import Foundation
import os

/// The items AppKit holds. One node per row id, kept for as long as the id
/// exists, so the outline keeps expansion, selection and cell reuse by object
/// identity: an update replaces a node's `row`, never the node.
@MainActor
final class OutlineNode<Row: Identifiable> {
    let id: Row.ID
    var row: Row
    var header: OutlineSectionHeader?
    /// What AppKit currently knows as this node's children.
    var children: [OutlineNode] = []
    /// What the next update will make `children`. Only the updater reads it.
    var stagedChildren: [OutlineNode] = []
    /// Something at or below this node differs from what AppKit has (a child came,
    /// went or moved, here or anywhere underneath). Decides whether a CLOSED node
    /// is looked into: its whole subtree is then taken over and reloaded.
    var subtreeChanged = false
    /// How many lines of text its tallest cell shows (see `OutlineColumn.lines`).
    var lines = 1

    init(row: Row, header: OutlineSectionHeader?) {
        id = row.id
        self.row = row
        self.header = header
    }

    var isExpandable: Bool { !children.isEmpty }
}

/// The id to node map, and the staging of the next structure.
@MainActor
final class OutlineNodes<Row: Identifiable> {
    typealias Node = OutlineNode<Row>

    private(set) var byID: [Row.ID: Node] = [:]
    /// The top level, as AppKit currently knows it.
    var roots: [Node] = []
    /// The top level the next update will make `roots`.
    private(set) var stagedRoots: [Node] = []
    private var stagedByID: [Row.ID: Node] = [:]
    /// Whether the staged structure differs from what AppKit has: an id came,
    /// went, moved or changed parent. False for a values-only update, which then
    /// needs no diff at all.
    private(set) var structureChanged = false
    /// Nodes whose line count differs from the last update, on screen or not.
    private(set) var linesChanged: [Node] = []

    private static var log: Logger { Logger(subsystem: "com.mac-analyzers.app", category: "outline") }

    /// Builds the next structure from the caller's rows without touching what
    /// AppKit sees: existing ids reuse their node (its `row` replaced), new ids
    /// get a node. A duplicate id is a caller bug: the later occurrence is
    /// dropped and logged once at the fault level. Returns the duplicates dropped.
    @discardableResult
    func stage(rows: [Row], children: KeyPath<Row, [Row]?>,
               header: (@MainActor (Row) -> OutlineSectionHeader?)?,
               lines: (@MainActor (Row) -> Int)? = nil) -> Int {
        stagedByID.removeAll(keepingCapacity: true)
        linesChanged = []
        var duplicates = 0
        var changed = false
        func same(_ a: [Node], _ b: [Node]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { $0 === $1 } }

        func build(_ rows: [Row]) -> [Node] {
            var level: [Node] = []
            level.reserveCapacity(rows.count)
            for row in rows {
                let id = row.id
                if stagedByID[id] != nil { duplicates += 1; continue }
                let node: Node
                if let existing = byID[id] {
                    existing.row = row
                    existing.header = header?(row)
                    node = existing
                } else {
                    node = Node(row: row, header: header?(row))
                    changed = true
                }
                stagedByID[id] = node
                node.stagedChildren = []
                if let lines {
                    let count = lines(row)
                    if count != node.lines { node.lines = count; linesChanged.append(node) }
                }
                level.append(node)
                if let kids = row[keyPath: children], !kids.isEmpty {
                    node.stagedChildren = build(kids)
                }
                let differs = !same(node.children, node.stagedChildren)
                if differs { changed = true }
                node.subtreeChanged = differs || node.stagedChildren.contains { $0.subtreeChanged }
            }
            return level
        }

        stagedRoots = build(rows)
        structureChanged = changed || !same(roots, stagedRoots) || stagedByID.count != byID.count
        if duplicates > 0 {
            Self.log.fault("OutlineTable: \(duplicates) duplicate row id(s) dropped; ids must be unique across the whole outline")
        }
        return duplicates
    }

    /// The staged structure is now what AppKit knows.
    func commit() {
        byID = stagedByID
        roots = stagedRoots
        stagedByID = [:]
        stagedRoots = []
    }

    func node(for id: Row.ID) -> Node? { byID[id] }
}
