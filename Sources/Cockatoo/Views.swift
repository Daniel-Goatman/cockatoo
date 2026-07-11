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
    @State private var rows: [LibraryRow] = []

    struct LibraryRow: Identifiable {
        let id: String
        let source: String
        let target: String
        let band: Int
        let stage: String
        let box: Int
        let due: String
    }

    var body: some View {
        Table(rows) {
            TableColumn("English") { Text($0.source) }
            TableColumn("German") { Text($0.target) }
            TableColumn("Band") { Text("\($0.band)") }.width(50)
            TableColumn("Stage") { Text($0.stage) }.width(80)
            TableColumn("Box") { Text("\($0.box)") }.width(40)
            TableColumn("Next review") { Text($0.due) }
        }
        .onAppear(perform: reload)
        .onChange(of: model.overview?.countsByStage) { reload() }
        .navigationTitle("Library")
    }

    func reload() {
        let formatter = RelativeDateTimeFormatter()
        guard let items = try? model.engine.store.items(language: "de"),
              let progress = try? model.engine.store.allProgress() else { return }
        rows = items.map { item in
            let p = progress[item.id]
            return LibraryRow(
                id: item.id,
                source: item.sourceForms.first?.form ?? item.id,
                target: (item.targetMeta?.gender).map { "\($0) \(item.target)" } ?? item.target,
                band: item.frequencyBand,
                stage: (p?.stage ?? .locked).rawValue,
                box: p?.srsBox ?? 0,
                due: p?.dueAt.map { formatter.localizedString(for: $0, relativeTo: Date()) } ?? "—"
            )
        }
    }
}
