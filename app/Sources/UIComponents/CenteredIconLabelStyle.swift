import SwiftUI

/// A label whose icon is centred on the whole title, however many lines it has.
///
/// The system's own label style lines the icon up with the FIRST line of its title, which is right for a
/// sentence that wraps and wrong for a row that shows a name with a second line under it: the icon
/// then sits level with the name instead of in the middle of the two lines. A one-line title looks the same
/// in both styles. Use this on a `Label` whose title is a stack of lines (the review table's name cell).
public struct CenteredIconLabelStyle: LabelStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == CenteredIconLabelStyle {
    /// See `CenteredIconLabelStyle`.
    public static var centeredIcon: CenteredIconLabelStyle { CenteredIconLabelStyle() }
}
