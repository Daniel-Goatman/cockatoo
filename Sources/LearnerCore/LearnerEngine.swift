import Foundation
import GRDB

/// Top-level API surface: the app UI, the XPC listener, learnerctl, and the
/// simulated-learner tests all drive this one type.
public struct LearnerEngine: Sendable {
    public let store: LearnerStore
    public let config: EngineConfig
    public let ingestor: EventIngestor
    public let snapshotBuilder: SnapshotBuilder
    public let planner: SessionPlanner
    public let importer: PackImporter

    public init(store: LearnerStore, config: EngineConfig = .default) {
        self.store = store
        self.config = config
        self.ingestor = EventIngestor(config: config)
        self.snapshotBuilder = SnapshotBuilder(config: config)
        self.planner = SessionPlanner(config: config)
        self.importer = PackImporter()
    }

    // MARK: - Setup

    @discardableResult
    public func importPack(_ pack: PackFile, rawData: Data? = nil, now: Date) throws -> Int {
        let count = try importer.importPack(pack, rawData: rawData, store: store, now: now)
        try bootstrapActivation(now: now)
        return count
    }

    /// Initial locked → ambient admissions (there are no events yet to
    /// trigger activation, so run it once after import).
    public func bootstrapActivation(now: Date) throws {
        try store.db.writer.write { dbc in
            try ingestor.runActivation(dbc: dbc, now: now)
            try store.bumpSnapshotVersion(dbc)
        }
    }

    // MARK: - Extension-facing

    public func snapshot(sinceVersion: Int? = nil) throws -> GetSnapshotResponse {
        let current = try store.snapshotVersion()
        if let sinceVersion, sinceVersion == current {
            return .unchanged(version: current)
        }
        return .snapshot(try snapshotBuilder.build(store: store))
    }

    @discardableResult
    public func postEvents(_ events: [ExposureEvent], now: Date) throws -> PostEventsResponse {
        let outcome = try ingestor.ingest(events, store: store, now: now)
        return PostEventsResponse(accepted: outcome.accepted, latestVersion: outcome.latestVersion)
    }

    public func settingsResponse() throws -> GetSettingsResponse {
        GetSettingsResponse(
            enabled: (try store.setting(SettingsKey.enabled) ?? "true") == "true",
            blockedHosts: try store.blockedHosts(),
            pageContextOptIn: (try store.setting(SettingsKey.pageContextOptIn) ?? "false") == "true",
            activeLanguage: try store.setting(SettingsKey.activeLanguage) ?? "de"
        )
    }

    // MARK: - Practice

    public struct Session: Sendable {
        public var queue: [SessionPlanner.PlannedQuestion]
        public var grading: GradingConfig
    }

    public func planSession(now: Date, seed: UInt64) throws -> Session {
        let language = try store.setting(SettingsKey.activeLanguage) ?? "de"
        let items = try store.items(language: language)
        let progress = try store.allProgress()
        let selected = planner.selectItems(items: items, progress: progress, now: now)
        let queue = try planner.plan(
            items: selected,
            allItems: items,
            progress: progress,
            sentences: { try store.sentences(itemId: $0) },
            seed: seed
        )
        let grading = try importer.gradingConfig(language: language, store: store)
        return Session(queue: queue, grading: grading)
    }

    /// Grade an answered question, persist progress, bump snapshot version.
    @discardableResult
    public func grade(result: PracticeResult, now: Date) throws -> ItemProgress {
        let language = try store.setting(SettingsKey.activeLanguage) ?? "de"
        let grading = try importer.gradingConfig(language: language, store: store)
        let grader = Grader(config: config, grading: grading)

        return try store.db.writer.write { dbc in
            guard let progress = try ItemProgress.fetchOne(dbc, key: result.itemId) else {
                throw GradeError.unknownItem(result.itemId)
            }
            let updated = grader.apply(result: result, progress: progress, now: now)
            try updated.save(dbc)
            try ingestor.runActivation(dbc: dbc, now: now)
            try store.bumpSnapshotVersion(dbc)
            return updated
        }
    }

