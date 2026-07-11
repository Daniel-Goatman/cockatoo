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
            original English, always.

            **Words and genders come first; grammar comes later.** Swapped words show \
            their dictionary form with the correct article ("the house" becomes \
            "das Haus"), so every encounter teaches the word *and* its gender. Full \
            grammatical agreement inside English sentences isn't always possible — \
            Cockatoo marks every swap and never pretends otherwise. You can read \
            exactly what is and isn't guaranteed in Settings → How swapping works.
            """)
            .frame(maxWidth: 560, alignment: .leading)

            Button("Import a language pack…") { pickPack() }
                .buttonStyle(.borderedProminent)
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

// MARK: - Dashboard (real data only — P4)

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let o = model.overview {
                    HStack(spacing: 12) {
                        StatTile(title: "Due now", value: "\(o.dueNow)")
                        StatTile(title: "Unlocked tier", value: "\(o.unlockedTier)")
                        StatTile(title: "Words known", value: "\((o.countsByStage[.known] ?? 0) + (o.countsByStage[.mastered] ?? 0))")
                        StatTile(title: "In rotation", value: "\((o.countsByStage[.ambient] ?? 0) + (o.countsByStage[.ready] ?? 0))")
                    }
                    Text("Progress by stage").font(.headline)
                    ForEach(Stage.allCases, id: \.self) { stage in
                        let count = o.countsByStage[stage] ?? 0
                        HStack {
                            Text(stage.rawValue).frame(width: 90, alignment: .leading).font(.callout.monospaced())
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(stage >= .known ? Color.green.opacity(0.7) : Color.accentColor.opacity(0.5))
                                    .frame(width: max(2, geo.size.width * CGFloat(count) / CGFloat(max(1, o.totalItems))))
                            }
                            .frame(height: 14)
                            Text("\(count)").font(.callout.monospaced()).frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Overview")
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
        .onChange(of: model.overview?.countsByStage) { reload() }
        .navigationTitle("Library")
    }

    var columnHeader: some View {
        HStack(spacing: 12) {
            Text("English").frame(width: 170, alignment: .leading)
            Text("German").frame(width: 190, alignment: .leading)
            Text("Stage").frame(width: 84, alignment: .leading)
            Text("Strength").frame(width: 90, alignment: .leading)
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
            Text(row.source).frame(width: 170, alignment: .leading)
            Text(row.target).frame(width: 190, alignment: .leading)
            StageChip(stage: row.stage).frame(width: 84, alignment: .leading)
            StrengthDots(box: row.box).frame(width: 90, alignment: .leading)
            Text(row.due).foregroundStyle(.secondary).frame(minWidth: 90, alignment: .leading)
            Spacer()
        }
        .font(.callout)
        .opacity(row.stage == .locked ? 0.55 : 1)
    }

    func reload() {
        let formatter = RelativeDateTimeFormatter()
        guard let items = try? model.engine.store.items(language: "de"),
              let progress = try? model.engine.store.allProgress() else { return }
        unlockedTier = model.overview?.unlockedTier ?? 1

        let rows = items.map { item -> (Int, LibraryRow) in
            let p = progress[item.id]
            return (item.frequencyBand, LibraryRow(
                id: item.id,
                source: bareSource(item),
                target: (item.targetMeta?.gender).map { "\($0) \(item.target)" } ?? item.target,
                stage: p?.stage ?? .locked,
                box: p?.srsBox ?? 0,
                due: p?.dueAt.map { formatter.localizedString(for: $0, relativeTo: Date()) } ?? "—"
            ))
        }
        tiers = Dictionary(grouping: rows, by: \.0)
            .sorted { $0.key < $1.key }
            .map { TierGroup(id: $0.key, rows: $0.value.map(\.1).sorted { $0.source < $1.source }) }
    }

    /// Bare form for display: "book", not "the book" — the determiner
    /// variants exist for the matcher, not for reading lists.
    func bareSource(_ item: VocabItem) -> String {
        item.sourceForms.first { form in
            let lowered = form.form.lowercased()
            return !lowered.hasPrefix("the ") && !lowered.hasPrefix("a ") && !lowered.hasPrefix("an ")
        }?.form ?? item.sourceForms.first?.form ?? item.id
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
        Text(stage.rawValue)
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
