import Foundation

public enum ExposureEventType: String, Codable, CaseIterable, Sendable {
    case seen
    case engaged
    case pinned
    case sentenceCaptured
}

/// Append-only, idempotent-by-id exposure record emitted by the extension.
public struct ExposureEvent: Codable, Equatable, Identifiable, Sendable {
    /// Client-generated UUID string. Re-sent batches cannot double-credit (R5).
    public var id: String
    public var itemId: String
    public var type: ExposureEventType
    public var occurredAt: Date
    /// eTLD+1 only, optional.
    public var host: String?
    /// Present only for .sentenceCaptured.
    public var sentence: String?

    public init(
        id: String = UUID().uuidString,
        itemId: String,
        type: ExposureEventType,
        occurredAt: Date,
        host: String? = nil,
        sentence: String? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.type = type
        self.occurredAt = occurredAt
        self.host = host
        self.sentence = sentence
    }
}

/// Cloze material captured locally from browsing. It never leaves the device.
public struct CapturedSentence: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var itemId: String
    /// The sentence with the ORIGINAL English restored in place of the token.
    public var text: String
    public var sourceHost: String?
    public var capturedAt: Date

    public init(id: String = UUID().uuidString, itemId: String, text: String, sourceHost: String? = nil, capturedAt: Date) {
        self.id = id
        self.itemId = itemId
        self.text = text
        self.sourceHost = sourceHost
        self.capturedAt = capturedAt
    }
}
