import Foundation

/// One app or developer and everything of theirs in a category: the parent row
/// that opens to its members.
public struct StartupGroup: Identifiable, Hashable, Sendable {
    public let category: StartupItem.Category
    public let name: String
    public let items: [StartupItem]

    public init(category: StartupItem.Category, name: String, items: [StartupItem]) {
        self.category = category
        self.name = name
        self.items = items
    }

    public var id: String { "\(category.rawValue)|\(name)" }
    public var count: Int { items.count }

    /// "3 items", or the one item's own state when there is only one.
    public var countText: String { "\(count) \(count == 1 ? "item" : "items")" }

    /// How the members are doing, in a few words: "2 running, 1 loaded".
    public var stateSummary: String {
        let order: [StartupItem.State] = [.running, .loaded, .enabled, .notLoaded, .disabled]
        return order.compactMap { state in
            let n = items.filter { $0.state == state }.count
            return n == 0 ? nil : "\(n) \(state.title.lowercased())"
        }.joined(separator: ", ")
    }

    /// The worst finding among the members, for the parent row.
    public var worstFinding: StartupItem.Finding {
        items.map(\.finding).min { $0.rank < $1.rank } ?? .fine
    }

    /// What a member is called when it stands alone as a row: its own name,
    /// with the app or developer in front unless the name already says it.
    public func standaloneTitle(for item: StartupItem) -> String {
        item.name.localizedCaseInsensitiveContains(name) ? item.name : "\(name) \(item.name)"
    }
}
