import SwiftUI
import Combine
import LearnerCore
import GRDB

/// The app-side view model over LearnerEngine. The app owns the database
/// exclusively (D9); GRDB ValueObservation drives live UI updates.
@MainActor
final class AppModel: ObservableObject {
    let engine: LearnerEngine
    private var xpcListener: CockatooXPCListener?
    private var observation: AnyDatabaseCancellable?

    @Published var section: AppSection? = .dashboard
    /// Chrome layout: at the base window size the two side panels don't both
    /// fit, so opening one collapses the other (chevron toggles in the UI).
    @Published var sidebarCollapsed = false
    @Published var practiceInspectorOpen = false
    @Published var overview: LearnerEngine.Overview?
    @Published var needsOnboarding = false
    @Published var paused = false
    @Published var lastError: String?
    /// Last time the Safari extension reached us over IPC (this launch).
    @Published var lastExtensionContact: Date?
    /// Bumped on every database change — views whose data isn't covered by
    /// Overview equality (e.g. Library's per-item seen counts) reload on it.
    @Published var dbGeneration = 0

    /// Practice session state — owned here so it survives section switches.
    lazy var practice = PracticeSessionModel(engine: engine)

    private var contactObserver: NSObjectProtocol?

    init() {
        do {
            let db = try AppDatabase.onDisk(at: CockatooPaths.databaseURL())
            engine = LearnerEngine(store: LearnerStore(db: db))
        } catch {
            fatalError("cannot open database: \(error)")
        }

        refresh()
        needsOnboarding = (overview?.totalItems ?? 0) == 0
        paused = (try? engine.store.setting(SettingsKey.enabled)) == "false"
        upgradeBundledPackIfNeeded()
        startObservation()
        startXPC()
        contactObserver = NotificationCenter.default.addObserver(
            forName: .cockatooExtensionContact, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lastExtensionContact = Date() }
        }
    }

    /// Live UI: re-run queries whenever any tracked table changes.
    private func startObservation() {
        let observation = DatabaseRegionObservation(tracking: .fullDatabase)
        self.observation = observation.start(
            in: engine.store.db.writer,
            onError: { [weak self] error in
                Task { @MainActor in self?.lastError = "\(error)" }
            },
            onChange: { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                    self?.dbGeneration += 1
                }
            }
        )
    }

    private func startXPC() {
        let service = SyncService(engine: engine, contextualForm: makeContextualFormResolver())
        xpcListener = CockatooXPCListener(service: service)
        xpcListener?.start()
    }

    func refresh() {
        overview = try? engine.overview(now: Date())
    }

    func toggleSidebar() {
        sidebarCollapsed.toggle()
        if !sidebarCollapsed { practiceInspectorOpen = false }
    }

    func togglePracticeInspector() {
        practiceInspectorOpen.toggle()
        if practiceInspectorOpen { sidebarCollapsed = true }
    }

    /// Menu bar badge: actionable reviews (due + ready). Introductions are
    /// deliberately excluded — an always-on badge is nagging, not a signal.
    var dueBadge: String {
        let actionable = (overview?.dueNow ?? 0) + (overview?.readyCount ?? 0)
        guard actionable > 0 else { return "" }
        return "\(actionable)"
    }

    func togglePaused() {
        paused.toggle()
        try? engine.store.setSetting(SettingsKey.enabled, paused ? "false" : "true")
        _ = try? engine.store.db.writer.write { dbc in
            try engine.store.bumpSnapshotVersion(dbc)
        }
    }

    func importPack(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let pack = try decoder.decode(PackFile.self, from: data)
            try engine.importPack(pack, rawData: data, now: Date())
            needsOnboarding = false
            lastError = nil
            refresh()
        } catch {
            lastError = "Import failed: \(error)"
        }
    }

    /// The starter pack ships in the app bundle so first run is one click —
    /// no file picker, no dev workflow leaking into onboarding. Found by
    /// prefix so pack version bumps don't need code changes.
    static func bundledPackURL() -> URL? {
        var candidates: [URL] = []
        #if SWIFT_PACKAGE
        candidates += Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Resources") ?? []
        #endif
        candidates += Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return candidates
            .filter { $0.lastPathComponent.hasPrefix("de-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // newest version wins
            .first
    }

    func importBundledPack() {
        guard let url = Self.bundledPackURL() else {
            lastError = "The built-in pack is missing from this build — use Import a custom pack instead."
            return
        }
        importPack(from: url)
    }

    /// Pack updates ship with the app: when the bundled pack is a different
    /// version than the imported one, upgrade on launch. The importer
    /// upserts by stable ID, so all progress is preserved (and the
    /// validator blocks any pack that drops an existing ID).
    func upgradeBundledPackIfNeeded() {
        guard !needsOnboarding, let url = Self.bundledPackURL() else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let pack = try decoder.decode(PackFile.self, from: data)
            let installed = try engine.store.latestPackVersion(language: pack.language)
            guard let installed, installed != pack.version else { return }
            try engine.importPack(pack, rawData: data, now: Date())
            NSLog("Cockatoo: upgraded \(pack.language) pack \(installed) → \(pack.version)")
            refresh()
        } catch {
            NSLog("Cockatoo: bundled pack upgrade failed: \(error)")
        }
    }

    // MARK: - LLM

    var providerConfig: OpenAICompatClient.Config? {
        guard let baseURL = try? engine.store.setting("llm.baseURL"),
              let model = try? engine.store.setting("llm.model"),
              let url = URL(string: baseURL), !model.isEmpty else { return nil }
        return OpenAICompatClient.Config(
            baseURL: url,
            apiKey: KeychainStore.read(key: "llm.apiKey"),
            model: model
        )
    }

    func makeGateway() -> LLMGateway {
        let provider = providerConfig.map { OpenAICompatClient(config: $0) }
        let store = engine.store
        return LLMGateway(provider: provider) {
            (try? store.setting(SettingsKey.pageContextOptIn)) == "true"
        }
    }

    private func makeContextualFormResolver() -> (@Sendable (GetContextualFormRequest) throws -> String)? {
        guard let config = providerConfig else { return nil }
        let store = engine.store
        let gateway = LLMGateway(provider: OpenAICompatClient(config: config)) {
            (try? store.setting(SettingsKey.pageContextOptIn)) == "true"
        }
        let feature = ContextualFormFeature(gateway: gateway, store: store)
        return { request in
            guard let item = try store.item(id: request.itemId) else {
                throw LLMError.malformedOutput("unknown item")
            }
            // Bridge async resolve for the synchronous XPC handler with the
            // authored-form fallback (never blocks rendering: the extension
            // shows the authored form immediately and upgrades if we answer).
            let semaphore = DispatchSemaphore(value: 0)
            let box = ResultBox()
            Task {
                box.value = try? await feature.resolve(
                    item: item, sentence: request.sentence,
                    languageName: "German", now: Date()
                )
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 8)
            guard let form = box.value else { throw LLMError.transport("resolver timeout") }
            return form
        }
    }
}

final class ResultBox: @unchecked Sendable {
    var value: String?
}
