import AppKit
import SwiftUI
import AnalyzersKit

/// The main window: sidebar on the left, one navigation stack per section on
/// the right. This file is the table of contents — what is on the screen
/// lives in the groups, how it moves lives in the `Navigator`.
///
///   Navigator.swift          selection, per-section paths, one history
///   SectionRegistry.swift    the order of the sidebar groups
///   SidebarView.swift        the rows
///   SidebarVisibility.swift  shown or hidden (one source of truth) and the toolbar button
///   SidebarPeek.swift        the hover overlay that shows a hidden sidebar
///   HistoryToolbar.swift     back and forward
///   Screens/Activity/JobStatusToolbarItem.swift   the running job, on every screen
///   DeepLinkRouter.swift     target strings to locations
///   AppCommands.swift        the menu bar
public struct MainWindowView: View {
    /// Holds the navigator so it is built once, on first use, instead of on
    /// every re-creation of this view struct.
    @State private var session: Session
    @Environment(JobStore.self) private var jobs
    @Environment(UpdateState.self) private var updates
    private var navigator: Navigator { session.navigator }
    /// The ONE record of whether the sidebar is shown: the toolbar button, its tooltip and the View menu all derive from it.
    @State private var visibility: NavigationSplitViewVisibility
    @State private var peek: SidebarPeek
    @State private var isFullScreen = false

    /// `restoresLocation: false` starts at the home screen and never reads or writes the
    /// saved location: for tools (SnapshotRunner) that open a window to look at one target.
    /// `sidebar` fixes how the sidebar starts for such a tool; the app leaves it to what the person chose.
    public init(restoresLocation: Bool = true, sidebar: SidebarPresentation = .remembered) {
        _session = State(initialValue: Session(restores: restoresLocation))
        _visibility = State(initialValue: SidebarVisibility.restore(restoresLocation ? sidebar : (sidebar == .remembered ? .shown : sidebar)))
        _peek = State(initialValue: SidebarPeek(showing: sidebar == .peeking))
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            SidebarView(navigator: navigator)
                // our own button below stands in for the system's, which cannot show whether the sidebar is shown
                .toolbar(removing: .sidebarToggle)
                // shown: the button is declared in the sidebar's own toolbar ...
                .toolbar {
                    if visibility != .detailOnly { SidebarToggleItem(shown: true, toggle: toggleSidebar, peek: peek, placement: .primaryAction) }
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                // The window's minimum is set HERE, on the content, and not on the whole split view: a minimum on
                // the split view is added to the sidebar's width when the sidebar shows, and the window grew by
                // the sidebar every time it was shown (measured: 900 wide became 1111). With the sidebar shown the
                // window is at least this plus the sidebar (710 to 780); with it hidden, this.
                .frame(minWidth: 520, minHeight: 568)
                .overlay(alignment: .leading) {
                    // while the sidebar is hidden: the hover strip, and the sidebar itself as an overlay
                    if visibility == .detailOnly {
                        SidebarPeekOverlay(peek: peek, navigator: navigator, isFullScreen: isFullScreen)
                    }
                }
        }
        // On the split view, not on the stack inside it: a toolbar attached
        // to a NavigationStack itself (rather than to something inside it) is
        // dropped, which left the window with no Back or Forward button at all.
        .toolbar {
            // ... hidden: in the content's. One button, one place beside the traffic lights, whichever state it is in.
            if visibility == .detailOnly { SidebarToggleItem(shown: false, toggle: toggleSidebar, peek: peek) }
            HistoryToolbar(navigator: navigator)
            JobStatusToolbarItem(store: jobs, navigator: navigator)
        }
        // full screen has the system's own edge reveal, which the hover strip must not fight; read from THIS window
        .background { FullScreenWatcher(isFullScreen: $isFullScreen) }
        // remembered, and a sidebar shown for real, or a row chosen, ends the overlay
        .onChange(of: visibility) { _, now in
            if session.restores { SidebarVisibility.save(now) }
            if now != .detailOnly { peek.dismiss() }
        }
        .onChange(of: navigator.section) { peek.dismiss() }
        // the Updates row's badge reads the one update state
        .task { UpdateBadge.shared.state = updates }
        .environment(navigator)
        .focusedSceneValue(\.navigator, navigator)
        .focusedSceneValue(\.sidebarCommands, SidebarCommandState(
            shown: visibility != .detailOnly,
            toggle: { toggleSidebar() }))
        .onReceive(NotificationCenter.default.publisher(for: NotifyChannel.toggleSidebarInternal)) { _ in toggleSidebar() }
        .onReceive(NotificationCenter.default.publisher(for: NotifyChannel.openPaneInternal)) { note in
            guard let target = note.userInfo?["target"] as? String else { return }
            DeepLinkRouter.open(target, in: navigator)
        }
        // Saved on every move, not only on close and quit: an app that is
        // force-quit, or ended by a restart, gets no chance to say goodbye,
        // and would reopen on wherever the window was last CLOSED.
        .onChange(of: navigator.location) { _, location in
            if session.restores { NavigationPersistence.save(location) }
        }
        .onDisappear {
            if session.restores { NavigationPersistence.save(navigator.location) }
            ActivationPolicy.windowClosed()
        }
    }

    /// Shows or hides the sidebar the way the system's own button does: `toggleSidebar:` down the responder chain
    /// collapses the split view item INSIDE the window, which keeps its size, and the split view writes the new state
    /// back into `visibility`, the one record every other part reads. Where nothing answers (a window with no split
    /// view controller yet), the visibility is set directly.
    private func toggleSidebar() {
        if NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil) { return }
        visibility = visibility == .detailOnly ? .all : .detailOnly
    }

    /// The current section's stack. Its path is the navigator's: the stack
    /// reads it, and its own pops and pushes are written back through
    /// `setPath`. Re-created per section so each starts from its own path.
    private var detail: some View {
        let section = navigator.section
        return NavigationStack(path: pathBinding(for: section)) {
            SectionRegistry.root(for: section)
                .environment(\.stackDepth, 0)
                .navigationDestination(for: Route.self) { $0.destination }
        }
        // The one toolbar rule for every screen: an action shows its icon AND its title (only search
        // is an icon). Set here, on the screens' stack and not on the split view, so the shell's own
        // Back and Forward stay icons; a screen's toolbar items read this from where they are declared.
        .labelStyle(.titleAndIcon)
        .id(section)
    }

    /// Bound to the section the stack was built for, not to whichever
    /// section is current when it writes.
    private func pathBinding(for section: SectionID) -> Binding<[Route]> {
        Binding(get: { navigator.paths[section] ?? [] },
                set: { navigator.setPath($0, in: section) })
    }

    @MainActor private final class Session {
        let restores: Bool
        init(restores: Bool) { self.restores = restores }
        lazy var navigator = Navigator(initial: restores ? NavigationPersistence.restore() : SectionRegistry.home)
    }
}
