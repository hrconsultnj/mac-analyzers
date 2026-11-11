import Foundation
import os

/// What Apply may do right now, decided from the review and its preview alone.
public enum ReviewApplyGate: Equatable, Sendable {
    case ready
    /// No finished preview stands behind the rows (an example, or a read-only review).
    case noPreview
    /// The rows came from another preview than the one now current: acting on them
    /// would clean something nobody reviewed.
    case differentPreview
    /// More than `JobStore.reviewWindow` has passed since the preview finished.
    case expired

    /// The sentence the bar shows when Apply is not available; nil when it is.
    public var sentence: String? {
        switch self {
        case .ready: nil
        case .noPreview: nil
        case .differentPreview: "These rows are from an older preview. Preview again to review what would be cleaned now."
        case .expired: "This review is more than \(Int(JobStore.reviewWindow / 60)) minutes old. Preview Again to see what would be cleaned now."
        }
    }
}

/// Which rows of one review are ticked: the logic of the review table with no
/// screen in it, so a probe can prove it.
///
/// A review is tied to the preview its rows came from (`previewID`). Everything
/// starts ticked; a row that cannot be chosen (shown so a person sees what the
/// cleanup leaves alone) is never ticked and its key can never reach the approved
/// list, whatever else is done. Rows with the same key are kept once.
public struct ReviewSelection: Sendable {
    public struct Item: Sendable, Hashable {
        public let id: String
        public let choosable: Bool
        /// Not ticked here, but the apply acts on it by another argument ("will quit"): never
        /// choosable, never in the approved list, and not "kept" either.
        public let acts: Bool
        public init(id: String, choosable: Bool = true, acts: Bool = false) {
            self.id = id
            self.choosable = choosable && !acts
            self.acts = acts
        }
    }

    public let previewID: UUID
    /// Every key once, in the order the preview listed them.
    public private(set) var items: [Item]
    public private(set) var deselected: Set<String>
    private var choosable: Set<String>
    /// Rows that start unticked (the folded empty ones nobody can see): Select All leaves them as they are.
    private var startsUnticked: Set<String>

    /// `deselected` restores what a person had unticked for this same preview; nil means a
    /// first look, where `startsUnticked` rows are unticked and everything else is ticked.
    public init(previewID: UUID, items: [Item], deselected: Set<String>? = nil, startsUnticked: Set<String> = []) {
        self.previewID = previewID
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        if unique.count != items.count {
            // keep the first of each key and say so; a debug build must not stop for it
            Logger(subsystem: "com.mac-analyzers.app", category: "review")
                .error("a review was given \(items.count - unique.count) repeated key(s); the first of each is kept")
        }
        self.items = unique
        choosable = Set(unique.filter(\.choosable).map(\.id))
        self.startsUnticked = startsUnticked.intersection(choosable)
        self.deselected = (deselected ?? self.startsUnticked).intersection(choosable)
    }

    public func isChoosable(_ id: String) -> Bool { choosable.contains(id) }
    public func isTicked(_ id: String) -> Bool { choosable.contains(id) && !deselected.contains(id) }

    public mutating func setTicked(_ id: String, _ ticked: Bool) {
        guard choosable.contains(id) else { return }
        if ticked { deselected.remove(id) } else { deselected.insert(id) }
    }

    /// Ticks every visible row and leaves the folded ones as the person set them.
    public mutating func selectAll() { deselected.formIntersection(startsUnticked) }

    /// True when nothing but the folded rows is unticked: Select All has nothing to do.
    public var isAllSelected: Bool { deselected.isSubset(of: startsUnticked) }
    /// Changes which rows can be chosen while the review is open (a program ended): ticks on rows
    /// that stay choosable are untouched; a row that stops being choosable is unticked and can
    /// never be approved; a row that BECOMES choosable starts UNTICKED: nobody approves a row
    /// they only now see as choosable (a process whose session just ended joins the apply only
    /// when the person ticks it). Keys not in `now` and keys the review never listed are
    /// ignored. Returns whether any row actually changed, so a screen that calls this on every
    /// refresh can tell a quiet one from a real change.
    @discardableResult
    public mutating func updateChoosable(_ now: [String: Bool]) -> Bool {
        let before = choosable
        items = items.map { item in
            guard let canChoose = now[item.id], !item.acts else { return item }
            return Item(id: item.id, choosable: canChoose)
        }
        choosable = Set(items.filter(\.choosable).map(\.id))
        let became = choosable.subtracting(before)
        startsUnticked.formIntersection(choosable)
        deselected.formUnion(became)
        deselected.formIntersection(choosable)
        return choosable != before
    }

