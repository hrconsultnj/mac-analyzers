import SwiftUI

/// One bar, several shares of a whole — where a fixed quantity (physical
/// memory) is right now. Segments keep their order; anything the segments
/// don't cover shows as empty track. The bar is the glance; every number it
/// encodes must also appear as text beside it (colour alone reaches no one
/// using VoiceOver or who can't tell the hues apart).
public struct StackedBar: View {
    public struct Segment: Identifiable {
        public let id: String
        public let value: Double
        public let color: Color

        public init(id: String, value: Double, color: Color) {
            self.id = id
            self.value = value
            self.color = color
        }
    }

    let segments: [Segment]
    let total: Double

    public init(segments: [Segment], total: Double) {
        self.segments = segments
        self.total = total
    }

    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: Tokens.Space.hair) {
                ForEach(segments) { segment in
                    if total > 0, segment.value > 0 {
                        Rectangle()
                            .fill(segment.color.gradient)
                            .frame(width: max(2, geo.size.width * segment.value / total))
                    }
                }
                Spacer(minLength: 0)
            }
            .background(Tokens.Surface.track)
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityHidden(true)  // the legend rows carry every value as text
    }
}
