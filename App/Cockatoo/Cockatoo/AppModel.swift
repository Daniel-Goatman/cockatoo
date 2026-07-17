import SwiftUI
import Combine
import LearnerCore
import GRDB

/// The app-side view model over LearnerEngine. The app owns the database
/// exclusively (D9); GRDB ValueObservation drives live UI updates.
@MainActor
final class AppModel: ObservableObject {
    let engine: LearnerEngine
    private var ipcListener: CockatooIPCListener?
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
    @Published var installedLanguages: [String] = []
    @Published var activeLanguageCode: String?
    /// Item requested from an extension hover card. LibraryView uses this to
    /// reveal and highlight the matching row after the window is fronted.
    @Published var requestedLibraryItemID: String?

    /// Practice session state — owned here so it survives section switches.
    lazy var practice = PracticeSessionModel(engine: engine)

    private var contactObserver: NSObjectProtocol?
    private var openObserver: NSObjectProtocol?

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
        #if DEBUG
        // Visual QA hook: render first-run UI without deleting or mutating the
        // developer's real library (`swift run CockatooDev --show-onboarding`).
        if CommandLine.arguments.contains("--show-onboarding") {
            needsOnboarding = true
        }
        #endif
        startObservation()
        startIPC()
        contactObserver = NotificationCenter.default.addObserver(
            forName: .cockatooExtensionContact, object: nil, queue: .main
        ) { [weak self] _ in
            // NotificationCenter guarantees this closure runs on the main
            // operation queue selected above, which is the MainActor executor.
            MainActor.assumeIsolated {
                self?.lastExtensionContact = Date()
            }
        }
        openObserver = NotificationCenter.default.addObserver(
            forName: .cockatooOpenDashboard, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let request = notification.object as? OpenDashboardRequest else { return }
                switch request.destination {
                case .practice:
                    self?.section = .practice
                case .library:
                    self?.requestedLibraryItemID = request.itemId
                    self?.section = .library
                case nil:
                    break
                }
            }
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

    private func startIPC() {
        let service = SyncService(engine: engine)
        ipcListener = CockatooIPCListener(service: service)
        ipcListener?.start()
    }

    func refresh() {
        overview = try? engine.overview(now: Date())
        installedLanguages = (try? engine.store.installedLanguages()) ?? []
        activeLanguageCode = try? engine.store.setting(SettingsKey.activeLanguage)
    }

    func toggleSidebar() {
        sidebarCollapsed.toggle()
        if !sidebarCollapsed { practiceInspectorOpen = false }
    }

    func togglePracticeInspector() {
        practiceInspectorOpen.toggle()
        if practiceInspectorOpen { sidebarCollapsed = true }
    }

    /// User-facing language copy comes from the active/importable pack code,
    /// never from a target-language name embedded in a view.
    var targetLanguageName: String {
        let code = activeLanguageCode ?? Self.bundledPacks().first?.pack.language
        guard let code else { return "Target language" }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code.uppercased()
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
            let pack = try PackFile.load(from: url)
            try engine.importPack(pack, rawData: data, now: Date())
            // Import from the UI is explicit user intent to use this pack.
            // Background bundled-pack upgrades remain non-switching.
            try engine.store.activateLanguage(pack.language)
            practice.resetForLanguageChange()
            needsOnboarding = false
            lastError = nil
            refresh()
        } catch {
            lastError = "Import failed: \(error)"
        }
    }

    func activateLanguage(_ language: String) {
        guard language != activeLanguageCode else { return }
        do {
            try engine.store.activateLanguage(language)
            practice.resetForLanguageChange()
            lastError = nil
            refresh()
        } catch {
            lastError = "Couldn't switch language: \(error.localizedDescription)"
        }
    }

    /// The starter pack ships in the app bundle so first run is one click —
    /// no file picker, no dev workflow leaking into onboarding. Found by
    /// by decoding pack metadata so neither the filename nor a language code
    /// is hardwired into the app UI.
    static func bundledPacks() -> [(url: URL, pack: PackFile)] {
        var candidates: [URL] = []
        #if SWIFT_PACKAGE
        candidates += Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Resources") ?? []
        #endif
        candidates += Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let decoder = JSONDecoder()
        return candidates.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let pack = try? decoder.decode(PackFile.self, from: data) else { return nil }
            return (url, pack)
        }
    }

    static func bundledPackURL(language: String? = nil) -> URL? {
        let matching = bundledPacks().filter { language == nil || $0.pack.language == language }
        return matching.sorted { $0.pack.version > $1.pack.version }.first?.url
    }

    func importBundledPack() {
        guard let url = Self.bundledPackURL() else {
            lastError = "The built-in pack is missing from this build — use Import a custom pack instead."
            return
        }
        importPack(from: url)
    }

    /// Pack updates ship with the app: when the bundled pack has a different
    /// version or checksum than the imported one, upgrade on launch. The importer
    /// upserts by stable ID, so all progress is preserved (and the
    /// validator blocks any pack that drops an existing ID).
    func upgradeBundledPackIfNeeded() {
        guard let language = try? engine.store.setting(SettingsKey.activeLanguage),
              let url = Self.bundledPackURL(language: language) else { return }
        do {
            let data = try Data(contentsOf: url)
            let pack = try PackFile.load(from: url)
            let bundledChecksum = PackFile.checksum(of: data)
            let installed = try engine.store.latestPackIdentity(language: pack.language)
            guard installed?.version != pack.version || installed?.checksum != bundledChecksum else { return }
            try engine.importPack(pack, rawData: data, now: Date())
            NSLog("Cockatoo: upgraded \(pack.language) pack \(installed?.version ?? "none") → \(pack.version)")
            needsOnboarding = false
            refresh()
        } catch {
            NSLog("Cockatoo: bundled pack upgrade failed: \(error)")
        }
    }

}
