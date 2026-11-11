import AnalyzersKit
import Foundation

/// Building the closed group of empty rows at the end of a level, so a level
/// of three real rows and fourteen empty ones shows four rows.
public enum OutlineFolding {

    /// The name of the fold, from the name table, so the review tables and every
    /// other screen call it the same thing.
    public static var name: String { Names.Fold.empty }

    /// What follows the name in the group cell: "14 items".
    public static func summary(count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    /// `rows` without the empty ones, followed by one fold row holding them.
    ///
    /// - Parameters:
    ///   - isEmpty: whether a row is one of the empty ones.
    ///   - minimum: fewer empty rows than this stay where they are.
    ///   - makeFold: builds the fold row from the empty rows (its children).
    ///     The fold is closed unless the caller's expansion set holds its id.
    public static func foldEmpty<Row>(_ rows: [Row], isEmpty: (Row) -> Bool, minimum: Int = 2,
                                      makeFold: (_ empties: [Row]) -> Row) -> [Row] {
        let empties = rows.filter(isEmpty)
        guard empties.count >= minimum else { return rows }
        return rows.filter { !isEmpty($0) } + [makeFold(empties)]
    }
}
