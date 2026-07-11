import Foundation
import GRDB

/// Transactional pack import with stable-ID progress preservation
/// (docs/plan/03-data-model-and-storage.md §pack import and upgrade).
public struct PackImporter: Sendable {
    public init() {}

    public enum ImportError: Error, Equatable {
        case validationFailed([String])
        case checksumMismatch
    }

    @discardableResult
    public func importPack(
        _ pack: PackFile,
        rawData: Data? = nil,
        expectedChecksum: String? = nil,
        store: LearnerStore,
        now: Date
    ) throws -> Int {
        if let rawData, let expectedChecksum,
           PackFile.checksum(of: rawData) != expectedChecksum {
            throw ImportError.checksumMismatch
        }

        let report = PackValidator().validate(pack)
        guard report.isValid else {
            throw ImportError.validationFailed(report.failures)
        }

        return try store.db.writer.write { dbc in
            let newIds = Set(pack.items.map(\.id))

            // Upsert all items.
            for item in pack.items {
                try VocabItemRecord(item: item, packVersion: pack.version).save(dbc)
            }

            // Items absent from the new pack: delete if progress-free,
            // otherwise keep reviewable but never ambient.
            let existing = try VocabItemRecord
                .filter(Column("language") == pack.language)
                .fetchAll(dbc)
            for record in existing where !newIds.contains(record.id) {
                let hasProgress = try ItemProgress.fetchOne(dbc, key: record.id) != nil
                if hasProgress {
                    var item = try record.item()
                    item.replacementPolicy = .never
                    try VocabItemRecord(item: item, packVersion: record.packVersion).save(dbc)
                } else {
                    try record.delete(dbc)
                }
            }

            let gradingJSON = String(data: try JSONCoding.encoder.encode(pack.grading), encoding: .utf8)!
            let provenanceJSON = String(data: try JSONCoding.encoder.encode(pack.provenance), encoding: .utf8)!
            try PackRecord(
                language: pack.language,
                version: pack.version,
                checksum: expectedChecksum ?? rawData.map(PackFile.checksum(of:)) ?? "",
                provenance: provenanceJSON,
                gradingJSON: gradingJSON,
                importedAt: now
            ).save(dbc)

            if try SettingRecord.fetchOne(dbc, key: SettingsKey.activeLanguage) == nil {
                try SettingRecord(key: SettingsKey.activeLanguage, value: pack.language).save(dbc)
            }
            if try SettingRecord.fetchOne(dbc, key: SettingsKey.unlockedTier) == nil {
                try SettingRecord(key: SettingsKey.unlockedTier, value: "1").save(dbc)
                try SettingRecord(
                    key: SettingsKey.tierUnlockedAt(1),
                    value: ISO8601DateFormatter().string(from: now)
                ).save(dbc)
            }

            try LearnerStore(db: store.db).bumpSnapshotVersion(dbc)
            return pack.items.count
        }
    }

    /// The grading config for a language comes from its most recent pack.
    public func gradingConfig(language: String, store: LearnerStore) throws -> GradingConfig {
        let record = try store.db.writer.read { dbc in
            try PackRecord
                .filter(Column("language") == language)
                .order(Column("importedAt").desc)
                .fetchOne(dbc)
        }
        guard let record,
              let config = try? JSONCoding.decoder.decode(GradingConfig.self, from: Data(record.gradingJSON.utf8))
        else {
            return GradingConfig(articles: [])
        }
        return config
    }
}
