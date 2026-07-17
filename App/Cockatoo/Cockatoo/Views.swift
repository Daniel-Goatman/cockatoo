import SwiftUI
import LearnerCore

// MARK: - Dashboard (real data only — P4; leads with the next action)

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Overview")
                    .font(.system(size: 21, weight: .semibold))
                    .padding(.bottom, 22)
                if let o = model.overview {
                    // Flush on the background — no card chrome. Next action
                    // leads; the milestone ring is the one ambient signal.
                    hero(o)
                    // The progress ramp doubles as the divider between "what
                    // to do now" and "where you stand".
                    stageSeparator(o)
                        .padding(.vertical, 26)
                    summaries(o)
                    // Only surface the extension when it needs the user — a
                    // healthy connection lives quietly in the sidebar footer.
                    if model.lastExtensionContact == nil {
                        extensionSetup
                            .padding(.top, 30)
                    }
                }
            }
            // The prototype's calm reading column, centered.
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
        .navigationTitle("Overview")
    }

    // The hub's first job: say what to do next — with the milestone ring as
    // the one piece of ambient progress, not a wall of stat cards.
    @ViewBuilder
    func hero(_ o: LearnerEngine.Overview) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                if o.practiceAvailable {
                    HStack(spacing: 12) {
                        Button("Practice now") { model.section = .practice }
                            .buttonStyle(.pillProminent)
                        Text(practiceSubtitle(o))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    Text("Practice as much as you like — extra reps sharpen words without rushing them; strength only climbs across days.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.inkFaint)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("All caught up", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.live)
                    if let nextDue = o.nextDueAt {
                        Text("Next review \(RelativeDateTimeFormatter().localizedString(for: nextDue, relativeTo: Date())). Reading a page still reinforces what you know.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.inkMuted)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
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
    }

    func practiceSubtitle(_ o: LearnerEngine.Overview) -> String {
        var parts: [String] = []
        if o.dueNow > 0 { parts.append("\(o.dueNow) due") }
        let newAvailable = min(o.newRemainingToday, o.introAvailable)
        if newAvailable > 0 { parts.append("\(newAvailable) new word\(newAvailable == 1 ? "" : "s") today") }
        if parts.isEmpty { parts.append("reinforcement reps") }
        return parts.joined(separator: " · ")
    }

    // The two navigational summaries: colourful numbers, centered, split by a
    // hairline. Each is a subtle door into its section — no card, just a
    // hover lift and an arrow that arrives on approach.
    func summaries(_ o: LearnerEngine.Overview) -> some View {
        let known = (o.countsByStage[.known] ?? 0) + (o.countsByStage[.mastered] ?? 0)
        return HStack(spacing: 0) {
            summaryColumn(
                icon: "rectangle.stack",
                value: o.dueNow,
                valueColor: o.dueNow > 0 ? Theme.gold : Theme.inkMuted,
                title: "due to review",
                caption: "new today \(o.newToday)/\(o.newPerDay)"
            ) { model.section = .practice }

            Rectangle()
                .fill(Theme.line)
                .frame(width: 1, height: 62)

            summaryColumn(
                icon: "books.vertical",
                value: o.libraryCount,
                valueColor: Theme.stageOnPages,
                title: "words in your library",
                caption: "\(known) known · \(o.totalItems) in pack"
            ) { model.section = .library }
        }
        .frame(maxWidth: .infinity)
    }

    func summaryColumn(
        icon: String,
        value: Int,
        valueColor: Color,
        title: String,
        caption: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SummaryColumnLabel(icon: icon, value: value, valueColor: valueColor, title: title, caption: caption)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // When the extension hasn't reported in, teach the fix instead of hiding
    // an error in a status line — three concrete steps, coloured to invite.
    var extensionSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "safari")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.gold)
                Text("Turn on reading reinforcement")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            Text("The Safari extension swaps a few words on the pages you read, so the words you meet in practice keep resurfacing in the wild. It hasn't connected yet:")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 9) {
                setupStep(1, "Open Safari, then Settings → Extensions.")
                setupStep(2, "Enable Cockatoo (allow it on the sites you read).")
                setupStep(3, "Browse any page — sightings show up in your library.")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gold.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.gold.opacity(0.28)))
    }

    func setupStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.onGold)
                .frame(width: 18, height: 18)
                .background(Theme.gold, in: Circle())
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // The user-facing stages as ONE stacked ramp bar (cold→gold), framed by
    // hairlines so it reads as the section divider.
    func stageSeparator(_ o: LearnerEngine.Overview) -> some View {
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
            .frame(height: 10)
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
        .padding(.vertical, 18)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }
}

/// One Overview summary: big colour-tinted number, centered, with an arrow
/// that fades in on hover. A door into its section without a boxy tile.
private struct SummaryColumnLabel: View {
    let icon: String
    let value: Int
    let valueColor: Color
    let title: String
    let caption: String
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            // Default: the icon alone, centered over the card. On hover the
            // "view →" affordance is inserted (not just un-hidden), so the row
            // re-centers — sliding the icon left as the label fades in — instead
            // of the icon sitting permanently left of a reserved gap.
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                if hovering {
                    Text("view")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            Text("\(value)")
                .font(.system(size: 40, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkMuted)
            Text(caption)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 3)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(hovering ? Theme.surface.opacity(0.5) : .clear)
                .padding(.horizontal, 6)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
    }
}

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bands: [BandGroup] = []
    @State private var highlightedItemID: String?

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
        ScrollViewReader { proxy in
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
            .onAppear {
                reload()
            }
            .task(id: model.libraryRevealRequest?.token) {
                guard let request = model.libraryRevealRequest else { return }
                // A newly-created LazyVStack needs a turn to publish its row
                // scroll targets after reload/section navigation.
                await Task.yield()
                highlightedItemID = request.itemID
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                    proxy.scrollTo(request.itemID, anchor: .center)
                }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled,
                      model.libraryRevealRequest?.token == request.token else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) {
                    highlightedItemID = nil
                }
                model.consumeLibraryReveal(request.token)
            }
        }
        // dbGeneration, not countsByStage: seen/engaged counts change
        // without any stage changing, and they must update live too.
        .onChange(of: model.dbGeneration) { reload() }
        .navigationTitle("Library")
    }

    // Column widths sized so the last column survives the base window with
    // the sidebar expanded — never clip the time-sensitive column.
    static let colSource: CGFloat = 108
    static let colTarget: CGFloat = 138
    static let colStage: CGFloat = 96
    static let colProgress: CGFloat = 112

    var columnHeader: some View {
        HStack(spacing: 12) {
            Text("SOURCE").frame(width: Self.colSource, alignment: .leading)
            Text(model.targetLanguageName.uppercased()).frame(width: Self.colTarget, alignment: .leading)
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
        LibraryRowView(row: row, highlighted: row.id == highlightedItemID) { progressCell(row) }
            .id(row.id)
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
        guard let language = try? model.engine.store.setting(SettingsKey.activeLanguage) else { return }
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
    let highlighted: Bool
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
            .frame(width: LibraryView.colSource, alignment: .leading)
            Text(row.target)
                .font(Theme.serif(14.5, weight: .medium))
                .lineLimit(1)
                .frame(width: LibraryView.colTarget, alignment: .leading)
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
        .background(
            highlighted ? Theme.gold.opacity(0.22) : (hovering ? Theme.surface : .clear),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Theme.gold.opacity(highlighted ? 0.9 : 0), lineWidth: 1)
        }
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
