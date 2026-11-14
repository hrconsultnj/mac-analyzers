import Foundation
import Synchronization

/// What `lib/recording-sources.tsv` says about one recording app: the ONE list the engine (`cleanup.sh`) and the app
/// both read. The engine takes `layout`, `extensions`, `keepIf` and `warning` from it; the app takes the rest. A
/// list that cannot be read offers nothing, and the engine refuses to run with it missing.
public struct RecordingSourceDefinition: Equatable, Sendable {
    public enum Layout: String, Sendable { case folders, meetingFolders, files, none = "-" }

    public let id: String
    public let title: String
    public let symbol: String
    public let layout: Layout
    public let extensions: [String]
    public let keepIfZoomFile: Bool
    public let offer: RecordingSource.Offer
    public let findBy: [Step]
    public let warning: String?

    /// One way to find the source. The first step that finds it wins.
    public struct Step: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// A path in the app's own preference, then `suffix`.
            case defaults(domain: String, key: String, suffix: String)
            /// The Screenshot app's `location-screenrecording`, then `location`, then the Desktop.
            case screencapture
            case home(String)
            case documents(String)
            case movies(String)
            case app(String)
            case cloudStorage
            case always
        }
        public let kind: Kind
        /// The step only counts when this app is installed (`documents:Zoom@zoom.us`).
        public let onlyWithApp: String?
    }

    public var isOfferable: Bool { offer != .notOffered }
}

public enum RecordingSourceCatalog {

    /// The list, in the file's order.
    public static var definitions: [RecordingSourceDefinition] {
        state.withLock { current in
            let url = current.override ?? AnalyzersPaths.suiteRoot.appending(path: "lib/recording-sources.tsv")
            if let loaded = current.loaded, current.url == url { return loaded }
            let loaded = (try? String(contentsOf: url, encoding: .utf8)).map(parse) ?? []
            current.url = url
            current.loaded = loaded
            return loaded
        }
    }

    public static func definition(_ id: String) -> RecordingSourceDefinition? { definitions.first { $0.id == id } }

    /// The list is there and names at least one source.
    public static var isAvailable: Bool { !definitions.isEmpty }

    private struct State {
        var override: URL?
        var url: URL?
        var loaded: [RecordingSourceDefinition]?
    }
    private static let state = Mutex(State())

    /// A list file to read instead of the resolved suite's (a probe's checkout, a fixture). Test support.
    @_spi(TestSupport) public static func useList(at url: URL) {
        state.withLock { $0 = State(override: url) }
    }

    /// The same text the engine reads with awk: tab-separated, `#` comments, a lone `-` for an empty column.
    public static func parse(_ text: String) -> [RecordingSourceDefinition] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 9 else { return nil }
            func value(_ index: Int) -> String? { columns[index] == "-" || columns[index].isEmpty ? nil : columns[index] }
            let offer: RecordingSource.Offer
            switch columns[6] {
            case "on": offer = .on
            case "offWithWarning": offer = .offWithWarning
            default: offer = .notOffered
            }
            return RecordingSourceDefinition(
                id: columns[0], title: columns[1], symbol: columns[2],
                layout: RecordingSourceDefinition.Layout(rawValue: columns[3]) ?? .none,
                extensions: (value(4) ?? "").split(separator: ",").map(String.init),
                keepIfZoomFile: columns[5] == "zoomFile", offer: offer,
                findBy: (value(7) ?? "").split(separator: "|").compactMap { step(String($0)) },
                warning: value(8))
        }
    }

    private static func step(_ text: String) -> RecordingSourceDefinition.Step? {
        var body = text
        var gate: String?
        if let at = body.lastIndex(of: "@") { gate = String(body[body.index(after: at)...]); body = String(body[..<at]) }
        let parts = body.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        let kind: RecordingSourceDefinition.Step.Kind
        switch parts[0] {
        case "defaults" where parts.count == 4: kind = .defaults(domain: parts[1], key: parts[2], suffix: parts[3])
        case "screencapture": kind = .screencapture
        case "home" where parts.count >= 2: kind = .home(parts[1...].joined(separator: ":"))
        case "documents" where parts.count >= 2: kind = .documents(parts[1...].joined(separator: ":"))
        case "movies" where parts.count >= 2: kind = .movies(parts[1...].joined(separator: ":"))
        case "app" where parts.count >= 2: kind = .app(parts[1...].joined(separator: ":"))
        case "cloudstorage": kind = .cloudStorage
        case "always": kind = .always
        default: return nil
        }
        return .init(kind: kind, onlyWithApp: gate)
    }
}
