import Foundation

extension CensusGroup.Category {
    /// The category's short name, where the screen's own name for it is long: Monitor's tabs and the
    /// menu-bar panel's sections use the same words.
    public var shortTitle: String {
        switch self {
        case .apps: Names.Category.apps
        case .tools: Names.Monitor.tools
        case .system: Names.Category.system
        }
    }

    public var symbol: String {
        switch self {
        case .apps: "app.fill"
        case .tools: "terminal.fill"
        case .system: "gearshape.fill"
        }
    }

    /// The Monitor deep link that opens on this category (`monitor:apps`, `monitor:tools`, `monitor:macos`).
    public var monitorLink: String {
        switch self {
        case .apps: "monitor:apps"
        case .tools: "monitor:tools"
        case .system: "monitor:macos"
        }
    }
}
