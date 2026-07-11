import Foundation
import GRDB

/// Well-known settings keys. Nothing learning-related lives in UserDefaults.
public enum SettingsKey {
    public static let snapshotVersion = "snapshotVersion"
    public static let activeLanguage = "activeLanguage"
    public static let enabled = "enabled"
    public static let blockedHosts = "blockedHosts" // JSON array of strings
    public static let pageContextOptIn = "pageContextOptIn"
    public static let unlockedTier = "unlockedTier"
    public static func tierUnlockedAt(_ tier: Int) -> String { "tierUnlockedAt.\(tier)" }
}

/// Data-access facade over the database. All engine components go through
/// this; the Store API stays behind this type so even a transport change
/// (XPC fallback scenarios) touches no callers.
public struct LearnerStore: Sendable {
    public let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Items

    public func items(language: String) throws -> [VocabItem] {
        try db.writer.read { dbc in
            try VocabItemRecord
                .filter(Column("language") == language)
                .order(Column("frequencyBand"), Column("id"))
                .fetchAll(dbc)
        }.map { try $0.item() }
    }

    public func item(id: String) throws -> VocabItem? {
        try db.writer.read { dbc in
            try VocabItemRecord.fetchOne(dbc, key: id)
        }.map { try $0.item() }
    }

    // MARK: - Progress

    public func progress(itemId: String) throws -> ItemProgress? {
        try db.writer.read { dbc in try ItemProgress.fetchOne(dbc, key: itemId) }
    }

    public func allProgress() throws -> [String: ItemProgress] {
        let rows = try db.writer.read { dbc in try ItemProgress.fetchAll(dbc) }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.itemId, $0) })
    }

    public func saveProgress(_ progress: ItemProgress) throws {
        try db.writer.write { dbc in try progress.save(dbc) }
    }

    // MARK: - Sentences

    public func sentences(itemId: String) throws -> [CapturedSentence] {
        try db.writer.read { dbc in
            try CapturedSentence
                .filter(Column("itemId") == itemId)
                .order(Column("capturedAt").desc)
                .fetchAll(dbc)
        }
    }

    // MARK: - Enrichment

    public func enrichment(itemId: String, kind: String, cacheKey: String) throws -> EnrichmentRecord? {
        try db.writer.read { dbc in
            try EnrichmentRecord.fetchOne(dbc, key: ["itemId": itemId, "kind": kind, "cacheKey": cacheKey])
        }
    }

    public func saveEnrichment(_ record: EnrichmentRecord) throws {
        try db.writer.write { dbc in try record.save(dbc) }
    }

    // MARK: - Settings

    public func setting(_ key: String) throws -> String? {
        try db.writer.read { dbc in try SettingRecord.fetchOne(dbc, key: key)?.value }
    }

    public func setSetting(_ key: String, _ value: String) throws {
        try db.writer.write { dbc in try SettingRecord(key: key, value: value).save(dbc) }
    }

    public func snapshotVersion() throws -> Int {
        Int(try setting(SettingsKey.snapshotVersion) ?? "0") ?? 0
    }

    /// Any progress/settings/pack change bumps the version so the extension's
    /// piggyback freshness check notices (docs/plan/05-extension.md).
    @discardableResult
    public func bumpSnapshotVersion(_ dbc: Database) throws -> Int {
        let current = Int(try SettingRecord.fetchOne(dbc, key: SettingsKey.snapshotVersion)?.value ?? "0") ?? 0
        let next = current + 1
        try SettingRecord(key: SettingsKey.snapshotVersion, value: String(next)).save(dbc)
        return next
    }

    public func blockedHosts() throws -> [String] {
        guard let json = try setting(SettingsKey.blockedHosts) else { return [] }
        return (try? JSONCoding.decoder.decode([String].self, from: Data(json.utf8))) ?? []
    }

    public func setBlockedHosts(_ hosts: [String]) throws {
        let json = String(data: try JSONCoding.encoder.encode(hosts), encoding: .utf8)!
        try db.writer.write { dbc in
            try SettingRecord(key: SettingsKey.blockedHosts, value: json).save(dbc)
            try bumpSnapshotVersion(dbc)
        }
    }

    // MARK: - Packs

    /// The most recently imported pack version for a language — lets the
    /// app upgrade to a newer bundled pack on launch (upsert import keeps
    /// all progress; stable IDs are validator-enforced).
    public func latestPackVersion(language: String) throws -> String? {
        try db.writer.read { dbc in
            try PackRecord
                .filter(Column("language") == language)
                .order(Column("importedAt").desc)
                .fetchOne(dbc)?
                .version
        }
    }

    // MARK: - Diagnostics

    /// When the last exposure event was ingested — the honest answer to
    /// "is the extension actually syncing?".
    public func lastEventProcessedAt() throws -> Date? {
        try db.writer.read { dbc in
            try Date.fetchOne(dbc, sql: "SELECT MAX(processedAt) FROM exposure_event")
        }
    }

    /// Today's raw exposure events per item — what the daily crediting caps
    /// compare against. Lets the UI say "done for today" instead of
    /// promising sightings that won't credit.
    public func exposureCountsToday(now: Date) throws -> [String: (seen: Int, engaged: Int)] {
        let dayStart = Calendar(identifier: .gregorian).startOfDay(for: now)
        let rows = try db.writer.read { dbc in
            try Row.fetchAll(dbc, sql: """
                SELECT itemId,
                       SUM(CASE WHEN type = 'seen' THEN 1 ELSE 0 END) AS seen,
                       SUM(CASE WHEN type IN ('engaged', 'pinned') THEN 1 ELSE 0 END) AS engaged
                FROM exposure_event
                WHERE occurredAt >= ?
                GROUP BY itemId
                """, arguments: [dayStart])
        }
        return Dictionary(uniqueKeysWithValues: rows.map {
            ($0["itemId"] as String, (seen: $0["seen"] as Int, engaged: $0["engaged"] as Int))
        })
    }

    // MARK: - Maintenance

    /// Prune processed events older than the retention window and enforce
    /// sentence caps (docs/plan/03-data-model-and-storage.md §lifecycle).
    public func prune(now: Date, config: EngineConfig = .default) throws {
        try db.writer.write { dbc in
            let cutoff = now.addingTimeInterval(-Double(config.eventRetentionDays) * 24 * 3600)
            try dbc.execute(
                sql: "DELETE FROM exposure_event WHERE processedAt IS NOT NULL AND occurredAt < ?",
                arguments: [cutoff]
            )
            // Per-item sentence cap: keep the newest N per item.
            try dbc.execute(sql: """
                DELETE FROM captured_sentence WHERE id IN (
                  SELECT id FROM (
                    SELECT id, ROW_NUMBER() OVER (
                      PARTITION BY itemId ORDER BY capturedAt DESC
                    ) AS rn FROM captured_sentence
                  ) WHERE rn > ?
                )
                """, arguments: [config.sentencesPerItemCap])
        }
    }
}