    public enum GradeError: Error, Equatable {
        case unknownItem(String)
    }

    // MARK: - Dashboard queries

    public struct Overview: Equatable, Sendable {
        public var unlockedTier: Int
        public var countsByStage: [Stage: Int]
        public var dueNow: Int
        public var totalItems: Int
    }

    public func overview(now: Date) throws -> Overview {
        let language = try store.setting(SettingsKey.activeLanguage) ?? "de"
        let items = try store.items(language: language)
        let progress = try store.allProgress()
        let scheduler = LeitnerScheduler(config: config)

        var counts: [Stage: Int] = [:]
        for item in items {
            let stage = progress[item.id]?.stage ?? .locked
            counts[stage, default: 0] += 1
        }
        let dueNow = progress.values.filter {
            ($0.stage == .learning || $0.stage == .known) && scheduler.isDue($0, now: now)
        }.count

        return Overview(
            unlockedTier: Int(try store.setting(SettingsKey.unlockedTier) ?? "1") ?? 1,
            countsByStage: counts,
            dueNow: dueNow,
            totalItems: items.count
        )
    }
}

/// Envelope-level dispatch shared by the XPC listener (and, through it, the
/// appex). Enforces protocolVersion and the sendsPageText gate server-side.
public struct SyncService: Sendable {
    public let engine: LearnerEngine
    /// Injected so the contextual-form feature stays optional (no provider
    /// configured → degrade, R8).
    public var contextualForm: (@Sendable (GetContextualFormRequest) throws -> String)?

    public init(engine: LearnerEngine, contextualForm: (@Sendable (GetContextualFormRequest) throws -> String)? = nil) {
        self.engine = engine
        self.contextualForm = contextualForm
    }

    public func handle(_ envelopeData: Data, now: Date) -> Data {
        do {
            let envelope = try JSONCoding.decoder.decode(MessageEnvelope.self, from: envelopeData)
            guard envelope.protocolVersion == SyncProtocol.version else {
                return encodeError(.protocolMismatch)
            }
            guard let method = SyncMethod(rawValue: envelope.method) else {
                return encodeError(.unknownMethod)
            }
            switch method {
            case .getSnapshot:
                let req = try decodePayload(GetSnapshotRequest.self, envelope) ?? GetSnapshotRequest()
                return try JSONCoding.encoder.encode(engine.snapshot(sinceVersion: req.sinceVersion))
            case .postEvents:
                guard let req = try decodePayload(PostEventsRequest.self, envelope) else {
                    return encodeError(.badPayload)
                }
                return try JSONCoding.encoder.encode(engine.postEvents(req.events, now: now))
            case .getSettings:
                return try JSONCoding.encoder.encode(engine.settingsResponse())
            case .getContextualForm:
                guard let req = try decodePayload(GetContextualFormRequest.self, envelope) else {
                    return encodeError(.badPayload)
                }
                // Server-side gate: never trust the extension's own check.
                let optedIn = (try engine.store.setting(SettingsKey.pageContextOptIn) ?? "false") == "true"
                guard optedIn else { return encodeError(.pageContextNotOptedIn) }
                guard let resolver = contextualForm else { return encodeError(.appUnavailable) }
                let form = try resolver(req)
                return try JSONCoding.encoder.encode(GetContextualFormResponse(form: form))
            case .openDashboard:
                // The app-side listener handles UI activation; core just acks.
                return Data("{}".utf8)
            }
        } catch {
            return encodeError(.internalError)
        }
    }

    func decodePayload<T: Decodable>(_ type: T.Type, _ envelope: MessageEnvelope) throws -> T? {
        guard let payload = envelope.payload else { return nil }
        return try JSONCoding.decoder.decode(T.self, from: payload)
    }

    func encodeError(_ error: SyncError) -> Data {
        (try? JSONCoding.encoder.encode(SyncErrorResponse(error: error))) ?? Data("{\"error\":\"internalError\"}".utf8)
    }
}
