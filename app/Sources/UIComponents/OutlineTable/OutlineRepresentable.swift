import AppKit
import SwiftUI

/// What the table hands the coordinator on every update: the caller's rows and
/// bindings, and every modifier. Read fresh each time; nothing in it is kept
/// across updates except through the coordinator's own state.
struct OutlineConfiguration<Row: Identifiable> {
    var rows: [Row]
    var children: KeyPath<Row, [Row]?>
    var selection: OutlineSelection<Row.ID>
    var sortOrder: Binding<[KeyPathComparator<Row>]>?
    var expanded: Binding<Set<Row.ID>>
    var autosave: String
    var columns: [OutlineColumn<Row>]
    var menu: (@MainActor (Set<Row.ID>) -> AnyView)?
    var primaryAction: (@MainActor (Set<Row.ID>) -> Void)?
    var ticks: OutlineTicks<Row>?
    var rowEnabled: (@MainActor (Row) -> Bool)?
    var sectionHeader: (@MainActor (Row) -> OutlineSectionHeader?)?
    var showsColumnHeaders = true
    /// Off by default: stripes below the last row of a short table read as "still loading".
    var alternatingRows = false
}

/// A selection binding, single or multiple, as the one thing the coordinator reads.
struct OutlineSelection<ID: Hashable> {
    var allowsMultiple: Bool
    var get: @MainActor () -> Set<ID>
    var set: @MainActor (Set<ID>) -> Void
}

/// `makeNSView` builds the scroll view and the outline once; every later update
/// goes through the coordinator.
struct OutlineRepresentable<Row: Identifiable>: NSViewRepresentable {
    let configuration: OutlineConfiguration<Row>

    func makeCoordinator() -> OutlineCoordinator<Row> {
        OutlineCoordinator(configuration: configuration)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    /// The table is being taken away: what it queued for a later turn is dropped.
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: OutlineCoordinator<Row>) {
        coordinator.tearDown()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(configuration, environment: context.environment)
    }
}
