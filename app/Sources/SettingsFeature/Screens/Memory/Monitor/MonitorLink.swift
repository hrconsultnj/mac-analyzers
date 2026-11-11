import AnalyzersKit
import Foundation

/// What a deep link asks Monitor to show, carried as the one-shot request a
/// `SectionIntent` holds and applied by the screen once it has rows. It exists
/// so every state of the screen — an app selected, the details panel open, a
/// group's stop sheet — can be reached by a link, and therefore rendered
/// headless: `monitor:select:Opera`, `monitor:inspector`, `monitor:select:Node.js`,
/// `monitor:apps`, `monitor:energy`, `monitor:find:chrome`, `monitor:expanded`.
struct MonitorLink: Hashable, Codable {
    var lens: String?
    var scope: String?
    var query: String?
    var select: String?
    var stop: String?
    /// Opens the named row in place, as a click on its arrow does.
    var open: String?
    /// Shows the named group's stop sheet inside the window instead of as a
    /// sheet, so a render can capture it (a sheet is a separate window the
    /// headless capture cannot reach).
    var preview: String?
    var inspector = false
    var expandAll = false
    /// Selects the row for this process, wherever it sits; `why` says (in the app's own words) why a stop did not happen.
    var pid: Int?
    var why: StopWhy?

    var payload: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init(payload: String) {
        self = (try? JSONDecoder().decode(MonitorLink.self, from: Data(payload.utf8))) ?? MonitorLink()
    }

    init(lens: String? = nil, scope: String? = nil, query: String? = nil, select: String? = nil,
         stop: String? = nil, open: String? = nil, preview: String? = nil, inspector: Bool = false, expandAll: Bool = false) {
        self.lens = lens
        self.scope = scope
        self.query = query
        self.select = select
        self.stop = stop
        self.open = open
        self.preview = preview
        self.inspector = inspector
        self.expandAll = expandAll
    }

    /// The link a `monitor:…` target means, or nil when it names nothing.
    static func parse(_ rest: String) -> MonitorLink? {
        switch rest {
        case "inspector": return MonitorLink(inspector: true)
        case "expanded": return MonitorLink(expandAll: true)
        case "apps", "tools", "macos": return MonitorLink(scope: rest)
        case "energy", "disk": return MonitorLink(lens: rest)
        default: break
        }
        if rest.hasPrefix("select:") { return MonitorLink(select: String(rest.dropFirst(7)), inspector: true) }
        if rest.hasPrefix("preview:") { return MonitorLink(preview: String(rest.dropFirst(8))) }
        if rest.hasPrefix("open:") { return MonitorLink(open: String(rest.dropFirst(5))) }
        if rest.hasPrefix("stop:") { return MonitorLink(stop: String(rest.dropFirst(5))) }
        if rest.hasPrefix("pid:") {
            // monitor:pid:<N> or monitor:pid:<N>:why:<code>. A code the app does not know shows nothing.
            let tail = rest.dropFirst(4)
            let parts = tail.components(separatedBy: ":why:")
            guard let pid = Int(parts[0]) else { return nil }
            var link = MonitorLink(inspector: true)
            link.pid = pid
            link.why = parts.count > 1 ? StopWhy(code: parts[1]) : nil
            return link
        }
        if rest.hasPrefix("find:") { return MonitorLink(query: String(rest.dropFirst(5))) }
        return nil
    }
}
