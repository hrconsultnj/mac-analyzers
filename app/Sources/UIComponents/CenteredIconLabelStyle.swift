import SwiftUI

/// A label whose icon is centred on the whole title, however many lines it has.
///
/// The system's own label style lines the icon up with the FIRST line of its title, which is right for a
/// sentence that wraps and wrong for a row that shows a name with a second line under it: the icon
/// then sits level with the name instead of in the middle of the two lines. A one-line title looks the same
/// in both styles. Use this on a `Label` whose title is a stack of lines (the review table's name cell).
///
/// Give the icon a fixed size where rows must line up (the review table's is 20 x 20): the system style reserves an
/// icon column itself, this one takes the icon as it comes. VoiceOver reads the label as ONE element, its title,
/// as it does with the system style: the icon is decorative and hidden, the two are combined.
public struct CenteredIconLabelStyle: LabelStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon.accessibilityHidden(true)
            configuration.title
        }
        .accessibilityElement(children: .combine)
    }
}

extension LabelStyle where Self == CenteredIconLabelStyle {
    /// See `CenteredIconLabelStyle`.
    public static var centeredIcon: CenteredIconLabelStyle { CenteredIconLabelStyle() }
}
