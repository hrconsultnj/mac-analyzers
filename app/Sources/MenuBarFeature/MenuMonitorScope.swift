import AnalyzersKit

/// The panel's Monitor tabs: everything, then Monitor's three categories, in Monitor's words.
enum MonitorScope: String, CaseIterable, Sendable {
    case all, apps, tools, macos

    var category: CensusGroup.Category? {
        switch self {
        case .all: nil
        case .apps: .apps
        case .tools: .tools
        case .macos: .system
        }
    }

    var title: String { category?.shortTitle ?? Names.Scope.all }
    var symbol: String { category?.symbol ?? "square.stack.3d.up" }
}
