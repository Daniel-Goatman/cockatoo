import Foundation
import CryptoKit

/// The versioned pack JSON produced by packtool
/// (docs/plan/07-content-pipeline.md §Pack JSON schema).
public struct PackFile: Codable, Equatable, Sendable {
    public var schema: Int
    public var language: String
    public var version: String
    public var provenance: Provenance
    public var grading: GradingConfig
    public var items: [VocabItem]

    public struct Provenance: Codable, Equatable, Sendable {
        public var corpus: String
        public var license: String
        public var packtool: String
        public var authoringModel: String?
        public var generatedAt: String

        public init(corpus: String, license: String, packtool: String, authoringModel: String? = nil, generatedAt: String) {
            self.corpus = corpus
            self.license = license
            self.packtool = packtool
            self.authoringModel = authoringModel
            self.generatedAt = generatedAt
        }
    }

    public init(
        schema: Int = 1,
        language: String,
        version: String,
        provenance: Provenance,
        grading: GradingConfig,
        items: [VocabItem]
    ) {
        self.schema = schema
        self.language = language
        self.version = version
        self.provenance = provenance
        self.grading = grading
        self.items = items
    }

    public static func load(from url: URL) throws -> PackFile {
        try JSONCoding.decoder.decode(PackFile.self, from: Data(contentsOf: url))
    }

    public static func checksum(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
