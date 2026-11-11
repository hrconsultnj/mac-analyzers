import SwiftUI

// STOPGAP. The foundation's `GroupRow` replaces this file; both outline tables
// (Login & Startup Items, Network) draw their parent row's Name cell here and
// nowhere else, so the swap is one place.
//
// The Name cell of a group's parent row: its icon, its name and how many it holds.
struct GroupCell<Icon: View>: View {
    let name: String
    let countText: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Label {
            HStack {
                Text(name).fontWeight(.medium)
                Text(countText).foregroundStyle(.secondary)
            }
        } icon: {
            icon()
        }
    }
}
