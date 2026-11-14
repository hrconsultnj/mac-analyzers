import SwiftUI

/// Single-select filter chips with live counts ("Killed (4)"): the one chip
/// component every screen uses.
public struct FilterChipsBar<Option: Hashable>: View {
    public struct Chip {
        let option: Option
        let label: String
        let count: Int
        let color: Color

        public init(_ option: Option, _ label: String, count: Int, color: Color) {
            self.option = option
            self.label = label
            self.count = count
            self.color = color
        }
    }

    let chips: [Chip]
    @Binding var selection: Option

    public init(chips: [Chip], selection: Binding<Option>) {
        self.chips = chips
        self._selection = selection
    }

    /// One system toggle button per chip, single-select: the standard bordered
    /// button height (24 points) and padding, tinted by the chip's colour while
    /// it is chosen. They were hand-drawn capsules 19 points high with no press,
    /// focus or keyboard behaviour.
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(chips, id: \.option) { chip in
                    Toggle(isOn: Binding(get: { chip.option == selection },
                                         set: { if $0 { selection = chip.option } })) {
                        Text(chip.count > 0 ? "\(chip.label) (\(chip.count))" : chip.label)
                    }
                    .toggleStyle(.button)
                    .tint(chip.color)
                }
            }
            .padding(.vertical, Tokens.Space.hair)     // room for the focus ring inside the scroll view
        }
    }
}
