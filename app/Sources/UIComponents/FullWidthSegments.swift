import SwiftUI

/// Full-width segmented tabs, as the system draws them: a segmented `Picker`
/// stretched to the row. It was a stack of hand-drawn pills (5 pt of padding, a
/// filled accent rectangle); the system control has the standard height and
/// padding, the focus ring, keyboard arrows and the right look in every
/// appearance.
public struct FullWidthSegments<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option

    public init(options: [(Option, String)], selection: Binding<Option>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { option, label in
                Text(label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}
