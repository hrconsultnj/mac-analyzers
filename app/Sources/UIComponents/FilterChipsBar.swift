import SwiftUI

/// Single-select filter chips with live counts ("Killed (4)") — the same
/// visual language as BadgeCapsule: tinted when idle, filled when selected.
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

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.option) { chip in
                    let selected = chip.option == selection
                    Button {
                        selection = chip.option
                    } label: {
                        Text(chip.count > 0 ? "\(chip.label) (\(chip.count))" : chip.label)
                            .font(.caption.weight(selected ? .bold : .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(selected ? chip.color : chip.color.opacity(Tokens.Surface.tintFill),
                                        in: Capsule())
                            .foregroundStyle(selected ? Color.white : chip.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
