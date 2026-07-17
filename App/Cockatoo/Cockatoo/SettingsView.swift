import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import LearnerCore

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    @State private var blockedHostsText = ""
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
                    if !model.installedLanguages.isEmpty {
                        Picker("Active language", selection: Binding(
                            get: { model.activeLanguageCode ?? model.installedLanguages[0] },
                            set: { model.activateLanguage($0) }
                        )) {
                            ForEach(model.installedLanguages, id: \.self) { code in
                                Text(languageName(code)).tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 280, alignment: .leading)
                        caption("Import another pack to add it here. Switching keeps each language's progress separate.")
                        Divider().overlay(Theme.line).padding(.vertical, 4)
                    }
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

    func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.inkFaint)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    func languageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    func pickPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Cockatoo language-pack JSON file"
        if panel.runModal() == .OK, let url = panel.url {
            model.importPack(from: url)
        }
    }

    func load() {
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

    func saveBlockedHosts() {
        let hosts = blockedHostsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        try? model.engine.store.setBlockedHosts(hosts)
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
            source text. What a swap guarantees depends on its fidelity tier:
            """)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Exact").bold()
                    Text("Grammatically stable — the authored replacement works unchanged in context.")
                }
                GridRow {
                    Text("Form-matched").bold()
                    Text("Word, article and number are right. Case agreement inside a source-language sentence is not attempted — the form you see is the pack's dictionary form.")
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
            Text("Vocabulary first; grammar later — that's the deal, stated plainly.")
                .italic()
        }
        .font(.callout)
    }
}
