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
            Cockatoo teaches you German while you read the web. New words arrive in \
            short practice sessions — a few per day, marked as new — and then start \
            appearing swapped into German on pages you read. Hover any marked word \
            to see the original English, always.

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

    // The hub's first job: say what to do next — with the milestone ring as
    // the one piece of ambient progress, not a wall of stat cards.
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
                    Text("Practice as much as you like — extra reps sharpen words without rushing them; strength only climbs across days.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                } else {
                    Label("All caught up", systemImage: "checkmark.circle")
                        .font(.headline)
                    if let nextDue = o.nextDueAt {
                        Text("Next review \(RelativeDateTimeFormatter().localizedString(for: nextDue, relativeTo: Date())).")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            Spacer(minLength: 0)
            if let m = o.nextMilestone {
                VStack(spacing: 8) {
                    Text("BAND \(m.band)")
                        .font(Theme.monoLabel())
                        .kerning(0.6)
                        .foregroundStyle(Theme.inkFaint)
                    ProgressRing(known: m.known, needed: m.needed, diameter: 104)
                    Text("milestone")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkFaint)
                }
                .help("Band \(m.band) completes when \(m.needed) of its \(m.total) words are known — a milestone, not a gate; new words keep flowing regardless.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(padding: 20)
    }

    func practiceSubtitle(_ o: LearnerEngine.Overview) -> String {
        var parts: [String] = []
        if o.dueNow > 0 { parts.append("\(o.dueNow) due") }
        let newAvailable = min(o.newRemainingToday, o.introAvailable)
        if newAvailable > 0 { parts.append("\(newAvailable) new word\(newAvailable == 1 ? "" : "s") today") }
        if parts.isEmpty { parts.append("reinforcement reps") }
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
                Text("\(o.dueNow)")
                    .font(.system(size: 27, weight: .bold))
                    .monospacedDigit()
                Text("due to review")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                Text("new today \(o.newToday)/\(o.newPerDay)")
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
                Text("\(o.libraryCount)")
                    .font(.system(size: 27, weight: .bold))
                    .monospacedDigit()
                Text("words in your library")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                Text("\(known) known · \(o.totalItems) in pack")
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
                        Text("Last reading activity \(formatter.localizedString(for: event, relativeTo: Date())). Pages reinforce the words you're learning — sightings show up in your library.")
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

    // The user-facing stages as ONE stacked ramp bar (cold→gold),
    // upcoming last and muted — motion, not a wall of rows.
    func stageStripCard(_ o: LearnerEngine.Overview) -> some View {
        func count(_ stages: Stage...) -> Int {
            stages.reduce(0) { $0 + (o.countsByStage[$1] ?? 0) }
        }
        let groups: [(label: String, count: Int, color: Color, muted: Bool)] = [
            ("practicing", count(.learning), Theme.stagePracticing, false),
            ("known", count(.known, .mastered), Theme.stageKnown, false),
            ("upcoming", max(0, o.totalItems - o.libraryCount), Theme.stageUpcoming, true),
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
    @State private var bands: [BandGroup] = []

    struct BandGroup: Identifiable {
        let id: Int
        let rows: [LibraryRow]
        var knownCount: Int { rows.filter { ($0.stage ?? .learning) >= .known && $0.stage != nil }.count }
        var inLibraryCount: Int { rows.filter { $0.stage != nil }.count }
        /// Milestone reached (non-gating celebration threshold).
        var complete: Bool {
            !rows.isEmpty && Double(knownCount) / Double(rows.count) >= EngineConfig.default.milestoneFraction
        }
    }

    struct LibraryRow: Identifiable {
        let id: String
        let source: String
        let target: String
        /// nil = not introduced yet (upcoming).
        let stage: Stage?
        let box: Int
        let due: String
        /// Page sightings since introduction — display-only.
        let seenCount: Int
        /// Introduced today — the "new" highlight.
        let isNew: Bool
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(bands) { band in
                        bandHeader(band)
                        ForEach(band.rows, content: row)
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

    func bandHeader(_ band: BandGroup) -> some View {
        HStack(spacing: 9) {
            Text("Band \(band.id)").font(.system(size: 13.5, weight: .semibold))
            if band.complete {
                Label("milestone", systemImage: "star.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.gold.opacity(0.16), in: Capsule())
                    .foregroundStyle(Theme.goldDeep)
            } else if band.inLibraryCount > 0 {
                Text("\(band.inLibraryCount) in library")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.live.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.live)
            }
            Spacer()
            Text("\(band.knownCount) of \(band.rows.count) known")
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

    /// Library rows show SRS strength plus wild sightings; upcoming rows
    /// wait for the intake drip.
    @ViewBuilder
    func progressCell(_ row: LibraryRow) -> some View {
        if row.stage == nil {
            Text("—").foregroundStyle(.tertiary)
                .help("Not in your library yet — new words arrive in practice sessions, a few per day.")
        } else {
            HStack(spacing: 6) {
                StrengthDots(box: row.box)
                if row.seenCount > 0 {
                    Image(systemName: "eye")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Theme.inkFaint)
                    Text("\(row.seenCount)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .help(row.seenCount > 0 ? "Seen \(row.seenCount)× in the wild on pages you've read." : "")
        }
    }

    func reload() {
        let formatter = RelativeDateTimeFormatter()
        let language = (try? model.engine.store.setting(SettingsKey.activeLanguage) ?? "de") ?? "de"
        guard let items = try? model.engine.store.items(language: language),
              let progress = try? model.engine.store.allProgress() else { return }
        let dayStart = Calendar(identifier: .gregorian).startOfDay(for: Date())

        let rows = items.map { item -> (Int, LibraryRow) in
            let p = progress[item.id]
            return (item.frequencyBand, LibraryRow(
                id: item.id,
                source: item.bareSourceForm ?? item.id,
                target: item.displayTarget,
                stage: p?.stage,
                box: p?.srsBox ?? 0,
                due: p?.dueAt.map { formatter.localizedString(for: $0, relativeTo: Date()) } ?? "—",
                seenCount: p?.seenCount ?? 0,
                isNew: (p?.activatedAt).map { $0 >= dayStart } ?? false
            ))
        }
        bands = Dictionary(grouping: rows, by: \.0)
            .sorted { $0.key < $1.key }
            .map { BandGroup(id: $0.key, rows: $0.value.map(\.1).sorted { $0.source < $1.source }) }
    }
}

/// One library row: fixed columns matching the header, hover highlight.
struct LibraryRowView<Progress: View>: View {
    let row: LibraryView.LibraryRow
    @ViewBuilder let progress: () -> Progress
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(row.source)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
                if row.isNew {
                    Text("new")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Theme.outcomeIntroduced.opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.outcomeIntroduced)
                }
            }
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
        .opacity(row.stage == nil ? 0.55 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The user-facing model: upcoming (not in the library yet) → practicing →
/// known. "Mastered" is a badge on known, not a mental-model stage of its
/// own; library membership itself is the first visible step.
extension Optional where Wrapped == Stage {
    var displayName: String {
        switch self {
        case nil: return "upcoming"
        case .learning: return "practicing"
        case .known, .mastered: return "known"
        }
    }
}

struct StageChip: View {
    let stage: Stage?

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
