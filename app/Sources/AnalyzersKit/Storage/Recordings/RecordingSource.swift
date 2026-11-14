import Foundation

/// One line of `ANALYZERS_RECORDING_SOURCES` in config.local.sh: which source, whether it is on, and the folder
/// the app resolved for it. The engine splits it as `id|state|path`, with the path last, so a `|` inside a path
/// stays part of the path.
public struct RecordingSourceEntry: Equatable, Hashable, Sendable {
    /// A source of `lib/recording-sources.tsv`, or `custom`.
    public var id: String
    public var enabled: Bool
    public var path: String

    public init(id: String, enabled: Bool, path: String) {
        self.id = id
        self.enabled = enabled
        self.path = path
    }

    /// `id|on|/path`, or nil for anything else.
    public init?(parsing element: String, expandHome: (String) -> String = { $0 }) {
        guard let first = element.firstIndex(of: "|") else { return nil }
        let rest = element[element.index(after: first)...]
        guard let second = rest.firstIndex(of: "|") else { return nil }
        let id = String(element[..<first]), state = String(rest[..<second])
        let path = String(rest[rest.index(after: second)...])
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }), state == "on" || state == "off", !path.isEmpty else { return nil }
        self.init(id: id, enabled: state == "on", path: expandHome(path))
    }

    public var isCustom: Bool { id == RecordingSource.customID }

    /// What a tab, a row and the sheet call this source: the list's id, or the folder for a custom one.
    public var key: String { RecordingSource.key(id: id, path: path) }
}

/// A recording source as the app knows it: what the list says about the app, and what discovery found on this Mac.
public struct RecordingSource: Identifiable, Equatable, Sendable {
    public static let customID = "custom"

    /// The list's id, or `custom:<path>`: the tab id and the key of every row of this source.
    public let id: String
    /// The list's id (`zoom`), or `custom`.
    public let kind: String
    public let title: String
    public let symbol: String
    public let path: String?
    public var offer: Offer
    public var access: Access
    /// For a source offered off, the sentence shown with it; for one not offered, its reason.
    public let warning: String?
    /// Whether it is switched on now (saved, or the default for what was found).
    public var enabled: Bool

    public enum Offer: Equatable, Sendable {
        case on
        case offWithWarning
        case notOffered
    }

    public enum Access: Equatable, Sendable {
        case readable
        /// The folder is in a place macOS asks about (`Documents`, `Desktop`, `Downloads`): not looked at yet.
        case needsAccess(String)
        case missing
        /// The folder can never be a source (`RecordingFolderRule`): why, in a sentence. Never written to the config.
        case refused(String)
    }

    public static func key(id: String, path: String) -> String { id == customID ? "custom:\(path)" : id }

    public init(id: String, kind: String, title: String, symbol: String, path: String?, offer: Offer, access: Access,
                warning: String?, enabled: Bool) {
        self.id = id
        self.kind = kind
        self.title = title
        self.symbol = symbol
        self.path = path
        self.offer = offer
        self.access = access
        self.warning = warning
        self.enabled = enabled
    }

    public var isCustom: Bool { kind == Self.customID }
}
