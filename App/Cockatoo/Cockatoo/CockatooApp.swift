import SwiftUI
import LearnerCore

@main
struct CockatooApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Unbundled dev runs (`swift run Cockatoo`) have no Info.plist, so
        // make the process a regular app: Dock icon + Cmd-Tab, and come to
        // the front on launch. Without this a hidden window is unfindable.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Cockatoo", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            MenuBarLabel(badge: model.dueBadge)
        }
    }
}

/// The menu bar label is the one view that exists for the app's whole
/// lifetime, so it hosts the listener that fronts the dashboard when the
/// Safari extension (via XPC) asks for it.
struct MenuBarLabel: View {
    let badge: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(badge, systemImage: "bird")
            .onReceive(NotificationCenter.default.publisher(for: .cockatooOpenDashboard)) { _ in
                openDashboardWindow(openWindow)
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
                openDashboardWindow(openWindow)
            }
            .keyboardShortcut("o")
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

/// Bring the dashboard back no matter what state it's in: closed (recreate),
/// hidden via Cmd-H (unhide), miniaturized (deminiaturize), or just buried.
@MainActor
func openDashboardWindow(_ openWindow: OpenWindowAction) {
    NSApp.setActivationPolicy(.regular)
    NSApp.unhide(nil)
    let existing = NSApp.windows.filter {
        $0.identifier?.rawValue.hasPrefix("main") == true || $0.title == "Cockatoo"
    }
    if existing.isEmpty {
        openWindow(id: "main")
    }
    for window in existing {
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
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
