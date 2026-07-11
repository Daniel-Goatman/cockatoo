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
                    .buttonStyle(.borderedProminent)
                Button("Import a custom pack…") { pickPack() }
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
            VStack(alignment: .leading, spacing: 20) {
                if let o = model.overview {
                    nextActionCard(o)
                    HStack(spacing: 12) {
                        StatTile(title: "Due now", value: "\(o.dueNow)")
                        StatTile(title: "Ready to practice", value: "\(o.readyCount)")
                        StatTile(title: "Words known", value: "\((o.countsByStage[.known] ?? 0) + (o.countsByStage[.mastered] ?? 0))")
                        StatTile(title: "In rotation", value: "\((o.countsByStage[.ambient] ?? 0) + (o.countsByStage[.ready] ?? 0))")
                    }
                    if let tier = o.tierProgress {
                        tierProgressCard(tier)
                    }
                    extensionStatusCard
                    Text("Progress by stage").font(.headline)
                    stageBars(o)
                }
            }
            .padding(24)
        }
        .navigationTitle("Overview")
    }

    // The dashboard's first job: say what to do next.
    @ViewBuilder
    func nextActionCard(_ o: LearnerEngine.Overview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if o.practiceAvailable {
                HStack(spacing: 12) {
                    Button("Practice now") { model.section = .practice }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Text(practiceSubtitle(o))
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("All caught up", systemImage: "checkmark.circle")
                    .font(.headline)
                if let nextDue = o.nextDueAt {
                    Text("Next review \(RelativeDateTimeFormatter().localizedString(for: nextDue, relativeTo: Date())).")
                        .foregroundStyle(.secondary)
                }
            }
            if !o.almostReady.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Almost ready — keep reading in Safari")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(o.almostReady, id: \.itemId) { need in
                        Text("**\(need.target)** — \(ExposureHint.text(for: need))")
                            .font(.callout)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    func practiceSubtitle(_ o: LearnerEngine.Overview) -> String {
        var parts: [String] = []
        if o.dueNow > 0 { parts.append("\(o.dueNow) due") }
        if o.readyCount > 0 { parts.append("\(o.readyCount) ready") }
        if o.introAvailable > 0 { parts.append("\(o.introAvailable) new word\(o.introAvailable == 1 ? "" : "s")") }
        if o.tierCheckReady { parts.append("tier check") }
        return parts.joined(separator: " · ")
    }

    func tierProgressCard(_ tier: LearnerEngine.TierProgress) -> some View {
        let checkReady = model.overview?.tierCheckReady == true
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tier \(tier.nextTier)").font(.headline)
                if checkReady {
                    Label("check ready", systemImage: "flag.checkered")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.13), in: Capsule())
                        .foregroundStyle(.purple)
                }
                Spacer()
                Text("\(tier.knownInCurrentTier) of \(tier.neededInCurrentTier) known")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(tier.knownInCurrentTier, tier.neededInCurrentTier)), total: Double(tier.neededInCurrentTier))
            if checkReady {
                Text("Your next practice session ends with a \(EngineConfig.default.tierCheckQuestionCount)-question tier check — pass it to unlock tier \(tier.nextTier).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Unlocks through a short tier check once \(tier.neededInCurrentTier) of the \(tier.currentTierTotal) tier-\(tier.currentTier) words are known (and tier \(tier.currentTier) has had a week to settle).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // Honest connectivity, two signals: IPC contact this launch (is the
    // pipe up?) and the last ingested exposure event ever (is data moving?).
    var extensionStatusCard: some View {
        let formatter = RelativeDateTimeFormatter()
        return HStack(spacing: 8) {
            if let contact = model.lastExtensionContact {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safari extension connected — last synced \(formatter.localizedString(for: contact, relativeTo: Date())).")
                    if let event = model.overview?.lastEventAt {
                        Text("Last reading activity \(formatter.localizedString(for: event, relativeTo: Date())). Sightings credit up to 3 per word per day, hovers 2 — spacing beats cramming.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // Pipeline order with the parked (locked) words last and muted — the
    // dashboard shows motion, not a wall of unavailable items.
    func stageBars(_ o: LearnerEngine.Overview) -> some View {
        let order: [Stage] = [.ambient, .ready, .learning, .known, .mastered, .locked]
        return ForEach(order, id: \.self) { stage in
            let count = o.countsByStage[stage] ?? 0
            HStack {
                Text(stage.displayName).frame(width: 110, alignment: .leading).font(.callout)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(stageBarColor(stage))
                        .frame(width: max(2, geo.size.width * CGFloat(count) / CGFloat(max(1, o.totalItems))))
                }
                .frame(height: 14)
                Text("\(count)").font(.callout.monospaced()).frame(width: 40, alignment: .trailing)
            }
            .opacity(stage == .locked ? 0.5 : 1)
        }
    }

    func stageBarColor(_ stage: Stage) -> Color {
        switch stage {
        case .locked: return Color.secondary.opacity(0.3)
        case .known, .mastered: return Color.green.opacity(0.7)
        default: return Color.accentColor.opacity(0.5)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(minWidth: 120, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
        List {
            columnHeader
            ForEach(tiers) { tier in
                Section {
                    ForEach(tier.rows, content: row)
                } header: {
                    tierHeader(tier)
                }
            }
        }
        .listStyle(.inset)
        .onAppear(perform: reload)
        // dbGeneration, not countsByStage: seen/engaged counts change
        // without any stage changing, and they must update live too.
        .onChange(of: model.dbGeneration) { reload() }
        .navigationTitle("Library")
    }

    var columnHeader: some View {
        HStack(spacing: 12) {
            Text("English").frame(width: 160, alignment: .leading)
            Text("German").frame(width: 180, alignment: .leading)
            Text("Stage").frame(width: 92, alignment: .leading)
            Text("Progress").frame(width: 130, alignment: .leading)
            Text("Next review").frame(minWidth: 90, alignment: .leading)
            Spacer()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    func tierHeader(_ tier: TierGroup) -> some View {
        HStack(spacing: 8) {
            Text("Tier \(tier.id)").font(.headline)
            if tier.id <= unlockedTier {
                Text("unlocked")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            } else {
                Label("locked", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(tier.knownCount) of \(tier.rows.count) known")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    func row(_ row: LibraryRow) -> some View {
        HStack(spacing: 12) {
            Text(row.source).frame(width: 160, alignment: .leading)
            Text(row.target).frame(width: 180, alignment: .leading)
            StageChip(stage: row.stage).frame(width: 92, alignment: .leading)
            progressCell(row).frame(width: 130, alignment: .leading)
            Text(row.due).foregroundStyle(.secondary).frame(minWidth: 90, alignment: .leading)
            Spacer()
        }
        .font(.callout)
        .opacity(row.stage == .locked ? 0.55 : 1)
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
                        .foregroundStyle(.blue)
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
                .foregroundStyle(.teal)
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

/// Human names for the engine's stage machine — the rawValues are engine
/// jargon and never shown to users.
extension Stage {
    var displayName: String {
        switch self {
        case .locked: return "upcoming"
        case .ambient: return "on pages"
        case .ready: return "ready"
        case .learning: return "practicing"
        case .known: return "known"
        case .mastered: return "mastered"
        }
    }
}

struct StageChip: View {
    let stage: Stage

    var color: Color {
        switch stage {
        case .locked: return .gray
        case .ambient: return .blue
        case .ready: return .teal
        case .learning: return .orange
        case .known: return .green
        case .mastered: return .green
        }
    }

    var body: some View {
        Text(stage.displayName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

/// SRS box 0–6 as filled dots — "Strength" without the jargon.
struct StrengthDots: View {
    let box: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(i < box ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("strength \(box) of 6")
    }
}
