import Foundation

/// The per-level diff of an outline update, by id. Pure: no AppKit. Public so
/// the probe can time it on its own.
///
/// For one level: the set difference gives what was removed and inserted; of
/// the ids present in both, the longest increasing subsequence of their old
/// positions (taken in new order) stays where it is and every other one is a
/// move. O(n log n) however the level was reordered, where a Myers diff over a
/// full re-sort of a 6,000-row level costs on the order of n squared.
public enum OutlineDiff {

    public struct Level<ID: Hashable> {
        /// Indexes in the old list whose id is gone.
        public var removed: [Int]
        /// Indexes in the new list whose id was not in the old one.
        public var inserted: [Int]
        /// The ids in both lists, in old order.
        public var survivorsOld: [ID]
        /// The ids in both lists, in new order.
        public var survivorsNew: [ID]
        /// For each element of `survivorsNew`: it does not have to move.
        public var stays: [Bool]
        /// For each element of `survivorsNew`: its position in `survivorsOld`.
        public var oldPositions: [Int]

        public var moveCount: Int { stays.reduce(0) { $0 + ($1 ? 0 : 1) } }
        public var lisLength: Int { stays.count - moveCount }
        public var isUnchanged: Bool { removed.isEmpty && inserted.isEmpty && moveCount == 0 }
    }

    public static func level<ID: Hashable>(old: [ID], new: [ID]) -> Level<ID> {
        // one dictionary (where each old id was); everything else is arrays indexed by position
        var oldIndex = [ID: Int](minimumCapacity: old.count)
        for (index, id) in old.enumerated() { oldIndex[id] = index }

        var seen = [Bool](repeating: false, count: old.count)         // old index: its id is still there
        var inserted: [Int] = []
        var survivorsNew: [ID] = []
        var oldIndexInNewOrder: [Int] = []
        survivorsNew.reserveCapacity(new.count)
        oldIndexInNewOrder.reserveCapacity(new.count)
        for (index, id) in new.enumerated() {
            if let position = oldIndex[id] {
                seen[position] = true
                survivorsNew.append(id)
                oldIndexInNewOrder.append(position)
            } else {
                inserted.append(index)
            }
        }

        var removed: [Int] = []
        var survivorsOld: [ID] = []
        var rank = [Int](repeating: -1, count: old.count)            // old index -> position among the survivors
        survivorsOld.reserveCapacity(old.count)
        for index in old.indices {
            if seen[index] {
                rank[index] = survivorsOld.count
                survivorsOld.append(old[index])
            } else {
                removed.append(index)
            }
        }

        let oldPositions = oldIndexInNewOrder.map { rank[$0] }
        var stays = [Bool](repeating: false, count: survivorsNew.count)
        for index in longestIncreasingSubsequence(oldPositions) { stays[index] = true }
        return Level(removed: removed, inserted: inserted, survivorsOld: survivorsOld,
                     survivorsNew: survivorsNew, stays: stays, oldPositions: oldPositions)
    }

    public struct Move: Equatable {
        public var from: Int
        public var to: Int
    }

    /// The `moveItem` calls that bring the survivors, in their old order, into
    /// their new order: each one outside the longest increasing subsequence moves
    /// once, to just after the survivor before it in the new order. `to` is the
    /// index the row has after the move (AppKit's meaning). Pure integers, so the
    /// search for positions runs as fast as plain arrays do; the caller applies
    /// the same removes and inserts to its own list by index.
    public static func moves(oldPositions: [Int], stays: [Bool]) -> [Move] {
        var current = Array(0..<oldPositions.count)
        var result: [Move] = []
        var previous = -1
        for (index, token) in oldPositions.enumerated() {
            defer { previous = token }
            if stays[index] { continue }
            let from = current.firstIndex(of: token) ?? 0
            current.remove(at: from)
            let to = previous < 0 ? 0 : (current.firstIndex(of: previous) ?? -1) + 1
            current.insert(token, at: to)
            if from != to { result.append(Move(from: from, to: to)) }
        }
        return result
    }

    /// Indexes into `values` of one longest strictly increasing subsequence
    /// (patience sorting with binary search).
    public static func longestIncreasingSubsequence(_ values: [Int]) -> [Int] {
        guard !values.isEmpty else { return [] }
        var tails: [Int] = []                                   // index into values of the smallest tail per length
        var previous = [Int](repeating: -1, count: values.count)
        for (index, value) in values.enumerated() {
            var low = 0, high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if values[tails[mid]] < value { low = mid + 1 } else { high = mid }
            }
            if low > 0 { previous[index] = tails[low - 1] }
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var result: [Int] = []
        var cursor = tails[tails.count - 1]
        while cursor >= 0 {
            result.append(cursor)
            cursor = previous[cursor]
        }
        return result.reversed()
    }
}
