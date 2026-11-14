import AppKit
import SwiftUI
import AnalyzersKit

/// Hover-to-reveal for a hidden sidebar, built in the app with public API only.
///
/// While the sidebar is hidden, resting the pointer on a narrow strip at the leading edge of the content, or on the
/// toggle button, shows the same live sidebar as an overlay above the content; the content never resizes, because
/// the split view's visibility is not touched. It stays while the pointer is over the strip, the overlay or the
/// button, and goes away shortly after the pointer leaves, on Escape, and after a row is chosen. Reduce Motion fades
/// instead of sliding. In full screen the system has its own edge reveal and this one stands aside.
@MainActor @Observable
final class SidebarPeek {

    enum Region { case edge, panel, toggle }

    private(set) var isShown = false
    private var inside: Set<Region> = []
    private var pending: Task<Void, Never>?

    /// How long the pointer must rest before it shows, and how long it must be gone before it hides: enough that
    /// passing over the edge, or leaving for a moment, does not flicker it.
    private static let showDelay: Duration = .milliseconds(120)
    private static let hideDelay: Duration = .milliseconds(350)

    init(showing: Bool = false) { isShown = showing }

    func enter(_ region: Region) {
        inside.insert(region)
        pending?.cancel()
        guard !isShown else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.showDelay)
            guard !Task.isCancelled else { return }
            self?.set(true)
        }
    }

    func exit(_ region: Region) {
        inside.remove(region)
        guard inside.isEmpty else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled else { return }
            self?.set(false)
        }
    }

    /// Escape, a chosen row, the sidebar being shown for real: gone now.
    func dismiss() {
        pending?.cancel()
        inside = []
        set(false)
    }

    private func set(_ shown: Bool) { if isShown != shown { isShown = shown } }
}

/// The overlay over the detail content: the hover strip, and while peeking the sidebar itself.
struct SidebarPeekOverlay: View {
    let peek: SidebarPeek
    let navigator: Navigator
    /// Full screen has the system's own edge reveal.
    let isFullScreen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The sidebar's normal width (`SidebarView` asks the split view for 190 to 260, ideally 210).
    private static let width: CGFloat = 210

    var body: some View {
        ZStack(alignment: .leading) {
            if !isFullScreen {
                // tracking only: it takes no clicks, so the content's first column and its leading controls still work
                HoverEdge(enter: { peek.enter(.edge) }, exit: { peek.exit(.edge) })
                    .frame(width: 8)
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if peek.isShown {
                panel
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.22), value: peek.isShown)
    }

    private var panel: some View {
        SidebarView(navigator: navigator, floating: true)
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 4)
            .padding(8)
            .contentShape(Rectangle())
            .onHover { inside in inside ? peek.enter(.panel) : peek.exit(.panel) }
            // in the tree only while shown, and named, for VoiceOver
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Names.Sidebar.title)
            // Escape puts it away only when the overlay itself has the keyboard; a search field or a sheet keeps its own Escape
            .onExitCommand { peek.dismiss() }
    }
}

/// A strip that reports the pointer entering and leaving WITHOUT taking clicks: its `hitTest` answers nil, and the
/// tracking area (public AppKit API) does not need a hit.
private struct HoverEdge: NSViewRepresentable {
    let enter: () -> Void
    let exit: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EdgeView()
        view.enter = enter
        view.exit = exit
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? EdgeView)?.enter = enter
        (view as? EdgeView)?.exit = exit
    }

    private final class EdgeView: NSView {
        var enter: (() -> Void)?
        var exit: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { enter?() }
        override func mouseExited(with event: NSEvent) { exit?() }
    }
}

/// Whether the window this view is in is in full screen, kept current. Only THIS window's notifications count, and the
/// first value is read from the window itself, so a window restored in full screen starts right.
struct FullScreenWatcher: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = WindowView()
        let coordinator = context.coordinator
        view.onWindow = { [binding = $isFullScreen] window in coordinator.watch(window) { binding.wrappedValue = $0 } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }

    @MainActor final class Coordinator {
        private var tasks: [Task<Void, Never>] = []

        func watch(_ window: NSWindow?, _ set: @escaping @MainActor (Bool) -> Void) {
            tasks.forEach { $0.cancel() }
            tasks = []
            guard let window else { return }
            set(window.styleMask.contains(.fullScreen))
            for (name, value) in [(NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false)] {
                tasks.append(Task { @MainActor in
                    for await _ in NotificationCenter.default.notifications(named: name, object: window) { set(value) }
                })
            }
        }

        deinit { tasks.forEach { $0.cancel() } }
    }
}
