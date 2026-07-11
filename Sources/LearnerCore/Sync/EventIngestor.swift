import Foundation
import GRDB

/// Ingests exposure event batches in one transaction: insert (ignoring
/// duplicate UUIDs — idempotency, R5), fold into item_progress with daily
/// caps, fire ambient → ready transitions, run activation, bump the
/// snapshot version.
public struct EventIngestor: Sendable {
    public var config: EngineConfig
    public var activation: ActivationEngine

    public init(config: EngineConfig = .default) {
        self.config = config
        self.activation = ActivationEngine(config: config)
    }

    public struct Outcome: Equatable, Sendable {
        public var accepted: Int
        public var duplicates: Int
        public var latestVersion: Int
    }

    @discardableResult
    public func ingest(_ events: [ExposureEvent], store: LearnerStore, now: Date) throws -> Outcome {
        try store.db.writer.write { dbc in
            var accepted = 0
            var duplicates = 0
            var touchedProgress = false

            for event in events {
                let exists = try ExposureEventRecord.fetchOne(dbc, key: event.id) != nil
                if exists {
                    duplicates += 1
                    continue
                }
                try ExposureEventRecord(
                    id: event.id,
                    itemId: event.itemId,
                    type: event.type.rawValue,
                    occurredAt: event.occurredAt,
                    host: event.host,
                    processedAt: now
                ).insert(dbc)
                accepted += 1

                if try apply(event: event, dbc: dbc, now: now) {
                    touchedProgress = true
                }
            }

            if touchedProgress {
                try runActivation(dbc: dbc, now: now)
            }

            let version: Int
            if accepted > 0 {
                version = try store.bumpSnapshotVersion(dbc)
            } else {
                version = Int(try SettingRecord.fetchOne(dbc, key: SettingsKey.snapshotVersion)?.value ?? "0") ?? 0
            }
            return Outcome(accepted: accepted, duplicates: duplicates, latestVersion: version)
        }
    }

    /// Returns true if progress changed.
    func apply(event: ExposureEvent, dbc: Database, now: Date) throws -> Bool {
        if event.type == .sentenceCaptured {
            guard let text = event.sentence, !text.isEmpty else { return false }
            try CapturedSentence(
                id: event.id,
                itemId: event.itemId,
                text: text,
                sourceHost: event.host,
                capturedAt: event.occurredAt
            ).insert(dbc)
            return false // no progress credit for sentence capture
        }

        guard var p = try ItemProgress.fetchOne(dbc, key: event.itemId) else { return false }
        // Exposure only credits items in the ambient window.
        guard p.stage == .ambient || p.stage == .ready else { return false }

        let dayStart = Calendar(identifier: .gregorian).startOfDay(for: event.occurredAt)
        switch event.type {
        case .seen:
            let todayCount = try creditedCount(dbc: dbc, itemId: event.itemId, types: ["seen"], since: dayStart, excluding: event.id)
            guard todayCount < config.seenCreditDailyCap else { return false }
            p.seenCount += 1
        case .engaged, .pinned:
            let todayCount = try creditedCount(dbc: dbc, itemId: event.itemId, types: ["engaged", "pinned"], since: dayStart, excluding: event.id)
            guard todayCount < config.engagedCreditDailyCap else { return false }
            p.engagedCount += 1
        case .sentenceCaptured:
            return false
        }

        // Transition b: ambient → ready on exposure thresholds.
        if p.stage == .ambient,
           p.seenCount >= config.readySeenThreshold,
           p.engagedCount >= config.readyEngagedThreshold {
            p.stage = .ready
        }
        p.updatedAt = now
        try p.save(dbc)
        return true
    }

    /// Events already credited today for the item (the current event is
    /// already inserted, so exclude it from the count).
    func creditedCount(dbc: Database, itemId: String, types: [String], since: Date, excluding eventId: String) throws -> Int {
        try Int.fetchOne(dbc, sql: """
            SELECT COUNT(*) FROM exposure_event
            WHERE itemId = ? AND type IN (\(types.map { "'\($0)'" }.joined(separator: ",")))
              AND occurredAt >= ? AND id != ?
            """, arguments: [itemId, since, eventId]) ?? 0
    }

    /// Promote locked → ambient per ActivationEngine; unlock tiers.
    func runActivation(dbc: Database, now: Date) throws {
        let language = try SettingRecord.fetchOne(dbc, key: SettingsKey.activeLanguage)?.value ?? "de"
        let itemRecords = try VocabItemRecord.filter(Column("language") == language).fetchAll(dbc)
        let items = try itemRecords.map { try $0.item() }
        var progress = Dictionary(uniqueKeysWithValues: try ItemProgress.fetchAll(dbc).map { ($0.itemId, $0) })

        var unlockedTier = Int(try SettingRecord.fetchOne(dbc, key: SettingsKey.unlockedTier)?.value ?? "1") ?? 1
        let unlockedAtRaw = try SettingRecord.fetchOne(dbc, key: SettingsKey.tierUnlockedAt(unlockedTier))?.value
        let unlockedAt = unlockedAtRaw.flatMap { ISO8601DateFormatter().date(from: $0) }

        let tierState = ActivationEngine.TierState(unlockedTier: unlockedTier, unlockedAt: unlockedAt)
        if activation.shouldUnlockNextTier(items: items, progress: progress, tier: tierState, now: now) {
            unlockedTier += 1
            try SettingRecord(key: SettingsKey.unlockedTier, value: String(unlockedTier)).save(dbc)
            try SettingRecord(
                key: SettingsKey.tierUnlockedAt(unlockedTier),
                value: ISO8601DateFormatter().string(from: now)
            ).save(dbc)
        }

        for id in activation.admissions(items: items, progress: progress, unlockedTier: unlockedTier) {
            var p = progress[id] ?? ItemProgress(itemId: id, now: now)
            p.stage = .ambient
            p.activatedAt = now
            p.updatedAt = now
            try p.save(dbc)
            progress[id] = p
        }
    }
}
