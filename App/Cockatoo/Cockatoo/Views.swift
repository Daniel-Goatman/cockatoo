import SwiftUI
import LearnerCore
import UniformTypeIdentifiers

// MARK: - Onboarding (fidelity-tier transparency requirement 1)

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Cockatoo").font(.largeTitle.bold())
            Text("""
            Cockatoo teaches you German while you read the web. A few words on each \
            page are quietly swapped into German — hover any marked word to see the \
            original English, always. Hovering also tells Cockatoo you're curious, \
            which brings a word into practice sooner.

            **Words and genders come first; grammar comes later.** Swapped words show \
            their dictionary form with the correct article ("the house" becomes \
            "das Haus"), so every encounter teaches the word *and* its gender. Full \
            grammatical agreement inside English sentences isn't always possible — \
            Cockatoo marks every swap and never pretends otherwise. You can read \
            exactly what is and isn't guaranteed in Settings → How swapping works.
            """)
            .frame(maxWidth: 560, alignment: .leading)

            HStack(spacing: 10) {
                Button("Start learning German") { model.importBundledPack() }
                    .buttonStyle(.pillProminent)
                Button("Import a custom pack…") { pickPack() }
                    .buttonStyle(.pill)
            }
            Text("The built-in pack has over 200 frequency-ordered words and phrases. You can practice your first words right away — no browsing required.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: 560, alignment: .leading)

            if let error = model.lastError {
                Text(error).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func pickPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Cockatoo language pack (e.g. de-2026.07.json)"
        if panel.runModal() == .OK, let url = panel.url {
            model.importPack(from: url)
        }
    }
}

