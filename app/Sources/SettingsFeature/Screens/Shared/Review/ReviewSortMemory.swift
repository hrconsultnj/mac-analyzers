import Foundation

/// The sort order of each screen's review table, kept per screen key like the open groups and the column
/// widths: a screen that replaces its table (every new preview) does not send the person back to Size,
/// largest first. Only the two orders the table offers (name, size) exist, so a pair of words is enough.
@MainActor
enum ReviewSortMemory {
    private static let named: [(word: String, path: PartialKeyPath<ReviewNode>)] = [
        ("name", \ReviewNode.sortName), ("size", \ReviewNode.sortBytes),
    ]

    /// What the table starts with when nothing was chosen: Size, largest first.
    static var standard: [KeyPathComparator<ReviewNode>] { [KeyPathComparator(\ReviewNode.sortBytes, order: .reverse)] }

    private static func key(_ screen: String) -> String { "review.sort.\(screen)" }

    static func order(for screen: String) -> [KeyPathComparator<ReviewNode>] {
        guard let saved = UserDefaults.standard.string(forKey: key(screen)) else { return standard }
        let parts = saved.split(separator: "|").map(String.init)
        guard parts.count == 2, let path = named.first(where: { $0.word == parts[0] })?.path else { return standard }
        let order: SortOrder = parts[1] == "reverse" ? .reverse : .forward
        if path == \ReviewNode.sortName { return [KeyPathComparator(\ReviewNode.sortName, order: order)] }
        return [KeyPathComparator(\ReviewNode.sortBytes, order: order)]
    }

    static func save(_ order: [KeyPathComparator<ReviewNode>], for screen: String) {
        guard let first = order.first, let word = named.first(where: { $0.path == first.keyPath })?.word else { return }
        UserDefaults.standard.set("\(word)|\(first.order == .reverse ? "reverse" : "forward")", forKey: key(screen))
    }
}
