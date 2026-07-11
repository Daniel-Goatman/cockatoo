import Foundation
import GRDB

/// The single database, owned exclusively by the app process (decision D9).
/// The appex never opens this — it reaches data through the app's XPC API.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// On-disk database (WAL) at the given URL, creating parent directories.
    public static func onDisk(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.busyMode = .timeout(2.0)
        let pool = try DatabasePool(path: url.path, configuration: config)
        return try AppDatabase(writer: pool)
    }

    /// In-memory database for tests and simulation.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    /// Numbered, append-only migrations. No decode-time migration logic
    /// anywhere else (docs/plan/03-data-model-and-storage.md).
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "pack") { t in
                t.column("language", .text).notNull()
                t.column("version", .text).notNull()
                t.column("checksum", .text).notNull()
                t.column("provenance", .text).notNull()
                t.column("gradingJSON", .text).notNull()
                t.column("importedAt", .text).notNull()
                t.primaryKey(["language", "version"])
            }

            // Indexed scalar columns + the full item as JSON. Queries only
            // ever filter on the indexed columns.
            try db.create(table: "vocab_item") { t in
                t.column("id", .text).primaryKey()
                t.column("language", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("frequencyBand", .integer).notNull()
                t.column("replacementPolicy", .text).notNull()
                t.column("fidelityTier", .text).notNull()
                t.column("packVersion", .text).notNull()
                t.column("json", .text).notNull()
            }
            try db.create(index: "idx_item_band", on: "vocab_item", columns: ["language", "frequencyBand"])

            try db.create(table: "item_progress") { t in
                t.column("itemId", .text).primaryKey()
                t.column("stage", .text).notNull().defaults(to: "locked")
                t.column("srsBox", .integer).notNull().defaults(to: 0)
                t.column("dueAt", .datetime)
                t.column("seenCount", .integer).notNull().defaults(to: 0)
                t.column("engagedCount", .integer).notNull().defaults(to: 0)
                t.column("correctStreak", .integer).notNull().defaults(to: 0)
                t.column("lapses", .integer).notNull().defaults(to: 0)
                t.column("recognitionCorrect", .integer).notNull().defaults(to: 0)
                t.column("recallCorrect", .integer).notNull().defaults(to: 0)
                t.column("clozeCorrect", .integer).notNull().defaults(to: 0)
                t.column("activatedAt", .datetime)
                t.column("lastResultAt", .datetime)
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_progress_due", on: "item_progress", columns: ["stage", "dueAt"])

            try db.create(table: "exposure_event") { t in
                t.column("id", .text).primaryKey()
                t.column("itemId", .text).notNull()
                t.column("type", .text).notNull()
                t.column("occurredAt", .datetime).notNull()
                t.column("host", .text)
                t.column("processedAt", .datetime)
            }
            try db.create(index: "idx_event_unprocessed", on: "exposure_event", columns: ["processedAt"])

            try db.create(table: "captured_sentence") { t in
                t.column("id", .text).primaryKey()
                t.column("itemId", .text).notNull()
                t.column("text", .text).notNull()
                t.column("sourceHost", .text)
                t.column("capturedAt", .datetime).notNull()
            }
            try db.create(index: "idx_sentence_item", on: "captured_sentence", columns: ["itemId"])

            try db.create(table: "enrichment") { t in
                t.column("itemId", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("cacheKey", .text).notNull()
                t.column("contentJSON", .text).notNull()
                t.column("model", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["itemId", "kind", "cacheKey"])
            }

            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        return migrator
    }
}
