import Foundation
import GRDB

// GRDB record conformances live here so Domain stays persistence-free.

struct VocabItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "vocab_item"

    var id: String
    var language: String
    var kind: String
    var frequencyBand: Int
    var replacementPolicy: String
    var fidelityTier: String
    var packVersion: String
    var json: String

    init(item: VocabItem, packVersion: String) throws {
        self.id = item.id
        self.language = item.language
        self.kind = item.kind.rawValue
        self.frequencyBand = item.frequencyBand
        self.replacementPolicy = item.replacementPolicy.rawValue
        self.fidelityTier = item.fidelityTier.rawValue
        self.packVersion = packVersion
        self.json = String(data: try JSONCoding.encoder.encode(item), encoding: .utf8)!
    }

    func item() throws -> VocabItem {
        try JSONCoding.decoder.decode(VocabItem.self, from: Data(json.utf8))
    }
}

extension ItemProgress: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "item_progress"
}

struct ExposureEventRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "exposure_event"

    var id: String
    var itemId: String
    var type: String
    var occurredAt: Date
    var host: String?
    var processedAt: Date?
}

extension CapturedSentence: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "captured_sentence"
}

struct PackRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pack"

    var language: String
    var version: String
    var checksum: String
    var provenance: String
    var gradingJSON: String
    var importedAt: Date
}

public struct EnrichmentRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "enrichment"

    public var itemId: String
    public var kind: String
    public var cacheKey: String
    public var contentJSON: String
    public var model: String
    public var createdAt: Date

    public init(itemId: String, kind: String, cacheKey: String, contentJSON: String, model: String, createdAt: Date) {
        self.itemId = itemId
        self.kind = kind
        self.cacheKey = cacheKey
        self.contentJSON = contentJSON
        self.model = model
        self.createdAt = createdAt
    }
}

struct SettingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "settings"
    var key: String
    var value: String
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso8601Plain = ISO8601DateFormatter()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // JS Date.toISOString() emits fractional seconds; Swift's stock
        // .iso8601 strategy rejects them. Accept both (regression: every
        // real postEvents batch once failed as internalError over this).
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601Fractional.date(from: string) ?? iso8601Plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid ISO-8601 date: \(string)")
        }
        return d
    }()
}
