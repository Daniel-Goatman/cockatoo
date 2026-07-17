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
            #if DEBUG
            if CommandLine.arguments.contains("--light-appearance") {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
            #endif
            NSApp.setActivationPolicy(.regular)
            // Launch Services may retain an older Dock / app-switcher image
            // when a development build is repeatedly replaced at the same
            // bundle URL. Re-apply the icon embedded by the asset catalog so
            // the running app always presents the artwork in this build.
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = icon
            }
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
            MenuBarLabel()
        }
    }
}

/// The menu bar label is the one view that exists for the app's whole
/// lifetime, so it hosts the listener that fronts the dashboard when the
/// Safari extension (via the app IPC port) asks for it.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.markTemplate)
            .accessibilityLabel("Cockatoo")
            .onReceive(NotificationCenter.default.publisher(for: .cockatooOpenDashboard)) { _ in
                openDashboardWindow(openWindow)
            }
    }

    /// A resolution-independent AppKit template image. The drawing handler is
    /// evaluated at the destination's backing scale, avoiding the jagged edge
    /// produced when a pre-rasterised 36px mask was enlarged or transformed.
    /// The compact body and spread crest take the system foreground colour;
    /// the outlined beak and eye use negative space.
    static let markTemplate: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let markRect = rect.insetBy(dx: 0.5, dy: 0.5)

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(CockatooToolbarCrestRootShape().path(in: markRect).cgPath)
            ctx.fillPath()

            // Fill overlapping silhouettes independently. Combining the head
            // and crest into one compound path lets their opposite windings
            // cancel, which punched a dark triangular patch into the join.
            ctx.addPath(CockatooToolbarCrestShape().path(in: markRect).cgPath)
            ctx.fillPath()
            ctx.addPath(CockatooToolbarBodyShape().path(in: markRect).cgPath)
            ctx.fillPath()

            // Negative space supplies the dark face details without fighting
            // macOS template tinting. The crest stays solid because its three
            // separated feathers are the recognition cue at status-item size.
            let upperBeakPath = CockatooToolbarUpperBeakShape().path(in: markRect).cgPath
            ctx.setBlendMode(.clear)
            ctx.addPath(upperBeakPath)
            ctx.fillPath()

            // Slightly oversizing the eye keeps it crisp after the 18pt image
            // is rasterised for a Retina menu bar.
            let eyeSide = max(1.0, markRect.width * 0.06)
            let eyeCenter = CGPoint(
                x: markRect.minX + markRect.width * 0.69,
                y: markRect.minY + markRect.height * 0.36
            )
            ctx.fillEllipse(in: CGRect(
                x: eyeCenter.x - eyeSide / 2,
                y: eyeCenter.y - eyeSide / 2,
                width: eyeSide,
                height: eyeSide
            ))

            // A foreground outline keeps the dark shapes distinct from the
            // menu-bar background without turning them back into solid blobs.
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(max(0.45, markRect.width * 0.027))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(upperBeakPath)
            ctx.strokePath()
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
        if let overview = model.overview {
            Text(menuStatus(overview))

            if overview.practiceAvailable {
                Button {
                    open(.practice)
                } label: {
                    Label(practiceTitle(overview), systemImage: "rectangle.stack.fill")
                }
            }

            Divider()
        }

        Button {
            open(.dashboard)
        } label: {
            Label("Open Overview", systemImage: AppSection.dashboard.icon)
        }
        .keyboardShortcut("o")

        Button {
            open(.library)
        } label: {
            Label("Library", systemImage: AppSection.library.icon)
        }

        Button {
            open(.settings)
        } label: {
            Label("Settings…", systemImage: AppSection.settings.icon)
        }
        .keyboardShortcut(",")

        Divider()

        Toggle("Pause Page Swaps", isOn: Binding(
            get: { model.paused },
            set: { paused in
                guard paused != model.paused else { return }
                model.togglePaused()
            }
        ))

        Divider()

        Button("Quit Cockatoo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Actionable status, not a census: what is there to do right now?
    func menuStatus(_ overview: LearnerEngine.Overview) -> String {
        if overview.dueNow > 0 {
            return "\(overview.dueNow) due · \(overview.libraryCount) in library"
        }
        if overview.newRemainingToday > 0, overview.introAvailable > 0 {
            return "New words · \(overview.libraryCount) in library"
        }
        return "All caught up · \(overview.libraryCount) in library"
    }

    func practiceTitle(_ overview: LearnerEngine.Overview) -> String {
        if overview.dueNow > 0 {
            return "Practice Now"
        }
        if overview.newRemainingToday > 0, overview.introAvailable > 0 {
            return "Practice New Words"
        }
        return "Practice"
    }

    private func open(_ section: AppSection) {
        model.section = section
        openDashboardWindow(openWindow)
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
    case dashboard, practice, library, settings

    var title: String {
        switch self {
        case .dashboard: return "Overview"
        case .practice: return "Practice"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .practice: return "rectangle.stack"
        case .library: return "books.vertical"
        case .settings: return "gearshape"
        }
    }
}
