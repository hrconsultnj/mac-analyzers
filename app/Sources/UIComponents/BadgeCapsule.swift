import SwiftUI

/// Small colored badge (KILLED/DRY/DONE…) shared by menu rows, log run rows
/// and detail rows.
///
/// The hand-drawn capsule is the actual job here, decided 2026-11-11: a status badge is a label,
/// not a control, and the system has no status chip outside a list row's `.badge`. One drawing
/// for the whole app is the consistent answer; a screen never draws its own chip.
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
            .padding(.horizontal, Tokens.Space.s)
            .padding(.vertical, Tokens.Space.hair)
            .background(color.opacity(Tokens.Surface.tintFill), in: Capsule())
            .foregroundStyle(color)
    }
}
