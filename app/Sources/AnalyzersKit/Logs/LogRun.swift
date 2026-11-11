import Foundation

public struct LogRun: Identifiable, Hashable, Sendable {
    public let id: Int
    public let header: String
    public let lines: [String]

    public init(id: Int, header: String, lines: [String]) {
        self.id = id
        self.header = header
        self.lines = lines
    }

    /// First content line that reads as a summary (DONE/DRY/freed …).
    public var summary: String? {
        lines.first {
            !$0.hasPrefix("### ") &&
            ($0.contains("DONE") || $0.contains("DRY RUN") || $0.contains("freed")
             || $0.contains("reclaim") || $0.contains("guard started") || $0.first?.isNumber == true)
        }
    }

    public var itemCount: Int {
        lines.filter { !$0.hasPrefix("### ") }.count
    }
}
