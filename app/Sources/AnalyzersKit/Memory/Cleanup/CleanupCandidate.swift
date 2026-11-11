import Foundation

/// One program the memory cleanup found, as a person reads it: a name, why it
/// is a candidate, how much memory it holds, and what became of it. Built from
/// the cleaner's own parsed run (`ReapItem`), never from its banner text —
/// no `[DRY]`, no `pid=…`, no flags.
public struct CleanupCandidate: Identifiable, Hashable, Sendable {

    public enum State: String, Sendable {
        /// A preview found it and a person may tick it.
        case readyToClose
        /// An app on the "also quit" list: asked to quit whatever is ticked.
        case willBeAskedToQuit
        /// The cleaner found it but left it alone (in use, or still busy).
        case leftAlone
        /// Belongs to a live session, so it is kept.
        case kept
        case closed
        case quit
        case alreadyGone
        /// Left out of what the person approved.
        case notApproved
    }

    public let id: String
    public let pid: Int?
    /// "Next.js dev server", "iOS Simulator", "Opera".
    public let name: String
    /// What distinguishes it: the project, the device, the version.
    public let detail: String?
    /// Why it is on the list, in a sentence.
    public let reason: String
    /// The kind of finding it came from ("Idle emulators and simulators").
    public let group: String
    public let memoryMB: Int?
    /// How many programs this row stands for (kept helpers are folded by name).
    public let count: Int
    public let state: State
    /// The kind of thing it is (level 2: a tab) and the app, project or session
    /// it belongs to (level 3: a row that opens).
    public let category: Category
    public let groupName: String
    /// Who this pid was when the review was read. An apply re-checks it, so a
    /// pid the system has since given to another program is left alone.
    public let identity: ProcessIdentity?

    /// The kinds of thing the cleaner finds, from what its sections classify.
    public enum Category: String, Sendable, CaseIterable {
        case devServers = "Dev Servers"
        case orphanedTools = "Orphaned Tools"
        case emulators = "Emulators & Browsers"
        case buildHelpers = "Build Helpers"
        case containers = "Containers"
        case editorHelpers = "Editor Helpers"
        case apps = "Apps on Your List"
        /// What the cleaner counts but never closes: live sessions' helpers.
        case liveSessions = "Live Sessions"

        public var symbol: String {
            switch self {
            case .devServers: "server.rack"
            case .orphanedTools: "wrench.and.screwdriver"
            case .emulators: "iphone"
            case .buildHelpers: "hammer"
            case .containers: "shippingbox"
            case .editorHelpers: "curlybraces"
            case .apps: "app"
            case .liveSessions: "person.2"
            }
        }
    }

    public var memoryBytes: Int64 { Int64(memoryMB ?? 0) * 1_048_576 }

    /// Only a program the preview found, with a pid to hand the engine.
    public var isSelectable: Bool { state == .readyToClose && pid != nil }

    /// The same row under another title (two rows of one group told apart).
    func renamed(_ title: String) -> CleanupCandidate {
        CleanupCandidate(id: id, pid: pid, name: title, detail: detail, reason: reason, group: group,
                         memoryMB: memoryMB, count: count, state: state, category: category,
                         groupName: groupName, identity: identity)
    }

    /// A row that is nothing — no memory to give back — folds into "N empty items".
    public var isEmpty: Bool { memoryBytes == 0 }

    /// What the engine is given for this row on an apply.
    public var approvalKey: String? { isSelectable ? pid.map(String.init) : nil }

    public var stateText: String {
        switch state {
        case .readyToClose: "Ready to Close"
        case .willBeAskedToQuit: "Will Be Asked to Quit"
        case .leftAlone: "Left Alone"
        case .kept: "Kept"
        case .closed: "Closed"
        case .quit: "Quit"
        case .alreadyGone: "Already Gone"
        case .notApproved: "Not Approved"
        }
    }

    /// Where the row sorts when nobody has chosen a sort: what can be acted on
    /// first, then what was left alone, then what is kept.
    public var rank: Int {
        switch state {
        case .readyToClose, .closed, .quit: 0
        case .willBeAskedToQuit: 1
        case .leftAlone, .notApproved, .alreadyGone: 2
        case .kept: 3
        }
    }
}
