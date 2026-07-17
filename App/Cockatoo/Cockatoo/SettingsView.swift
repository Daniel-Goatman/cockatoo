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
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 21, weight: .semibold))
                    .padding(.bottom, 24)

                group("GENERAL") {
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
                        .labelsHidden()
                        .frame(maxWidth: 240, alignment: .leading)
                        caption("Each language keeps its own progress. Import a pack to add another.")
                    }
                    row {
                        Toggle(isOn: $launchAtLogin) {
                            Text("Launch Cockatoo at login").font(.system(size: 13))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Theme.goldDeep)
                        .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                    }
                    if let launchAtLoginError {
                        Text(launchAtLoginError).font(.caption).foregroundStyle(Theme.outcomeMissed)
                    } else {
                        caption("Recommended — keeps swaps and progress syncing to Safari.")
                    }
                    row {
                        Button("Import language pack…", action: pickPack)
                            .buttonStyle(.pill)
                    }
                }

                sectionDivider

                group("PRACTICE") {
                    HStack(spacing: 12) {
                        Text("New words per day")
                            .font(.system(size: 13))
                        Spacer(minLength: 12)
                        Stepper(value: $newPerDay, in: 1...20) {
                            Text("\(newPerDay)")
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .frame(width: 26, alignment: .trailing)
                        }
                        .onChange(of: newPerDay) {
                            try? model.engine.store.setSetting(SettingsKey.newPerDay, String(newPerDay))
                        }
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                    caption("How many new words each day introduces. Practice itself stays unlimited.")
                }

                sectionDivider

                group("PAGE SWAPS") {
                    Text("Blocked sites")
                        .font(.system(size: 13))
                    HStack(spacing: 10) {
                        TextField("", text: $blockedHostsText, prompt: Text("bank.com, mail.example.org"))
                            .themeField()
                            .onSubmit(saveBlockedHosts)
                        Button("Save", action: saveBlockedHosts)
                            .buttonStyle(.pill)
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                    caption("Cockatoo never swaps words on these domains.")

                    infoRow(
                        icon: "text.magnifyingglass",
                        title: "How swapping works",
                        subtitle: "Where swaps appear, the fidelity tiers, and how strength grows."
                    ) { model.swapGuidePresented = true }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
        .onAppear(perform: load)
        .navigationTitle("Settings")
    }

    // A flush section: mono header label + left-aligned content, no card.
    func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.monoLabel())
                .kerning(0.6)
                .foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var sectionDivider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .padding(.vertical, 22)
    }

    func row(@ViewBuilder content: () -> some View) -> some View {
        content().padding(.top, 4)
    }

    func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.inkFaint)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // A subtle tappable row that opens a deeper explanation elsewhere.
    func infoRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            InfoRowLabel(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
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

/// The disclosure row that opens the swap guide — hover lifts it off the
/// flush background without turning it back into a boxed card.
private struct InfoRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.gold)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(hovering ? Theme.surface : Theme.surface.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(hovering ? Theme.line2 : Theme.line)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

// MARK: - How swapping works (interactive overlay)

/// Fidelity-tier transparency requirement 3: the plain-language contract,
/// reworked as a graphical, scrollable modal instead of a wall of prose.
struct SwapGuideOverlay: View {
    let onClose: () -> Void

    /// A real swap drawn from the bundled pack, so the example matches what
    /// the user actually sees on pages.
    private var sample: (source: String, target: String, sentence: String) {
        guard let item = AppModel.bundledPacks()
            .sorted(by: { $0.pack.version > $1.pack.version })
            .first?.pack.items.first(where: { $0.fidelityTier == .exact && !$0.examples.isEmpty }) else {
            return ("house", "Haus", "Sie kaufen ein Haus am See.")
        }
        return (item.sourceLemma, item.target, item.examples[0].target)
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop; a click anywhere outside the panel closes it.
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            panel
                .frame(maxWidth: 540)
                .frame(maxHeight: 620)
                .padding(40)
        }
        .overlay(alignment: .topLeading) {
            // Invisible Escape target.
            Button(action: onClose) { Color.clear.frame(width: 0, height: 0) }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    exampleCard
                    densityBlock
                    neverBlock
                    tiersBlock
                    strengthBlock
                    Text("Vocabulary first; grammar later — that's the deal, stated plainly.")
                        .font(Theme.serif(14))
                        .italic()
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(22)
            }
        }
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.gold)
            Text("How swapping works")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 24, height: 24)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var intro: some View {
        Text("Cockatoo swaps a few words on the pages you read, so the vocabulary you meet in practice keeps resurfacing where you already spend time.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.inkMuted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // The swap, shown the way it appears in the wild: gold, underlined,
    // with the original one hover away.
    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "safari")
                Text("ON A PAGE")
            }
            .font(Theme.monoLabel(9))
            .kerning(0.55)
            .foregroundStyle(Theme.inkFaint)

            highlightedSentence(sample.sentence, target: sample.target)
                .font(Theme.serif(17))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(Theme.gold).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sample.target).font(Theme.serif(15, weight: .semibold))
                    Text("ORIGINAL · \(sample.source.uppercased())")
                        .font(Theme.monoLabel(8.5))
                        .kerning(0.4)
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line))
    }

    // "About one in forty" made literal: a small grid where a single dot is
    // gold.
    private var densityBlock: some View {
        section("HOW OFTEN", "Roughly one word in forty") {
            let columns = Array(repeating: GridItem(.fixed(9), spacing: 5), count: 20)
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(0..<40, id: \.self) { i in
                    Circle()
                        .fill(i == 17 ? Theme.gold : Theme.line2.opacity(0.6))
                        .frame(width: 9, height: 9)
                }
            }
            .frame(maxWidth: 260, alignment: .leading)
            Text("Enough to keep words alive on the page, rare enough to stay out of your way.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkFaint)
        }
    }

    private var neverBlock: some View {
        section("NEVER SWAPPED", "Some places stay untouched") {
            HStack(spacing: 8) {
                neverChip("square.and.pencil", "Forms")
                neverChip("chevron.left.forwardslash.chevron.right", "Code")
                neverChip("lock.shield", "Sensitive sites")
            }
        }
    }

    private func neverChip(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(label).font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Theme.surface, in: Capsule())
    }

    // The three fidelity tiers as coloured cards, each with a live underline
    // sample of what its guarantee looks like.
    private var tiersBlock: some View {
        section("FIDELITY", "What a swap guarantees") {
            VStack(spacing: 8) {
                tierCard(
                    color: Theme.live,
                    style: .solid,
                    name: "Exact",
                    detail: "Grammatically stable — the authored replacement works unchanged in context."
                )
                tierCard(
                    color: Theme.stageOnPages,
                    style: .solid,
                    name: "Form-matched",
                    detail: "Word, article and number are right. Case agreement inside a sentence isn't attempted — you see the pack's dictionary form."
                )
                tierCard(
                    color: Theme.stageUpcoming,
                    style: .dotted,
                    name: "Approximate",
                    detail: "Reserved for future word classes like verbs. Not used today; will carry a dotted underline."
                )
            }
        }
    }

    private enum UnderlineStyle { case solid, dotted }

    private func tierCard(color: Color, style: UnderlineStyle, name: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Text("Wort")
                    .font(Theme.serif(15, weight: .semibold))
                    .foregroundStyle(color)
                underline(color: color, style: style)
                    .frame(width: 34, height: 2)
            }
            .frame(width: 52)
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(color)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(color.opacity(0.28)))
    }

    @ViewBuilder
    private func underline(color: Color, style: UnderlineStyle) -> some View {
        switch style {
        case .solid:
            Capsule().fill(color)
        case .dotted:
            Line().stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 3]))
        }
    }

    // Strength lives in days, not reps — the three-day "known" rule as dots.
    private var strengthBlock: some View {
        section("STRENGTH", "Words ripen over days, not reps") {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 5) {
                        Circle().fill(Theme.gold).frame(width: 8, height: 8)
                        Text("Day \(i + 1)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    if i < 2 {
                        Rectangle().fill(Theme.line2).frame(width: 14, height: 1)
                    }
                }
            }
            Text("Strength climbs at most once per calendar day, and “known” takes correct answers on three different days — so a long session sharpens words without faking mastery.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkFaint)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section(_ label: String, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(Theme.monoLabel(9))
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkFaint)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlightedSentence(_ sentence: String, target: String) -> Text {
        guard let range = sentence.range(of: target, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(sentence)
        }
        let prefix = String(sentence[..<range.lowerBound])
        let match = String(sentence[range])
        let suffix = String(sentence[range.upperBound...])
        return Text(prefix)
            + Text(match).foregroundColor(Theme.gold).underline(true, color: Theme.goldDeep)
            + Text(suffix)
    }
}

/// A single horizontal rule, for the dotted fidelity underline.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
