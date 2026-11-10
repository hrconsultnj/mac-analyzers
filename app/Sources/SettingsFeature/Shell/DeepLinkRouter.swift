import Foundation
import AnalyzersKit
import os

/// Turns a deep-link target string into a place in the app.
///
/// Three inputs reach it, all with the same strings: `macanalyzers://pane/<target>`,
/// `--pane <target>`, and the in-process `com.mac-analyzers.open-pane`
/// notification (which the Pro overlay posts raw with `"support"`). Each group
/// answers the aliases for its own screens; the router just asks them in
/// order, so a target is never listed in two places.
@MainActor
enum DeepLinkRouter {

    enum Resolution: Equatable {
        case main(Location)
        case unknown
    }

    private static let log = Logger(subsystem: "com.mac-analyzers.app", category: "router")

    static func resolve(_ target: String) -> Resolution {
        let key = target.trimmingCharacters(in: .whitespacesAndNewlines)
        for group in SectionRegistry.groups {
            if let location = group.resolve(key) { return .main(location) }
        }
        return .unknown
    }

    /// Resolves and navigates; an unknown target is logged and ignored.
    static func open(_ target: String, in navigator: Navigator) {
        switch resolve(target) {
        case .main(let location):
            navigator.open(location)
        case .unknown:
            log.notice("ignored unknown deep-link target \(target, privacy: .public)")
        }
    }
}

extension Navigator {
    /// For a screen that sends the user somewhere by deep-link name — the same
    /// strings the menu bar and notifications use.
    func open(target: String) {
        DeepLinkRouter.open(target, in: self)
    }
}
