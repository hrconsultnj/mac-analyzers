import AppKit
import AnalyzersKit

/// The standard "About Sparehold" window: the system's panel shows the name, icon and version on its own; the credits
/// line carries the link to the README that used to sit at the foot of How It Works.
@MainActor
enum AboutPanel {
    static let readme = URL(string: "https://github.com/hrconsultnj/sparehold")!

    static func show() {
        let credits = NSMutableAttributedString(
            string: "README on GitHub",
            attributes: [.link: readme, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centred, range: NSRange(location: 0, length: credits.length))
        // the panel's own version line would show the bundle's release number even on a development build; the sidebar and
        // Updates show `BuildInfo`'s version, so the panel shows the same one
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationVersion: BuildInfo.current.shortVersion,
            // the panel appends the bundle's build number in brackets ("(2)"); the commit it was built from says more
            .version: BuildInfo.current.commit.map { String($0.prefix(7)) } ?? "",
        ])
        NSApp.activate()
    }
}
