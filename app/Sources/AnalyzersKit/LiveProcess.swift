import Foundation

/// Live system facts the menu reads on open — the same signals the guard
/// watches, so what you see is what the guard decides on.
public struct LiveProcess: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable { case devTool, app }

    public let pid: Int
    public let residentMB: Int
    public let rawName: String
    public let kind: Kind
    public let ppid: Int
    /// Memory footprint in bytes — Activity Monitor's "Memory" column. Set by
    /// the full census; nil on the guard-facing lists, which stay on
    /// `residentMB` because resident size is what the guard acts on.
    public let footprintBytes: Int64?
    /// The process's OWN name ("Opera Helper (Renderer)") where the census
    /// knows it — without it every helper in a family reads as its app.
    public let label: String?
    /// false where a Quit button has no business appearing: processes owned
    /// by macOS or another account (the request can't reach them), and
    /// macOS's own services running as the user — quitting `loginwindow`
    /// logs you out on the spot. They are shown and measured, never offered.
    public let canQuit: Bool
    /// Who this pid was when it was sampled: its start time. A stop re-checks it,
    /// so a row drawn minutes ago can never signal the program the system has
    /// since given the pid to. nil when it could not be read.
    public let identity: ProcessIdentity?
    public var id: Int { pid }

    public init(pid: Int, residentMB: Int, rawName: String, kind: Kind, ppid: Int = 0,
                footprintBytes: Int64? = nil, label: String? = nil, canQuit: Bool = true,
                identity: ProcessIdentity? = nil) {
        self.pid = pid
        self.residentMB = residentMB
        self.rawName = rawName
        self.kind = kind
        self.ppid = ppid
        self.footprintBytes = footprintBytes
        self.label = label
        self.canQuit = canQuit
        self.identity = identity
    }

    public var isDev: Bool { kind == .devTool }

    /// The number a row shows and sorts by: footprint when the census
    /// measured it, resident size otherwise.
    public var memoryBytes: Int64 { footprintBytes ?? Int64(residentMB) * 1_048_576 }
    public var memoryMB: Int { Int(memoryBytes / 1_048_576) }
    public var memoryText: String { MemorySize.text(memoryBytes) }

    /// Human name: glossary for dev tooling, .app bundle name for apps.
    public var friendlyName: String {
        if isDev, let known = ProcessGlossary.friendlyName(for: rawName) { return known }
        if let label { return label }
        if let app = AppBundleName.first(in: rawName) { return app }
        // bare binary name (helpers/daemons outside .app bundles)
        return String(rawName.split(separator: " ").first.map {
            $0.split(separator: "/").last.map(String.init) ?? String($0)
        } ?? rawName)
    }

    public var residentText: String { String(format: "%.1f GB", Double(residentMB) / 1024) }
}

/// A parent process with its heavy helpers rolled underneath — the Monitor
/// pane's Activity-Monitor-beating view: one row per APP, expandable.
public struct ProcessGroup: Identifiable, Sendable {
    public let parent: LiveProcess
    public let children: [LiveProcess]
    public var id: Int { parent.pid }

    public init(parent: LiveProcess, children: [LiveProcess]) {
        self.parent = parent
        self.children = children
    }

    public var totalMB: Int { parent.residentMB + children.map(\.residentMB).reduce(0, +) }
    public var totalText: String { String(format: "%.1f GB", Double(totalMB) / 1024) }
}
