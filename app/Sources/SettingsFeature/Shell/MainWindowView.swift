import SwiftUI
import AnalyzersKit

/// The main window: sidebar on the left, one navigation stack per section on
/// the right. This file is the table of contents — what is on the screen
/// lives in the groups, how it moves lives in the `Navigator`.
///
///   Navigator.swift          selection, per-section paths, one history
///   SectionRegistry.swift    the order of the sidebar groups
///   SidebarView.swift        the rows
///   HistoryToolbar.swift     back and forward
///   Screens/Activity/JobStatusToolbarItem.swift   the running job, on every screen
///   DeepLinkRouter.swift     target strings to locations
///   AppCommands.swift        the menu bar
public struct MainWindowView: View {
    /// Holds the navigator so it is built once, on first use, instead of on
    /// every re-creation of this view struct.
    @State private var session: Session
    @Environment(JobStore.self) private var jobs
    private var navigator: Navigator { session.navigator }

    /// `restoresLocation: false` starts at the home screen and never reads or writes the
    /// saved location: for tools (SnapshotRunner) that open a window to look at one target.
    public init(restoresLocation: Bool = true) {
        _session = State(initialValue: Session(restores: restoresLocation))
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(navigator: navigator)
        } detail: {
            detail
        }
        // On the split view, not on the stack inside it: a toolbar attached
        // to a NavigationStack itself (rather than to something inside it) is
        // dropped, which left the window with no Back or Forward button at all.
        .toolbar {
            HistoryToolbar(navigator: navigator)
            JobStatusToolbarItem(store: jobs, navigator: navigator)
        }
        .frame(minWidth: 780, minHeight: 620)
        .environment(navigator)
        .focusedSceneValue(\.navigator, navigator)
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

    /// The current section's stack. Its path is the navigator's: the stack
    /// reads it, and its own pops and pushes are written back through
    /// `setPath`. Re-created per section so each starts from its own path.
    private var detail: some View {
        let section = navigator.section
        return NavigationStack(path: pathBinding(for: section)) {
            SectionRegistry.root(for: section)
                .navigationDestination(for: Route.self) { $0.destination }
        }
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
