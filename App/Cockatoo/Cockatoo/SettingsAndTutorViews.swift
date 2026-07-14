import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import LearnerCore

// MARK: - Settings (provider config, privacy, How swapping works)

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var apiKey = ""
    @State private var pageContextOptIn = false
    @State private var blockedHostsText = ""
    @State private var testResult: String?
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var newPerDay = EngineConfig.default.newPerDay

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.system(size: 21, weight: .semibold))
                    .padding(.bottom, 4)

                settingSection("GENERAL") {
                    Toggle(isOn: $launchAtLogin) {
                        Text("Launch Cockatoo at login").font(.system(size: 13))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.goldDeep)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                    if let launchAtLoginError {
                        Text(launchAtLoginError).font(.caption).foregroundStyle(Theme.outcomeMissed)
                    }
                    caption("""
                    Recommended: the Safari extension reads its vocabulary from the app, \
                    so keeping Cockatoo running means swaps and progress sync are always live.
                    """)
                    Divider().overlay(Theme.line).padding(.vertical, 4)
                    Button("Import language pack…", action: pickPack)
                        .buttonStyle(.pill)
                    caption("Re-importing a newer pack version keeps all your progress — items match by stable ID.")
                }

                settingSection("PRACTICE") {
                    HStack(spacing: 12) {
                        Text("New words per day")
                            .font(.system(size: 13))
                        Stepper(value: $newPerDay, in: 1...20) {
                            Text("\(newPerDay)")
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .frame(width: 26, alignment: .trailing)
                        }
                        .onChange(of: newPerDay) {
                            try? model.engine.store.setSetting(SettingsKey.newPerDay, String(newPerDay))
                        }
                    }
                    caption("""
                    How many new words practice sessions introduce per day. Practice \
                    itself is unlimited — extra sessions re-run due reviews and \
                    reinforcement reps; a word's strength only climbs once per day, \
                    so volume never inflates progress. Introductions pause \
                    automatically while many reviews are due.
                    """)
                }

                settingSection("LANGUAGE MODEL · OPENAI-COMPATIBLE") {
                    fieldRow("Base URL") {
                        TextField("", text: $baseURL, prompt: Text("https://openrouter.ai/api/v1")).themeField()
                    }
                    fieldRow("Model") {
                        TextField("", text: $modelName, prompt: Text("e.g. anthropic/claude-sonnet-5")).themeField()
                    }
                    fieldRow("API key") {
                        SecureField("", text: $apiKey, prompt: Text("stored in the Keychain")).themeField()
                    }
                    HStack(spacing: 10) {
                        Button("Save") { save() }
                            .buttonStyle(.pillProminent)
                        Button("Test connection") { testConnection() }
                            .buttonStyle(.pill)
                            .disabled(baseURL.isEmpty || modelName.isEmpty)
                        if let testResult {
                            Text(testResult).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .padding(.top, 2)
                    caption("Works with OpenRouter, OpenAI, llama.cpp server (http://127.0.0.1:8080/v1) and Ollama (http://127.0.0.1:11434/v1).")
                }

                settingSection("PRIVACY") {
                    Toggle(isOn: $pageContextOptIn) {
                        Text("Allow sending page sentences to the model").font(.system(size: 13))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.goldDeep)
                    .onChange(of: pageContextOptIn) {
                        try? model.engine.store.setSetting(SettingsKey.pageContextOptIn, pageContextOptIn ? "true" : "false")
                    }
                    caption("""
                    Off (default): word swapping, hover, and reviews are fully local; only \
                    the tutor and word deep-dives use the model, and they send vocabulary \
                    words — never page text. On: sentences around a swapped word may be sent \
                    to your configured model to compute a better-inflected form. Enforced in \
                    the app, not just the UI.
                    """)
                }

                settingSection("BLOCKED SITES") {
                    TextField("", text: $blockedHostsText, prompt: Text("bank.com, mail.example.org"))
                        .themeField()
                        .onSubmit(saveBlockedHosts)
                    Button("Save blocked sites", action: saveBlockedHosts)
                        .buttonStyle(.pill)
                }

                settingSection("HOW SWAPPING WORKS") {
                    HowSwappingWorksView()
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .onAppear(perform: load)
        .navigationTitle("Settings")
    }

    func settingSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.monoLabel())
                .kerning(0.6)
                .foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(padding: 18)
    }

    func fieldRow(_ label: String, @ViewBuilder field: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 80, alignment: .leading)
            field()
        }
    }

    func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.inkFaint)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    func pickPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Cockatoo language pack (e.g. de-2026.07.json)"
        if panel.runModal() == .OK, let url = panel.url {
            model.importPack(from: url)
        }
    }

    func load() {
        baseURL = (try? model.engine.store.setting("llm.baseURL")) ?? ""
        modelName = (try? model.engine.store.setting("llm.model")) ?? ""
        apiKey = KeychainStore.read(key: "llm.apiKey") ?? ""
        pageContextOptIn = (try? model.engine.store.setting(SettingsKey.pageContextOptIn)) == "true"
        blockedHostsText = ((try? model.engine.store.blockedHosts()) ?? []).joined(separator: ", ")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        newPerDay = (try? model.engine.store.setting(SettingsKey.newPerDay))
            .flatMap { Int($0) } ?? EngineConfig.default.newPerDay
    }

    /// SMAppService requires a stable bundle path — effectively the
    /// /Applications copy installed by script/install.sh. From a DerivedData
    /// build the registration may fail; surface that instead of hiding it.
    func setLaunchAtLogin(_ enable: Bool) {
        launchAtLoginError = nil
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func save() {
        try? model.engine.store.setSetting("llm.baseURL", baseURL)
        try? model.engine.store.setSetting("llm.model", modelName)
        KeychainStore.write(key: "llm.apiKey", value: apiKey)
        testResult = "Saved."
    }

    func saveBlockedHosts() {
        let hosts = blockedHostsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        try? model.engine.store.setBlockedHosts(hosts)
    }

    func testConnection() {
        save()
        guard let config = model.providerConfig else {
            testResult = "Invalid configuration."
            return
        }
        testResult = "Testing…"
        Task {
            let client = OpenAICompatClient(config: config)
            switch await client.testConnection() {
            case .success(let latency):
                testResult = String(format: "OK — %.0f ms", latency * 1000)
            case .failure(let error):
                testResult = "Failed: \(error)"
            }
        }
    }
}