// MARK: - Dashboard (real data only — P4; leads with the next action)

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Overview")
                    .font(.system(size: 21, weight: .semibold))
                    .padding(.bottom, 4)
                if let o = model.overview {
                    heroCard(o)
                    stageStripCard(o)
                    HStack(spacing: 12) {
                        practiceTile(o)
                        libraryTile(o)
                    }
                    extensionStatusCard
                }
            }
            // The prototype's calm reading column, centered.
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .navigationTitle("Overview")
    }

    // The hub's first job: say what to do next — with the tier ring as the
    // one piece of ambient progress, not a wall of stat cards.
    @ViewBuilder
    func heroCard(_ o: LearnerEngine.Overview) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                if o.practiceAvailable {
                    HStack(spacing: 12) {
                        Button("Practice now") { model.section = .practice }
                            .buttonStyle(.pillProminent)
                        Text(practiceSubtitle(o))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkMuted)
                    }
                } else {
                    Label("All caught up", systemImage: "checkmark.circle")
                        .font(.headline)
                    if let nextDue = o.nextDueAt {
                        Text("Next review \(RelativeDateTimeFormatter().localizedString(for: nextDue, relativeTo: Date())).")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                if !o.almostReady.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ALMOST READY — KEEP READING IN SAFARI")
                            .font(Theme.monoLabel())
                            .foregroundStyle(Theme.inkFaint)
                            .padding(.top, 6)
                            .padding(.bottom, 3)
                        ForEach(o.almostReady, id: \.itemId) { need in
                            (Text(need.target).font(Theme.serif(13.5, weight: .semibold))
                                + Text(" — \(ExposureHint.text(for: need))"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let tier = o.tierProgress {
                VStack(spacing: 8) {
                    Text("TIER \(tier.nextTier)")
                        .font(Theme.monoLabel())
                        .kerning(0.6)
                        .foregroundStyle(Theme.inkFaint)
                    TierRing(known: tier.knownInCurrentTier, needed: tier.neededInCurrentTier, diameter: 104)
                    if o.tierCheckReady {
                        Text("check ready")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.gold.opacity(0.16), in: Capsule())
                            .foregroundStyle(Theme.goldDeep)
                    } else {
                        Text("opens with a short check")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                .help("Unlocks through a short tier check once \(tier.neededInCurrentTier) of the \(tier.currentTierTotal) tier-\(tier.currentTier) words are known (and tier \(tier.currentTier) has had a week to settle).")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(padding: 20)
    }

    func practiceSubtitle(_ o: LearnerEngine.Overview) -> String {
        var parts: [String] = []
        if o.dueNow > 0 { parts.append("\(o.dueNow) due") }
        if o.readyCount > 0 { parts.append("\(o.readyCount) ready") }
        if o.introAvailable > 0 { parts.append("\(o.introAvailable) new word\(o.introAvailable == 1 ? "" : "s")") }
        if o.tierCheckReady { parts.append("tier check") }
        return parts.joined(separator: " · ")
    }

    // Navigational tiles: one number each, and a door to the section.
    func practiceTile(_ o: LearnerEngine.Overview) -> some View {
        Button { model.section = .practice } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.bottom, 8)
                Text("\(o.dueNow + o.readyCount)")
                    .font(.system(size: 27, weight: .bold))
                    .monospacedDigit()
                Text("to practice")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                Text("\(o.dueNow) due · \(o.introAvailable) new")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 5)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.tile)
    }

    func libraryTile(_ o: LearnerEngine.Overview) -> some View {
        let known = (o.countsByStage[.known] ?? 0) + (o.countsByStage[.mastered] ?? 0)
        let onPages = (o.countsByStage[.ambient] ?? 0) + (o.countsByStage[.ready] ?? 0)
        return Button { model.section = .library } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.bottom, 8)
                Text("\(o.totalItems)")
                    .font(.system(size: 27, weight: .bold))
                    .monospacedDigit()
                Text("words in your pack")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                Text("\(known) known · \(onPages) on pages")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 5)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.tile)
    }

    // Honest connectivity, two signals: IPC contact this launch (is the
    // pipe up?) and the last ingested exposure event ever (is data moving?).
    var extensionStatusCard: some View {
        let formatter = RelativeDateTimeFormatter()
        return HStack(spacing: 8) {
            if let contact = model.lastExtensionContact {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.live)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safari extension connected — last synced \(formatter.localizedString(for: contact, relativeTo: Date())).")
                    if let event = model.overview?.lastEventAt {
                        Text("Last reading activity \(formatter.localizedString(for: event, relativeTo: Date())). Sightings credit up to 3 per word per day, hovers 2 — spacing beats cramming.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.outcomeAlmost)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The Safari extension hasn't connected since Cockatoo launched. Enable it in Safari → Settings → Extensions, then browse any page.")
                    if let event = model.overview?.lastEventAt {
                        Text("Last reading activity \(formatter.localizedString(for: event, relativeTo: Date())).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(padding: 12)
    }

    // The four user-facing stages as ONE stacked ramp bar (cold→gold),
    // upcoming last and muted — motion, not a wall of rows.
    func stageStripCard(_ o: LearnerEngine.Overview) -> some View {
        func count(_ stages: Stage...) -> Int {
            stages.reduce(0) { $0 + (o.countsByStage[$1] ?? 0) }
        }
        let groups: [(label: String, count: Int, color: Color, muted: Bool)] = [
            ("on pages", count(.ambient, .ready), Theme.stageOnPages, false),
            ("practicing", count(.learning), Theme.stagePracticing, false),
            ("known", count(.known, .mastered), Theme.stageKnown, false),
            ("upcoming", count(.locked), Theme.stageUpcoming, true),
        ]
        let total = CGFloat(max(1, o.totalItems))
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("PROGRESS BY STAGE")
                    .font(Theme.monoLabel())
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
                Text("\(o.totalItems) words")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(groups.filter { $0.count > 0 }, id: \.label) { group in
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(group.color.opacity(group.muted ? 0.4 : 1))
                            .frame(width: max(4, (geo.size.width - 6) * CGFloat(group.count) / total))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)
            HStack(spacing: 16) {
                ForEach(groups, id: \.label) { group in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(group.color.opacity(group.muted ? 0.4 : 1))
                            .frame(width: 7, height: 7)
                        Text("\(group.label) \(group.count)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.inkMuted)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }
}

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var tiers: [TierGroup] = []
    @State private var unlockedTier = 1

    struct TierGroup: Identifiable {
        let id: Int
        let rows: [LibraryRow]
        var knownCount: Int { rows.filter { $0.stage >= .known }.count }
    }

    struct LibraryRow: Identifiable {
        let id: String
        let source: String
        let target: String
        let stage: Stage
        let box: Int
        let due: String
        let seenCount: Int
        let engagedCount: Int
        /// Today's sighting credit is exhausted — show it, don't imply
        /// more looking would help today.
        let seenCappedToday: Bool
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(tiers) { tier in
                        tierHeader(tier)
                        ForEach(tier.rows, content: row)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Library")
                            .font(.system(size: 21, weight: .semibold))
                        columnHeader
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bg)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear(perform: reload)
        // dbGeneration, not countsByStage: seen/engaged counts change
        // without any stage changing, and they must update live too.
        .onChange(of: model.dbGeneration) { reload() }
        .navigationTitle("Library")
    }

    // Column widths sized so the last column survives the base window with
    // the sidebar expanded — never clip the time-sensitive column.
    static let colEnglish: CGFloat = 108
    static let colGerman: CGFloat = 138
    static let colStage: CGFloat = 96
    static let colProgress: CGFloat = 112

    var columnHeader: some View {
        HStack(spacing: 12) {
            Text("ENGLISH").frame(width: Self.colEnglish, alignment: .leading)
            Text("GERMAN").frame(width: Self.colGerman, alignment: .leading)
            Text("STAGE").frame(width: Self.colStage, alignment: .leading)
            Text("PROGRESS").frame(width: Self.colProgress, alignment: .leading)
            Text("NEXT REVIEW").frame(minWidth: 70, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(Theme.monoLabel())
        .kerning(0.5)
        .foregroundStyle(Theme.inkFaint)
        .lineLimit(1)
        .padding(.horizontal, 10)
    }

    func tierHeader(_ tier: TierGroup) -> some View {
        HStack(spacing: 9) {
            Text("Tier \(tier.id)").font(.system(size: 13.5, weight: .semibold))
            if tier.id <= unlockedTier {
                Text("unlocked")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.live.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.live)
            } else {
                Label("locked", systemImage: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.surface, in: Capsule())
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            Text("\(tier.knownCount) of \(tier.rows.count) known")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, 10)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    func row(_ row: LibraryRow) -> some View {
        LibraryRowView(row: row) { progressCell(row) }
    }

    /// Ambient rows show exposure progress (the invisible waiting period,
    /// made visible); scheduled rows show SRS strength.
    @ViewBuilder
    func progressCell(_ row: LibraryRow) -> some View {
        switch row.stage {
        case .locked:
            Text("—").foregroundStyle(.tertiary)
        case .ambient:
            HStack(spacing: 5) {
                Text("\(row.seenCount)/6 seen").font(.caption.monospacedDigit())
                if row.engagedCount > 0 {
                    Image(systemName: "cursorarrow.rays")
                        .font(.caption2)
                        .foregroundStyle(Theme.stageOnPages)
                }
                if row.seenCappedToday {
                    Text("· done today")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
            .help("Sightings credit up to 3 per word per day (hovers 2) — spaced encounters beat cramming. A hover halves the sightings needed. \"Done today\" means today's credit is banked; counts resume tomorrow.")
        case .ready:
            Text("practice now")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.goldDeep)
        case .learning, .known, .mastered:
            StrengthDots(box: row.box)
        }
    }

    func reload() {
        let formatter = RelativeDateTimeFormatter()
        let language = (try? model.engine.store.setting(SettingsKey.activeLanguage) ?? "de") ?? "de"
        guard let items = try? model.engine.store.items(language: language),
              let progress = try? model.engine.store.allProgress() else { return }
        let countsToday = (try? model.engine.store.exposureCountsToday(now: Date())) ?? [:]
        let seenCap = EngineConfig.default.seenCreditDailyCap
        unlockedTier = model.overview?.unlockedTier ?? 1

        let rows = items.map { item -> (Int, LibraryRow) in
            let p = progress[item.id]
            return (item.frequencyBand, LibraryRow(
                id: item.id,
                source: item.bareSourceForm ?? item.id,
                target: item.displayTarget,
                stage: p?.stage ?? .locked,
                box: p?.srsBox ?? 0,
                due: p?.dueAt.map { formatter.localizedString(for: $0, relativeTo: Date()) } ?? "—",
                seenCount: p?.seenCount ?? 0,
                engagedCount: p?.engagedCount ?? 0,
                seenCappedToday: (countsToday[item.id]?.seen ?? 0) >= seenCap
            ))
        }
        tiers = Dictionary(grouping: rows, by: \.0)
            .sorted { $0.key < $1.key }
            .map { TierGroup(id: $0.key, rows: $0.value.map(\.1).sorted { $0.source < $1.source }) }
    }
}

/// One library row: fixed columns matching the header, hover highlight.
struct LibraryRowView<Progress: View>: View {
    let row: LibraryView.LibraryRow
    @ViewBuilder let progress: () -> Progress
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text(row.source)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
                .frame(width: LibraryView.colEnglish, alignment: .leading)
            Text(row.target)
                .font(Theme.serif(14.5, weight: .medium))
                .lineLimit(1)
                .frame(width: LibraryView.colGerman, alignment: .leading)
            StageChip(stage: row.stage).frame(width: LibraryView.colStage, alignment: .leading)
            progress().frame(width: LibraryView.colProgress, alignment: .leading)
            Text(row.due)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
                .frame(minWidth: 70, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovering ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 7))
        .opacity(row.stage == .locked ? 0.55 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The user-facing model is FOUR stages: upcoming → on pages → practicing
/// → known. The engine's six states stay load-bearing underneath (P2), but
/// "ready" is only a session-priority hint (any on-pages word can be
/// introduced in practice anyway) and "mastered" is a badge on known — not
/// mental-model stages of their own.
extension Stage {
    var displayName: String {
        switch self {
        case .locked: return "upcoming"
        case .ambient, .ready: return "on pages"
        case .learning: return "practicing"
        case .known, .mastered: return "known"
        }
    }
}

struct StageChip: View {
    let stage: Stage

    var color: Color { Theme.stageColor(stage) }

    var body: some View {
        HStack(spacing: 4) {
            Text(stage.displayName)
            if stage == .mastered {
                Image(systemName: "star.fill").font(.system(size: 7))
            }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .padding(.horizontal, 9).padding(.vertical, 3.5)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
        .help(stage == .mastered ? "Mastered — retired from pages, kept fresh with rare reviews" : "")
    }
}

/// SRS box 0–6 as filled dots — "Strength" without the jargon.
struct StrengthDots: View {
    let box: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(i < box ? Theme.gold : Theme.line2.opacity(0.6))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("strength \(box) of 6")
    }
}
