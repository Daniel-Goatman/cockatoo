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
        .defaultSize(width: 880, height: 580)

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
        HStack(spacing: 3) {
            Image(nsImage: Self.markTemplate)
            if !badge.isEmpty { Text(badge) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cockatooOpenDashboard)) { _ in
            openDashboardWindow(openWindow)
        }
    }

    /// The cockatoo mark as a template image — mono, so it follows the menu
    /// bar like every native status item (the 16px pressure test in
    /// research/prototype-v2/menubar.html chose template over colored crest).
    static let markTemplate: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(CockatooBodyShape().path(in: rect).cgPath)
            ctx.fillPath()
            ctx.addPath(CockatooCrestShape().path(in: rect).cgPath)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()
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
        if overview.dueNow > 0 {
            return "\(overview.dueNow) word\(overview.dueNow == 1 ? "" : "s") due · \(overview.libraryCount) in your library"
        }
        if overview.newRemainingToday > 0, overview.introAvailable > 0 {
            return "New words available · \(overview.libraryCount) in your library"
        }
        return "All caught up · \(overview.libraryCount) in your library"
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
                        .id(model.section)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.bg)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: model.sidebarCollapsed)
                .animation(.easeOut(duration: 0.18), value: model.section)
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

    var collapsed: Bool { model.sidebarCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                CockatooMark(eyeColor: Theme.sideBg)
                    .frame(width: 17, height: 17)
                if !collapsed {
                    Text("Cockatoo")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.horizontal, collapsed ? 0 : 20)
            .padding(.bottom, 14)

            VStack(spacing: 1) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    SidebarRow(section: section, collapsed: collapsed)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            SidebarChevron(collapsed: collapsed) { model.toggleSidebar() }
                .padding(.horizontal, collapsed ? 0 : 18)
                .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
                .padding(.bottom, 10)
            footer
                .padding(.horizontal, collapsed ? 0 : 21)
                .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
                .padding(.bottom, 14)
        }
        .padding(.top, Theme.chromeTop)
        .frame(width: collapsed ? 64 : 212)
        .frame(maxHeight: .infinity)
        .background(Theme.sideBg)
    }

    var footer: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(model.lastExtensionContact != nil ? Theme.live : Theme.inkFaint)
                .frame(width: 7, height: 7)
                .padding(.top, 4)
                .help(model.lastExtensionContact != nil ? "Extension connected" : "Extension not connected")
            if !collapsed {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.lastExtensionContact != nil ? "Extension connected" : "Extension not connected")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                    if let contact = model.lastExtensionContact {
                        Text("synced \(RelativeDateTimeFormatter().localizedString(for: contact, relativeTo: Date()))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.inkFaint)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct SidebarRow: View {
    @EnvironmentObject var model: AppModel
    let section: AppSection
    let collapsed: Bool
    @State private var hovering = false

    var body: some View {
        let isOn = (model.section ?? .dashboard) == section
        Button {
            model.section = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 17)
                    .foregroundStyle(isOn ? Theme.gold : Theme.inkMuted.opacity(0.82))
                if !collapsed {
                    Text(section.title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(isOn ? Theme.ink : (hovering ? Theme.ink : Theme.inkMuted))
                        .lineLimit(1)
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
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.horizontal, collapsed ? 0 : 10)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .fill(isOn ? Theme.selection : (hovering ? Theme.surface : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(isOn ? Theme.selectionLine : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(collapsed ? section.title : "")
    }
}

/// The subtle chevron that expands/collapses a side panel. `edge` is the
/// window edge the panel lives on; the chevron points where the panel goes.
struct SidebarChevron: View {
    var edge: HorizontalEdge = .leading
    let collapsed: Bool
    let action: () -> Void
    @State private var hovering = false

    var icon: String {
        switch edge {
        case .leading: return collapsed ? "chevron.right" : "chevron.left"
        case .trailing: return collapsed ? "chevron.left" : "chevron.right"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? Theme.ink : Theme.inkFaint)
                .frame(width: 22, height: 22)
                .background(hovering ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(collapsed ? "Expand panel" : "Collapse panel")
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