    public mutating func selectNone() { deselected = choosable }

    /// Whether any row is ticked, without building the list: the unticked rows are all choosable rows.
    public var hasTicked: Bool { choosable.count > deselected.count }

    public var tickedIDs: [String] { items.map(\.id).filter(isTicked) }
    public var actingIDs: [String] { items.filter(\.acts).map(\.id) }
    public var choosableCount: Int { choosable.count }

    /// What Apply sends. Rows that cannot be chosen are passed as deselected, so the set
    /// is narrowed whenever any exist and the list is sent: an apply with no list would
    /// let the engine clean everything it found, including what the review kept. When no
    /// row is kept and nothing is unticked the set is not narrowed and no list is sent,
    /// until the kernel patch makes the list always sent.
    public var approved: ApprovedSet {
        ApprovedSet(approvable: items.map(\.id), deselected: deselected.union(items.filter { !$0.choosable }.map(\.id)))
    }

    /// What a caller's own approval rule may send: its choice, minus anything this review does not
    /// allow. Kept rows, unticked rows (the fold's included) and keys the review never listed are
    /// removed whatever the caller returns; an unrestricted set means "the ticks".
    public func narrowed(_ wanted: ApprovedSet) -> ApprovedSet {
        // The result is a copy of the CALLER'S set, restricted: whatever else it carries rides along.
        // An unrestricted result means "the ticks", still through the caller's set.
        let keep = wanted.isUnrestricted ? Set(approved.approved) : Set(wanted.approved).intersection(Set(tickedIDs))
        return wanted.restricted(over: items.map(\.id), keeping: keep)
    }

    /// Whether Apply is allowed against `preview` at `now`.
    public func gate(previewID current: UUID?, finishedAt: Date?, now: Date = Date()) -> ReviewApplyGate {
        guard let current else { return .noPreview }
        guard current == previewID else { return .differentPreview }
        if let finishedAt, now.timeIntervalSince(finishedAt) > JobStore.reviewWindow { return .expired }
        return .ready
    }
}

/// What a person unticked, kept per preview so it outlives the screen: leaving a
/// review and coming back within its window shows the same ticks, not everything
/// ticked again. Dropped when the preview is applied, discarded or expires.
@MainActor
public final class ReviewTickStore {
    public static let shared = ReviewTickStore()
    public init() {}

    private var unticked: [UUID: Set<String>] = [:]

    /// nil when this preview has not been looked at before.
    public func deselected(for previewID: UUID) -> Set<String>? { unticked[previewID] }

    public func save(_ deselected: Set<String>, for previewID: UUID) {
        unticked[previewID] = deselected
    }

    public func drop(_ previewID: UUID) { unticked[previewID] = nil }

    /// Forgets every preview that is not in `live` (finished within the window and not dismissed).
    public func keepOnly(_ live: Set<UUID>) {
        unticked = unticked.filter { live.contains($0.key) }
    }
}

/// A value that belongs to one preview: asking for it with another preview's id (or
/// none) finds nothing, so what was done for one preview (an apply and its message) can
/// never show against the next.
public struct PerPreview<Value> {
    private var previewID: UUID?
    private var stored: Value?
    public init() {}
    public mutating func set(_ value: Value, for id: UUID) { previewID = id; stored = value }
    public func value(for id: UUID?) -> Value? { id != nil && id == previewID ? stored : nil }
}

/// A value built from an owner (a review's session) and a key (the sort order),
/// rebuilt whenever EITHER changes: a new review with the same number of rows is a
/// different owner, so it can never show the previous review's tree.
@MainActor
public final class IdentityMemo<Owner: AnyObject, Key: Equatable, Value> {
    private weak var owner: Owner?
    private var key: Key?
    private var built: Value?
    public private(set) var builds = 0
    public init() {}

    public func value(for owner: Owner, key: Key, build: () -> Value) -> Value {
        if let built, self.owner === owner, self.key == key { return built }
        let value = build()
        self.owner = owner
        self.key = key
        built = value
        builds += 1
        return value
    }
}
