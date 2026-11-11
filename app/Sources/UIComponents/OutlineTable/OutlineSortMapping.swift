import AppKit
import SwiftUI

/// `KeyPathComparator` and `NSSortDescriptor` for the same column. The column's
/// `id` is the descriptor's key, so the mapping needs no key-path introspection.
@MainActor
enum OutlineSortMapping {

    /// The descriptor that makes AppKit draw the column's sort indicator.
    static func prototype<Row: Identifiable>(for column: OutlineColumn<Row>) -> NSSortDescriptor? {
        column.comparator == nil ? nil : NSSortDescriptor(key: column.id, ascending: true)
    }

    /// The comparators a header click means: the clicked column's comparator,
    /// ordered as the descriptor says.
    static func comparators<Row: Identifiable>(from descriptors: [NSSortDescriptor],
                                               columns: [OutlineColumn<Row>]) -> [KeyPathComparator<Row>] {
        descriptors.compactMap { descriptor in
            guard let key = descriptor.key,
                  var comparator = columns.first(where: { $0.id == key })?.comparator else { return nil }
            comparator.order = descriptor.ascending ? .forward : .reverse
            return comparator
        }
    }

    /// The descriptor for the first element of a binding, so a sort set in code
    /// still shows in the header. Matching compares with the order set to
    /// `.forward`, as each column declared its comparator.
    static func descriptors<Row: Identifiable>(for sortOrder: [KeyPathComparator<Row>],
                                               columns: [OutlineColumn<Row>]) -> [NSSortDescriptor] {
        guard var first = sortOrder.first else { return [] }
        let ascending = first.order == .forward
        first.order = .forward
        guard let column = columns.first(where: { $0.comparator == first }) else { return [] }
        return [NSSortDescriptor(key: column.id, ascending: ascending)]
    }
}
