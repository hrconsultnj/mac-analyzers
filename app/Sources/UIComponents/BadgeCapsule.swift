import SwiftUI

/// Small colored badge (KILLED/DRY/DONE…) shared by menu rows, log run rows
/// and detail rows.
public struct BadgeCapsule: View {
    let text: String
    let color: Color

    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(Tokens.Surface.tintFill), in: Capsule())
            .foregroundStyle(color)
    }
}
