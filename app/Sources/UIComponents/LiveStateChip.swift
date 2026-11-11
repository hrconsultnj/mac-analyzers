import SwiftUI

/// Liveness chip: green dot + ACTIVE while the row's process is still the
/// same running program; dimmed ENDED once it's gone (killed, quit, or the
/// pid was recycled). One component for the menu and the settings panes.
public struct LiveStateChip: View {
    let active: Bool

    public init(active: Bool) { self.active = active }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? Tokens.Status.live.tint : Tokens.Status.inert.tint)
                .frame(width: 5, height: 5)
            Text(active ? "Active" : "Ended")
                .font(.caption2.weight(.bold))
        }
        // one source for the tone (was a hardcoded Color.green/.secondary
        // alongside the token-driven dot/background — same colour, two sources)
        .foregroundStyle(active ? Tokens.Status.live.tint : Tokens.Status.inert.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((active ? Tokens.Status.live.tint : Tokens.Status.inert.tint).opacity(Tokens.Surface.tintFill), in: Capsule())
    }
}
