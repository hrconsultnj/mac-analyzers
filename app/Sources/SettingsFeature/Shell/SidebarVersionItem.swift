import SwiftUI
import AnalyzersKit

/// The pinned item at the foot of the sidebar: the app's name, the version
/// that is running, and whether a newer one exists. A click opens Updates.
/// It is part of the sidebar, so it goes when the sidebar is collapsed.
struct SidebarVersionItem: View {
    let navigator: Navigator
    @Environment(UpdateState.self) private var updates

    var body: some View {
        Button {
            navigator.select(AppGroup.updates)
        } label: {
            // Two arrangements, the first that fits: name and version on the
            // left with the state on the right; or, in a narrow sidebar, the
            // state on its own line underneath. Nothing is ever cut off — a
            // line that still does not fit wraps instead of ending in "…".
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    identity
                    Spacer(minLength: 4)
                    stateLabel
                }
                VStack(alignment: .leading, spacing: 2) {
                    identity
                    stateLabel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .help("Open \(Names.Screen.updates)")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(Names.Screen.updates)")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Names.app)
                .font(.callout.weight(.semibold))
            Text(updates.build.sidebarText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var stateLabel: some View {
        if let state {
            Label(state.text, systemImage: state.symbol)
                .font(.caption)
                .foregroundStyle(state.tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Nothing until a check has answered: an app that cannot reach the
    /// network says only its version rather than claiming to be current.
    private var state: (text: String, symbol: String, tint: Color)? {
        if updates.isAvailable {
            return (Names.State.updateAvailable, "arrow.down.circle.fill", .orange)
        }
        if updates.build.isDevelopment {
            return (Names.State.developmentBuild, "hammer.fill", .blue)
        }
        if updates.latest != nil {
            return (Names.State.upToDate, "checkmark.circle.fill", .secondary)
        }
        return nil
    }
}
