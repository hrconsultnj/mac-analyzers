import SwiftUI

extension View {
    /// The one inset of a bar above or below scrolling content: the tab bar, a table's notes or status line, the review's
    /// Apply bar, Network's totals bar, the Time Machine footer. The sides are the system's scene margin, the same as the
    /// window's content has; 8 points above and below keep a bar one line or one row of controls tall, not a card.
    /// A bar on the window's BOTTOM edge (`barMargin(edge: .bottom)`: the Apply bar, a footer) keeps 16 below, so its
    /// buttons do not sit against the window's rounded corners. Put it on the CONTENT of the bar
    /// (`safeAreaBar { content.barMargin() }`), never on the bar itself, so every bar of the app has the same inset and a
    /// change here changes them all.
    func barMargin(edge: VerticalEdge = .top) -> some View {
        scenePadding(.horizontal)
            .padding(.top, 8)                           // the one place the bar's vertical insets are written
            .padding(.bottom, edge == .bottom ? 16 : 8)
    }
}
