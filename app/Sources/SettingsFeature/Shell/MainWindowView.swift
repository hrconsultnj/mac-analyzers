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
///   DeepLinkRouter.swift     target strings to locations
///   AppCommands.swift        the menu bar
public struct MainWindowView: View {
    /// Holds the navigator so it is built once, on first use, instead of on
    /// every re-creation of this view struct.
    @State private var session = Session()
    private var navigator: Navigator { session.navigator }

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(navigator: navigator)
        } detail: {
            detail
        }
        .frame(minWidth: 780, minHeight: 620)
        .environment(navigator)
        .focusedSceneValue(\.navigator, navigator)
        .onReceive(NotificationCenter.default.publisher(for: NotifyChannel.openPaneInternal)) { note in
            guard let target = note.userInfo?["target"] as? String else { return }
            DeepLinkRouter.open(target, in: navigator)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            NavigationPersistence.save(navigator.location)
        }
        .onDisappear {
            NavigationPersistence.save(navigator.location)
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
        .toolbar { HistoryToolbar(navigator: navigator) }
    }

    /// Bound to the section the stack was built for, not to whichever
    /// section is current when it writes.
    private func pathBinding(for section: SectionID) -> Binding<[Route]> {
        Binding(get: { navigator.paths[section] ?? [] },
                set: { navigator.setPath($0, in: section) })
    }

    @MainActor private final class Session {
        lazy var navigator = Navigator(initial: NavigationPersistence.restore())
    }
}