/// Fidelity-tier transparency requirement 3: the plain-language contract.
struct HowSwappingWorksView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("""
            Cockatoo swaps a small number of words on the pages you read — about one \
            per forty words, never in forms, code, or sensitive sites. Every swapped \
            word is marked with an underline, and hovering always shows the original \
            English. What a swap guarantees depends on its fidelity tier:
            """)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Exact").bold()
                    Text("Grammatically perfect — unchanging words like \"and\" → und.")
                }
                GridRow {
                    Text("Form-matched").bold()
                    Text("Word, article and number are right: \"the houses\" → die Häuser. Case agreement inside an English sentence is not attempted — the article you see is the dictionary form, which is exactly what's worth memorising.")
                }
                GridRow {
                    Text("Approximate").bold()
                    Text("Reserved for future word classes (verbs). Not used today; will carry a dotted underline.")
                }
            }
            Text("""
            New words enter through practice sessions, not through browsing — pages \
            then reinforce what you're learning. A word's strength climbs at most \
            once per calendar day and "known" takes correct answers on three \
            different days, so practicing a lot in one sitting sharpens words \
            without ever faking mastery. That's the spacing working, not a bug.
            """)
            Text("Words and genders first; grammar later — that's the deal, stated plainly.")
                .italic()
        }
        .font(.callout)
    }
}

// MARK: - Tutor

struct TutorView: View {
    @EnvironmentObject var model: AppModel
    @State private var messages: [(role: String, text: String)] = []
    @State private var input = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            if model.providerConfig == nil {
                ContentUnavailableView(
                    "No language model configured",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                    description: Text("Add an OpenAI-compatible endpoint in Settings. Everything else in Cockatoo works without one.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tutor")
                            .font(.system(size: 21, weight: .semibold))
                            .padding(.bottom, 4)
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            HStack {
                                if message.role == "user" { Spacer(minLength: 60) }
                                Text(message.text)
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 10)
                                    .background(
                                        message.role == "user" ? Theme.selection : Theme.cardBg,
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(message.role == "user" ? Theme.selectionLine : Theme.line)
                                    )
                                if message.role != "user" { Spacer(minLength: 60) }
                            }
                        }
                        if busy { ProgressView().controlSize(.small).padding(.leading, 8) }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }
                HStack(spacing: 10) {
                    TextField("Ask about a word, grammar, anything…", text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line2))
                        .onSubmit(send)
                    Button("Send", action: send)
                        .buttonStyle(.pillProminent)
                        .disabled(busy || input.isEmpty)
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Tutor")
    }

    func send() {
        let question = input.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty, !busy else { return }
        input = ""
        messages.append(("user", question))
        busy = true

        Task {
            defer { busy = false }
            do {
                let overview = try model.engine.overview(now: Date())
                let progress = try model.engine.store.allProgress()
                let weakIds = progress.values.sorted { $0.lapses > $1.lapses }.prefix(5).map(\.itemId)
                let weakItems = weakIds.compactMap { try? model.engine.store.item(id: $0) }.compactMap { $0 }
                let system = TutorPromptBuilder().systemPrompt(languageName: "German", overview: overview, weakItems: weakItems)

                var chat: [ChatMessage] = [.system(system)]
                for message in messages { chat.append(.init(role: message.role == "user" ? "user" : "assistant", content: message.text)) }

                let completion = try await model.makeGateway().complete(
                    tier: .sendsWordIds,
                    messages: chat,
                    options: CompletionOptions(maxTokens: 500, temperature: 0.4)
                )
                messages.append(("assistant", completion.text))
            } catch {
                messages.append(("assistant", "⚠️ The model is unreachable (\(error)). Your reviews and browsing all keep working — try again later or check Settings."))
            }
        }
    }
}
