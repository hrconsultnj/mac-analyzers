import SwiftUI
import AnalyzersKit

/// The Stop or Quit cell of a row Sparehold never stops by itself. At rest it shows a lock, the cue that the guard and
/// the cleanups leave this row alone; with the pointer on it, or when the keyboard has reached it, the lock gives way to
/// the row's own button, in the same place, so nothing moves.
///
/// The cell is ONE accessibility element: a button labelled with what it does and why the row is normally protected, whose
/// action is the stop. The lock is only the resting picture; the real button stays in the Tab order (it is transparent, not
/// removed), draws itself when focused, and answers Space like any other row button.
struct MonitorStopCell: View {
    let row: MonitorRow
    let verb: String
    let help: String
    let action: () -> Void
    /// Fixed by a render, which has no pointer and no focus.
    var showsButton = false
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var revealed: Bool { hovering || focused || showsButton }

    private var label: String {
        let reason = (row.protectionWhy ?? "never stopped by itself").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return "\(verb) \(row.name) (normally protected: \(reason))"
    }

    var body: some View {
        ZStack {
            Button(verb, action: action)
                .buttonStyle(.borderless)
                .focused($focused)
                .opacity(revealed ? 1 : 0)
            Image(systemName: "lock.fill")
                .foregroundStyle(.tertiary)
                .opacity(revealed ? 0 : 1)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(revealed ? help : (row.lockTip ?? help))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, action)
    }
}
