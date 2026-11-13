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
            // One arrangement in every state: the name, the version and, when there is
            // one, the state, each on its own line. The sidebar is narrow and a state
            // such as "Update Available" does not fit beside the version, so it has the
            // whole row to itself and never wraps.
            VStack(alignment: .leading) {
                Text(Names.app).font(.subheadline.weight(.semibold))
                Text(updates.build.sidebarText).font(.caption).foregroundStyle(.secondary)
                stateLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .help("Open \(Names.Screen.updates)")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(Names.Screen.updates)")
    }

    @ViewBuilder private var stateLabel: some View {
        if let state {
            Label(state.text, systemImage: state.symbol)
                .font(.caption)
                .foregroundStyle(state.tint)
        }
    }

    /// Nothing until a check has answered: an app that cannot reach the
    /// network says only its version rather than claiming to be current.
    private var state: (text: String, symbol: String, tint: Color)? {
        switch updates.summary {
        case .updateAvailable?: return (Names.State.updateAvailable, "arrow.down.circle.fill", .orange)
        case .developmentBuild?: return (Names.State.developmentBuild, "hammer.fill", .blue)
        case .upToDate?: return (Names.State.upToDate, "checkmark.circle.fill", .secondary)
        case nil: return nil
        }
    }
}
