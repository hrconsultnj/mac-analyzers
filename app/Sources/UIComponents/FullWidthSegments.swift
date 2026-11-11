import SwiftUI

/// Full-width segmented tabs: equal-width filled pills spanning the whole
/// row (macOS's native segmented picker sizes to content and won't stretch).
public struct FullWidthSegments<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option

    public init(options: [(Option, String)], selection: Binding<Option>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { option, label in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(selected ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
        .frame(maxWidth: .infinity)
    }
}
