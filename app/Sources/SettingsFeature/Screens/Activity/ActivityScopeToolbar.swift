import SwiftUI

/// The scope control: four segments, an icon and a word each. A system
/// segmented `Picker` draws only the words on macOS, so the segments are
/// buttons in one capsule.
///
/// Attached from `ActivityView`'s own `.toolbar`, which sits inside the
/// navigation stack's content — a toolbar attached to the stack itself is
/// silently dropped.
struct ActivityScopeToolbar: ToolbarContent {
    @Binding var scope: ActivityScope

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ScopeSegments(scope: $scope)
        }
    }
}

/// The chosen segment shows its icon and its word, the others their icons
/// (each has its name as a tooltip and for VoiceOver). A word on every segment
/// measured wider than the toolbar has once a running job's status item shares
/// it at 900 points, and the whole control fell into the overflow menu; this
/// one fits beside the status item.
private struct ScopeSegments: View {
    @Binding var scope: ActivityScope

    var body: some View {
        segments(labelled: { $0 == scope })
        .help("Choose which runs to show")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }

    private func segments(labelled: @escaping (ActivityScope) -> Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(ActivityScope.allCases) { item in
                let selected = scope == item
                Button { scope = item } label: {
                    Group {
                        if labelled(item) {
                            Label(item.title, systemImage: item.symbol).labelStyle(.titleAndIcon)
                        } else {
                            Image(systemName: item.symbol)
                        }
                    }
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(selected ? Color.primary.opacity(0.14) : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
