import SwiftUI

/// Liveness chip: green dot + ACTIVE while the row's process is still the
/// same running program; dimmed ENDED once it's gone (killed, quit, or the
/// pid was recycled). One component for the menu and the settings panes.
public struct LiveStateChip: View {
    let active: Bool

    public init(active: Bool) { self.active = active }

    public var body: some View {
        // a system label (dot + word) tinted by state; it was a hand-drawn capsule
        // behind a circle and a bold caption
        Label(active ? "Active" : "Ended", systemImage: "circle.fill")
            .font(.caption)
            .imageScale(.small)
            .foregroundStyle(active ? Tokens.Status.live.tint : Tokens.Status.inert.tint)
    }
}
