import SwiftUI
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
    @Published var overview: LearnerEngine.Overview?
    @Published var needsOnboarding = false
    @Published var paused = false
    @Published var lastError: String?

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
        startObservation()
        startXPC()
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
                Task { @MainActor in self?.refresh() }
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

    var dueBadge: String {
        guard let due = overview?.dueNow, due > 0 else { return "" }
        return "\(due)"
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
            refresh()
        } catch {
            lastError = "Import failed: \(error)"
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
