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
        // Flush chrome (visual-redesign plan §direction): no titlebar band —
        // the sidebar runs to the top and the traffic lights float over it.
        .windowStyle(.hiddenTitleBar)

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
                Text(menuStatus(overview))
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

    /// Actionable status, not a census: what is there to do right now?
    func menuStatus(_ overview: LearnerEngine.Overview) -> String {
        let actionable = overview.dueNow + overview.readyCount
        if actionable > 0 {
            return "\(actionable) word\(actionable == 1 ? "" : "s") to practice · tier \(overview.unlockedTier)"
        }
        if overview.introAvailable > 0 {
            return "New words available · tier \(overview.unlockedTier)"
        }
        return "All caught up · tier \(overview.unlockedTier)"
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
        Group {
            if model.needsOnboarding {
                OnboardingView()
                    .background(Theme.bg)
            } else {
                // Tint zones, no borders: the sidebar/content difference is
                // background alone (prototype-v2 frame).
                HStack(spacing: 0) {
                    SidebarView()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.bg)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    var detail: some View {
        switch model.section ?? .dashboard {
        case .dashboard: DashboardView()
        case .practice: PracticeView()
        case .library: LibraryView()
        case .tutor: TutorView()
        case .settings: SettingsView()
        }
    }
}

/// Custom sidebar: full-height tint zone under the floating traffic lights,
/// indigo selection with a gold active icon, extension status in the footer
/// (the one home of the old status-bar data).
struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                CockatooMark(eyeColor: Theme.sideBg)
                    .frame(width: 17, height: 17)
                Text("Cockatoo")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            VStack(spacing: 1) {
                ForEach(AppSection.allCases, id: \.self, content: row)
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
            footer
                .padding(.horizontal, 21)
                .padding(.bottom, 14)
        }
        .padding(.top, Theme.chromeTop)
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .background(Theme.sideBg)
    }

    func row(_ section: AppSection) -> some View {
        let isOn = (model.section ?? .dashboard) == section
        return Button {
            model.section = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 17)
                    .foregroundStyle(isOn ? Theme.gold : Theme.inkMuted.opacity(0.82))
                Text(section.title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(isOn ? Theme.ink : Theme.inkMuted)
                Spacer(minLength: 0)
                if section == .practice, let due = model.overview?.dueNow, due > 0 {
                    Text("\(due)")
                        .font(Theme.monoLabel())
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.line2))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .fill(isOn ? Theme.selection : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(isOn ? Theme.selectionLine : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    var footer: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(model.lastExtensionContact != nil ? Theme.live : Theme.inkFaint)
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.lastExtensionContact != nil ? "Extension connected" : "Extension not connected")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
                if let contact = model.lastExtensionContact {
                    Text("synced \(RelativeDateTimeFormatter().localizedString(for: contact, relativeTo: Date()))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
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
