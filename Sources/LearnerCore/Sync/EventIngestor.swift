import Foundation
import GRDB

/// Ingests exposure event batches in one transaction: insert (ignoring
/// duplicate UUIDs — idempotency, R5), fold sightings into item_progress
/// counters, bump the snapshot version.
///
/// Exposure is display-only ("seen in the wild") since the practice-first
/// redesign (docs/plan/10-learning-redesign.md D-R1): sightings never
/// change stage, box, or scheduling. Sentence captures still store cloze
/// material.
public struct EventIngestor: Sendable {
    public var config: EngineConfig

    public init(config: EngineConfig = .default) {
        self.config = config
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

                try apply(event: event, dbc: dbc, now: now)
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

    func apply(event: ExposureEvent, dbc: Database, now: Date) throws {
        if event.type == .sentenceCaptured {
            guard let text = event.sentence, !text.isEmpty,
                  text.count <= config.capturedSentenceMaxLength else { return }
            try CapturedSentence(
                id: event.id,
                itemId: event.itemId,
                text: text,
                sourceHost: event.host,
                capturedAt: event.occurredAt
            ).insert(dbc)
            return
        }

        // Sightings only count for library items (the swap set); an item
        // without a progress row hasn't been introduced yet.
        guard var p = try ItemProgress.fetchOne(dbc, key: event.itemId) else { return }
        switch event.type {
        case .seen:
            p.seenCount += 1
        case .engaged, .pinned:
            p.engagedCount += 1
        case .sentenceCaptured:
            return
        }
        p.updatedAt = now
        try p.save(dbc)
    }
}
