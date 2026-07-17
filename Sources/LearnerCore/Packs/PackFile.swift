import Foundation
import CryptoKit

/// The versioned pack JSON produced by packtool
/// (docs/plan/07-content-pipeline.md §Pack JSON schema).
public struct PackFile: Codable, Equatable, Sendable {
    public var schema: Int
    /// BCP 47 language of the pages being read, currently usually `en`.
    public var sourceLanguage: String
    /// BCP 47 target language taught by this pack.
    public var language: String
    public var version: String
    public var provenance: Provenance
    public var grading: GradingConfig
    public var validation: PackValidationConfig
    public var items: [VocabItem]

    public struct Provenance: Codable, Equatable, Sendable {
        public var corpus: String
        public var corpusVersion: String?
        public var corpusURL: String?
        public var license: String
        public var packtool: String
        public var authoringModel: String?
        public var promptVersion: String?
        public var inputChecksum: String?
        public var generatedAt: String

        public init(
            corpus: String,
            corpusVersion: String? = nil,
            corpusURL: String? = nil,
            license: String,
            packtool: String,
            authoringModel: String? = nil,
            promptVersion: String? = nil,
            inputChecksum: String? = nil,
            generatedAt: String
        ) {
            self.corpus = corpus
            self.corpusVersion = corpusVersion
            self.corpusURL = corpusURL
            self.license = license
            self.packtool = packtool
            self.authoringModel = authoringModel
            self.promptVersion = promptVersion
            self.inputChecksum = inputChecksum
            self.generatedAt = generatedAt
        }
    }

    public init(
        schema: Int = 2,
        sourceLanguage: String = "en",
        language: String,
        version: String,
        provenance: Provenance,
        grading: GradingConfig,
        validation: PackValidationConfig = .englishSourceV1,
        items: [VocabItem]
    ) {
        self.schema = schema
        self.sourceLanguage = sourceLanguage
        self.language = language
        self.version = version
        self.provenance = provenance
        self.grading = grading
        self.validation = validation
        self.items = items
    }

    public static func load(from url: URL) throws -> PackFile {
        try JSONCoding.decoder.decode(PackFile.self, from: Data(contentsOf: url))
    }

    public static func checksum(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Stable emission used by reviewed source builds. Formatting and key
    /// order are part of the reproducibility contract.
    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}

/// Source-language and safety rules are pack data, never target-language
/// branches in LearnerCore or packtool.
public struct PackValidationConfig: Codable, Equatable, Sendable {
    public var sourceDeterminers: [String]
    public var nounPartsOfSpeech: [String]
    public var disallowedAmbientPartsOfSpeech: [String]
    public var allowApproximateAmbient: Bool

    public init(
        sourceDeterminers: [String],
        nounPartsOfSpeech: [String] = ["noun"],
        disallowedAmbientPartsOfSpeech: [String] = ["verb"],
        allowApproximateAmbient: Bool = false
    ) {
        self.sourceDeterminers = sourceDeterminers
        self.nounPartsOfSpeech = nounPartsOfSpeech
        self.disallowedAmbientPartsOfSpeech = disallowedAmbientPartsOfSpeech
        self.allowApproximateAmbient = allowApproximateAmbient
    }

    public static let englishSourceV1 = PackValidationConfig(sourceDeterminers: ["the", "a", "an"])
}

/// Separate, human-owned gate for accepted source. It is deliberately not
/// embedded in an agent draft and cannot be self-asserted by a provider.
public struct PackReviewRecord: Codable, Equatable, Sendable {
    public struct Checklist: Codable, Equatable, Sendable {
        public var translations: Bool
        public var sourceForms: Bool
        public var examples: Bool
        public var safety: Bool
        public var licensing: Bool

        public init(
            translations: Bool,
            sourceForms: Bool,
            examples: Bool,
            safety: Bool,
            licensing: Bool
        ) {
            self.translations = translations
            self.sourceForms = sourceForms
            self.examples = examples
            self.safety = safety
            self.licensing = licensing
        }

        public var isComplete: Bool {
            translations && sourceForms && examples && safety && licensing
        }
    }

    public var schema: Int
    public var language: String
    public var version: String
    public var sourceChecksum: String
    public var reviewer: String
    public var reviewedAt: String
    public var checklist: Checklist
    public var notes: String?

    public init(
        schema: Int = 1,
        language: String,
        version: String,
        sourceChecksum: String,
        reviewer: String,
        reviewedAt: String,
        checklist: Checklist,
        notes: String? = nil
    ) {
        self.schema = schema
        self.language = language
        self.version = version
        self.sourceChecksum = sourceChecksum
        self.reviewer = reviewer
        self.reviewedAt = reviewedAt
        self.checklist = checklist
        self.notes = notes
    }

    public func validate(for pack: PackFile, sourceData: Data) -> [String] {
        var failures: [String] = []
        if schema != 1 { failures.append("unsupported review schema \(schema)") }
        if language != pack.language { failures.append("review language does not match pack") }
        if version != pack.version { failures.append("review version does not match pack") }
        if sourceChecksum != PackFile.checksum(of: sourceData) { failures.append("review sourceChecksum does not match accepted source") }
        if reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { failures.append("reviewer is empty") }
        if reviewedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { failures.append("reviewedAt is empty") }
        if !checklist.isComplete { failures.append("human review checklist is incomplete") }
        return failures
    }
}
