import SwiftUI
import LearnerCore

@main
struct CockatooApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Cockatoo") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            Label(model.dueBadge, systemImage: "bird")
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading) {
            if let overview = model.overview {
                Text("\(overview.dueNow) due · tier \(overview.unlockedTier)")
            }
            Button(model.paused ? "Resume swapping" : "Pause swapping") {
                model.togglePaused()
            }
            Button("Open Cockatoo") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.needsOnboarding {
            OnboardingView()
        } else {
            NavigationSplitView {
                List(AppSection.allCases, id: \.self, selection: $model.section) { section in
                    Label(section.title, systemImage: section.icon)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            } detail: {
                switch model.section ?? .dashboard {
                case .dashboard: DashboardView()
                case .practice: PracticeView()
                case .library: LibraryView()
                case .tutor: TutorView()
                case .settings: SettingsView()
                }
            }
        }
    }
}

enum AppSection: CaseIterable, Hashable {
    case dashboard, practice, library, tutor, settings

    var title: String {
        switch self {
        case .dashboard: return "Overview"
        case .practice: return "Practice"
        case .library: return "Library"
        case .tutor: return "Tutor"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .practice: return "rectangle.stack"
        case .library: return "books.vertical"
        case .tutor: return "bubble.left.and.bubble.right"
        case .settings: return "gearshape"
        }
    }
}
