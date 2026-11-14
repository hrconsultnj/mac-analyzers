import AppKit
import Foundation

/// The apps macOS says open a web link: the browsers, with no list of them to keep. A public API
/// (`NSWorkspace.urlsForApplications(toOpen:)`), asked once per census.
enum BrowserHandlers {

    /// Each handler's bundle identifier (lowercased) and path.
    static func current() -> Set<String> {
        guard let link = URL(string: "https://www.example.com") else { return [] }
        var found = Set<String>()
        for app in NSWorkspace.shared.urlsForApplications(toOpen: link) {
            found.insert(app.path)
            if let id = Bundle(url: app)?.bundleIdentifier { found.insert(id.lowercased()) }
        }
        return found
    }
}
