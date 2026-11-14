import SwiftUI
import AnalyzersKit

/// How the main window's sidebar starts: as the person left it, or fixed (a snapshot tool looks at one state).
public enum SidebarPresentation: Sendable {
    /// Shown unless the person hid it last time (the HIG: do not hide it by default).
    case remembered
    case shown
    case hidden
    /// Hidden, and the hover overlay is showing.
    case peeking
}

/// The sidebar's visibility lives in ONE place: the split view's `columnVisibility`, held by the main window. The
/// toolbar button's state, its tooltip and the View menu all derive from it, so a window resize, the menu, the button
/// and the person dragging the divider cannot disagree. It is remembered across launches under this key.
enum SidebarVisibility {
    static let key = "shell.sidebarHidden"

    static func restore(_ presentation: SidebarPresentation, from defaults: UserDefaults = .standard) -> NavigationSplitViewVisibility {
        switch presentation {
        case .shown: .all
        case .hidden, .peeking: .detailOnly
        case .remembered: defaults.bool(forKey: key) ? .detailOnly : .all
        }
    }

    static func save(_ visibility: NavigationSplitViewVisibility, to defaults: UserDefaults = .standard) {
        defaults.set(visibility == .detailOnly, forKey: key)
    }
}

/// The sidebar button, next to the traffic lights: on while the sidebar is shown, off while it is hidden, with a
/// tooltip that says what a press does. A `Toggle`, so VoiceOver reads on or off.
struct SidebarToggleItem: ToolbarContent {
    @Binding var visibility: NavigationSplitViewVisibility
    let peek: SidebarPeek

    private var shown: Bool { visibility != .detailOnly }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Toggle(isOn: Binding(get: { shown }, set: { visibility = $0 ? .all : .detailOnly })) {
                Label(Names.Sidebar.title, systemImage: "sidebar.leading")
                    // on: the accent colour on the icon, so shown and hidden read apart at a glance
                    .foregroundStyle(shown ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help(shown ? Names.Sidebar.hide : Names.Sidebar.show)
            // hovering the button while the sidebar is hidden shows it as an overlay, like the edge does
            .onHover { inside in
                if shown { return }
                inside ? peek.enter(.toggle) : peek.exit(.toggle)
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// What the View menu needs from the main window: whether the sidebar is shown and how to flip it, and the same for
/// full screen. Published through `focusedSceneValue`, so the menu items always act on the window in front and read
/// its state; the sidebar item is the window's own visibility, not a second flag.
struct SidebarCommandState {
    let shown: Bool
    let toggle: () -> Void
    let isFullScreen: Bool
    let toggleFullScreen: () -> Void
}

extension FocusedValues {
    @Entry var sidebarCommands: SidebarCommandState?
}
