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

    /// An ambient item's distance from `ready`, for "almost ready" UI.
    public struct ExposureNeed: Equatable, Sendable {
        public var itemId: String
        public var source: String
        public var target: String
        public var seenCount: Int
        public var engagedCount: Int
        /// Seen credits that make the item ready on their own.
        public var seenForReady: Int
        /// Seen credits that suffice once engagedForReady is also met.
        public var seenForFastReady: Int
        public var engagedForFastReady: Int
    }

    /// Progress toward unlocking the next tier, when one exists in the pack.
    public struct TierProgress: Equatable, Sendable {
        public var currentTier: Int
        public var nextTier: Int
        public var knownInCurrentTier: Int
        public var neededInCurrentTier: Int
        public var currentTierTotal: Int
    }

    public struct Overview: Equatable, Sendable {
        public var unlockedTier: Int
        public var countsByStage: [Stage: Int]
        public var dueNow: Int
        public var totalItems: Int
        /// Items awaiting their first question.
        public var readyCount: Int
        /// Ambient items an introduction question could bring into practice.
        public var introAvailable: Int
        /// The closest ambient items to becoming ready, nearest first.
        public var almostReady: [ExposureNeed]
        /// nil when the pack has no tier above the unlocked one.
        public var tierProgress: TierProgress?
        /// Earliest upcoming review among scheduled items (nil when none).
        public var nextDueAt: Date?

        /// Whether starting a practice session right now yields questions.
        public var practiceAvailable: Bool {
            dueNow + readyCount + introAvailable > 0
        }
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

        let ambientItems = items.filter { progress[$0.id]?.stage == .ambient }
        let almostReady = ambientItems
            .compactMap { item -> ExposureNeed? in
                guard let p = progress[item.id] else { return nil }
                return ExposureNeed(
                    itemId: item.id,
                    source: item.bareSourceForm ?? item.id,
                    target: item.displayTarget,
                    seenCount: p.seenCount,
                    engagedCount: p.engagedCount,
                    seenForReady: config.readySeenThreshold,
                    seenForFastReady: config.readySeenWithEngagementThreshold,
                    engagedForFastReady: config.readyEngagedThreshold
                )
            }
            .sorted { a, b in
                let ra = max(0, a.seenForReady - a.seenCount)
                let rb = max(0, b.seenForReady - b.seenCount)
                return ra == rb ? a.itemId < b.itemId : ra < rb
            }

        let unlockedTier = Int(try store.setting(SettingsKey.unlockedTier) ?? "1") ?? 1
        var tierProgress: TierProgress?
        let currentTierItems = items.filter { $0.frequencyBand == unlockedTier }
        if !currentTierItems.isEmpty,
           items.contains(where: { $0.frequencyBand == unlockedTier + 1 }) {
            let known = currentTierItems.filter { (progress[$0.id]?.stage ?? .locked) >= .known }.count
            let needed = Int((Double(currentTierItems.count) * config.tierUnlockFraction).rounded(.up))
            tierProgress = TierProgress(
                currentTier: unlockedTier,
                nextTier: unlockedTier + 1,
                knownInCurrentTier: known,
                neededInCurrentTier: needed,
                currentTierTotal: currentTierItems.count
            )
        }

        let nextDueAt = progress.values
            .filter { $0.stage >= .learning }
            .compactMap(\.dueAt)
            .filter { $0 > now }
            .min()

        return Overview(
            unlockedTier: unlockedTier,
            countsByStage: counts,
            dueNow: dueNow,
            totalItems: items.count,
            readyCount: counts[.ready] ?? 0,
            introAvailable: min(counts[.ambient] ?? 0, config.sessionIntroLimit),
            almostReady: Array(almostReady.prefix(3)),
            tierProgress: tierProgress,
            nextDueAt: nextDueAt
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
            return encodeError(.internalError, detail: String(describing: error).prefix(200).description)
        }
    }

    func decodePayload<T: Decodable>(_ type: T.Type, _ envelope: MessageEnvelope) throws -> T? {
        guard let payload = envelope.payload else { return nil }
        return try JSONCoding.decoder.decode(T.self, from: Data(payload.utf8))
    }

    func encodeError(_ error: SyncError, detail: String? = nil) -> Data {
        (try? JSONCoding.encoder.encode(SyncErrorResponse(error: error, detail: detail))) ?? Data("{\"error\":\"internalError\"}".utf8)
    }
}
