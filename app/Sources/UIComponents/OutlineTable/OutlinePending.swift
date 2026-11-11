import Foundation

/// What the person did since the last flush, kept so an update that arrives
/// before the flush — carrying the caller's old values — is merged with it
/// instead of undoing what the person just did.
struct OutlinePending<Row: Identifiable> {
    var opened: Set<Row.ID> = []
    var closed: Set<Row.ID> = []
    var selection: Set<Row.ID>?
    var sortOrder: [KeyPathComparator<Row>]?
    /// What each ticked or unticked row shows until the caller has heard.
    var tickValues: [Row.ID: Bool] = [:]
    /// The writes to deliver, in the order the person made them.
    var tickWrites: [(id: Row.ID, value: Bool)] = []

    var isEmpty: Bool {
        opened.isEmpty && closed.isEmpty && selection == nil && sortOrder == nil && tickWrites.isEmpty
    }
}
