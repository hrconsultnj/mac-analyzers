import AnalyzersKit
import Foundation

/// What a person reads for a status token the engine prints in capitals
/// ("NEEDS SUDO", "IDLE OR COMPLETE"). The token stays the identifier — it is
/// what the parsers match and the logs contain — and this is its label: title
/// style, small words lowercase.
public enum TokenLabel {

    public static func title(_ token: String) -> String {
        let small = TitleStyle.smallWords.union(["in", "on"])
        let words = token.split(separator: " ").map(String.init)
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            if index > 0, index < words.count - 1, small.contains(lower) { return lower }
            return lower.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-")
        }.joined(separator: " ")
    }
}
