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
        try importer.importPack(pack, rawData: rawData, store: store, now: now)
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

    /// Config with the user-tunable knobs (newPerDay) resolved from settings.
    func effectiveConfig() throws -> EngineConfig {
        var effective = config
        if let raw = try store.setting(SettingsKey.newPerDay), let value = Int(raw) {
            effective.newPerDay = max(1, min(20, value))
        }
        return effective
    }

    public func planSession(now: Date, seed: UInt64) throws -> Session {
        let language = try store.setting(SettingsKey.activeLanguage) ?? "de"
        let items = try store.items(language: language)
        let progress = try store.allProgress()
        let planner = SessionPlanner(config: try effectiveConfig())
        let selection = planner.select(items: items, progress: progress, now: now)
        let queue = try planner.plan(
            selection: selection,
            allItems: items,
            progress: progress,
            sentences: { try store.sentences(itemId: $0) },
            seed: seed
        )
        let grading = try importer.gradingConfig(language: language, store: store)
        return Session(queue: queue, grading: grading)
    }

    /// Grade an answered question, persist progress, bump snapshot version.
    /// A first answer for an item CREATES its progress row — that is the
    /// moment the word enters the library (practice-first intake, D-R1).
    @discardableResult
    public func grade(result: PracticeResult, now: Date) throws -> ItemProgress {
        let language = try store.setting(SettingsKey.activeLanguage) ?? "de"
        let grading = try importer.gradingConfig(language: language, store: store)
        let grader = Grader(config: config, grading: grading)

        return try store.db.writer.write { dbc in
            let progress: ItemProgress
            if let existing = try ItemProgress.fetchOne(dbc, key: result.itemId) {
                progress = existing
            } else {
                guard try VocabItemRecord.fetchOne(dbc, key: result.itemId) != nil else {
                    throw GradeError.unknownItem(result.itemId)
                }
                progress = ItemProgress(itemId: result.itemId, now: now)
            }
            let updated = grader.apply(result: result, progress: progress, now: now)
            try updated.save(dbc)
            try store.bumpSnapshotVersion(dbc)
            return updated
        }
    }

    public enum GradeError: Error, Equatable {
        case unknownItem(String)
    }

    // MARK: - Milestones (non-gating band completions, D-R3)

    /// The lowest band that has crossed the milestone fraction but hasn't
    /// been celebrated yet. The UI shows the moment, then marks it.
    public func pendingMilestone(now: Date) throws -> Int? {
        let language = try store.setting(SettingsKey.activeLanguage) ?? "de"
        let items = try store.items(language: language)
        let progress = try store.allProgress()
        for band in planner.intake.bandProgress(items: items, progress: progress) where band.reached {
            if try store.setting(SettingsKey.milestoneCelebrated(band.band)) == nil {
                return band.band
            }
        }
        return nil
    }

    public func markMilestoneCelebrated(band: Int, now: Date) throws {
        try store.setSetting(
            SettingsKey.milestoneCelebrated(band),
            ISO8601DateFormatter().string(from: now)
        )
    }

    // MARK: - Dashboard queries

    /// Progress toward the next uncompleted band milestone.
    public struct MilestoneProgress: Equatable, Sendable {
        public var band: Int
        public var known: Int
        public var needed: Int
        public var total: Int
    }

    public struct Overview: Equatable, Sendable {
        public var countsByStage: [Stage: Int]
        public var totalItems: Int
        /// Items introduced into the library (= progress rows).
        public var libraryCount: Int
        public var dueNow: Int
        /// Words introduced today vs the daily intake budget.
        public var newToday: Int
        public var newPerDay: Int
        /// Introductions still available today (0 while review debt pauses
        /// intake or the budget is spent).
        public var newRemainingToday: Int
        /// Un-introduced items eligible for intake right now.
        public var introAvailable: Int
        /// The lowest band that hasn't completed its milestone (nil when
        /// every populated band has).
        public var nextMilestone: MilestoneProgress?
        /// A band milestone reached but not yet celebrated.
        public var pendingMilestoneBand: Int?
        /// Earliest upcoming review among library items (nil when none).
        public var nextDueAt: Date?
        /// When the last exposure event arrived from the extension (ever,
        /// not just this launch) — the sync-liveness signal.
        public var lastEventAt: Date?

        /// Practice is available whenever anything is in the library or
        /// anything can be introduced — sessions are never empty (D-R1).
        public var practiceAvailable: Bool {
            libraryCount > 0 || (introAvailable > 0 && newRemainingToday > 0)
        }
    }

    public func overview(now: Date) throws -> Overview {
        let language = try store.setting(SettingsKey.activeLanguage) ?? "de"
        let items = try store.items(language: language)
        let progress = try store.allProgress()
        let effective = try effectiveConfig()
        let scheduler = LeitnerScheduler(config: effective)
        let intake = IntakeEngine(config: effective)

        var counts: [Stage: Int] = [:]
        for p in progress.values {
            counts[p.stage, default: 0] += 1
        }
        let dueNow = progress.values.filter {
            ($0.stage == .learning || $0.stage == .known) && scheduler.isDue($0, now: now)
        }.count

        let dayStart = LearningCalendar.dayStart(of: now)
        let newToday = progress.values.filter { ($0.activatedAt ?? .distantPast) >= dayStart }.count
        let budget = intake.budget(progress: progress, dueNow: dueNow, now: now)
        let candidates = intake.candidates(items: items, progress: progress)

        let bands = intake.bandProgress(items: items, progress: progress)
        let nextMilestone = bands.first { !$0.reached }.map {
            MilestoneProgress(band: $0.band, known: $0.known, needed: $0.needed, total: $0.total)
        }
        var pendingMilestoneBand: Int?
        for band in bands where band.reached {
            if try store.setting(SettingsKey.milestoneCelebrated(band.band)) == nil {
                pendingMilestoneBand = band.band
                break
            }
        }

        let nextDueAt = progress.values
            .compactMap(\.dueAt)
            .filter { $0 > now }
            .min()

        return Overview(
            countsByStage: counts,
            totalItems: items.count,
            libraryCount: progress.count,
            dueNow: dueNow,
            newToday: newToday,
            newPerDay: effective.newPerDay,
            newRemainingToday: budget,
            introAvailable: candidates.count,
            nextMilestone: nextMilestone,
            pendingMilestoneBand: pendingMilestoneBand,
            nextDueAt: nextDueAt,
            lastEventAt: try store.lastEventProcessedAt()
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
