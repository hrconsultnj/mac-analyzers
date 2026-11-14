import Foundation

/// The places the product really reads that macOS protects, as DATA: the protected set changes between macOS releases,
/// and Full Disk Access has no API to ask about, so the honest check is to try these (Apple's own advice). The
/// folder that holds the permission database is deliberately not here: reading it fails on macOS 27 even with the
/// permission granted.
public struct ProtectedPlace: Sendable, Equatable {
    public let id: String
    public let name: String
    /// Under the home folder.
    public let path: String
    /// What the storage report loses without it, in a phrase.
    public let hides: String

    public init(id: String, name: String, path: String, hides: String) {
        self.id = id
        self.name = name
        self.path = path
        self.hides = hides
    }
}

public enum ProtectedPlaces {
    public static let all: [ProtectedPlace] = [
        ProtectedPlace(id: "mail", name: "Mail", path: "Library/Mail", hides: "Mail downloads"),
        ProtectedPlace(id: "messages", name: "Messages Attachments", path: "Library/Messages/Attachments", hides: "Messages attachments"),
        ProtectedPlace(id: "safari", name: "Safari", path: "Library/Safari", hides: "Safari's data"),
        ProtectedPlace(id: "mailContainer", name: "Mail's Container", path: "Library/Containers/com.apple.mail",
                       hides: "other apps' data"),
    ]
}

/// What one try at reading a place came to.
public enum PlaceOutcome: Sendable, Equatable {
    /// It is not on this Mac: says nothing either way.
    case missing
    case readable
    /// `EPERM` on a place that exists: macOS refused, which is what a missing Full Disk Access looks like.
    case denied
    /// Any other error (`EACCES`, …): not counted, because it says nothing about Full Disk Access.
    case other(Int32)
}

/// The spot-check of the protected places. The reader is injected, so a probe judges the rule on stand-ins.
public enum FullDiskAccessProbe {

    /// The real reader: tries to open the folder and reads the error number.
    public static func read(_ path: String) -> PlaceOutcome {
        guard let handle = opendir(path) else {
            switch errno {
            case ENOENT, ENOTDIR: return .missing
            case EPERM: return .denied
            default: return .other(errno)
            }
        }
        closedir(handle)
        return .readable
    }

    /// Every place, tried once, in the order of `ProtectedPlaces.all`.
    public static func check(home: String = AnalyzersPaths.home.path, places: [ProtectedPlace] = ProtectedPlaces.all,
                             reader: (String) -> PlaceOutcome = read) -> [String: PlaceOutcome] {
        var result: [String: PlaceOutcome] = [:]
        for place in places { result[place.id] = reader("\(home)/\(place.path)") }
        return result
    }

    /// What the two readers (the app, and `agent-runner` as the background jobs run) add up to.
    public static func verdict(app: [String: PlaceOutcome], agent: [String: PlaceOutcome]?,
                               places: [ProtectedPlace] = ProtectedPlaces.all) -> (state: SetupItemState, evidence: String) {
        let present = places.filter { app[$0.id] != .missing && app[$0.id] != nil }
        guard !present.isEmpty else {
            return (.cantTell, "None of the folders Mac Analyzers checks exist on this Mac yet, so it can't tell.")
        }
        let denied = present.filter { app[$0.id] == .denied }
        let hidden = { (list: [ProtectedPlace]) in Names.Setup.list(list.map(\.hides)) }
        if !denied.isEmpty {
            return (.off, "Mac Analyzers can't read \(Names.Setup.list(denied.map(\.name))), so \(hidden(denied)) are left out of the storage report.")
        }
        if let agent {
            let agentDenied = places.filter { agent[$0.id] == .denied }
            if !agentDenied.isEmpty {
                return (.onlyApp, "The app can read \(Names.Setup.list(present.map(\.name))), but the background jobs can't read \(Names.Setup.list(agentDenied.map(\.name))), so their reports leave \(hidden(agentDenied)) out.")
            }
            return (.on, "\(present.count == 1 ? "The folder" : "All \(present.count) folders") the storage report reads can be read, by the app and by the background jobs.")
        }
        return (.on, "\(present.count == 1 ? "The folder" : "All \(present.count) folders") the storage report reads can be read by the app. The background jobs weren't checked here.")
    }
}
