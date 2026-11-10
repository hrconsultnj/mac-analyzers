import Foundation
import Observation
import os

/// The one owner of navigation: which section is selected, what is pushed on
/// each section, and a single back/forward history across all of it.
///
/// The rule that removes the old class of bugs: history is recorded in
/// exactly four mutators — `select`, `push`, `setPath`, `open` — and nowhere
/// else. `back` and `forward` only move the cursor and apply a stored
/// location; they cannot record, so there is no "time travelling" flag, no
/// observer that notices a change after the fact, and no coalescing.
@MainActor @Observable
final class Navigator {

    /// History is capped; the oldest stops fall off.
    static let historyLimit = 100

    private(set) var section: SectionID
    /// Each section keeps its own stack, so switching away and back returns
    /// to where that section was left.
    private(set) var paths: [SectionID: [Route]]
    private(set) var history: [Location]
    private(set) var cursor: Int

    private static let log = Logger(subsystem: "com.mac-analyzers.app", category: "nav")

    init(initial: Location) {
        section = initial.section
        paths = [initial.section: initial.path]
        // Back must reach a section's root before it leaves the section, so a
        // window restored onto a pushed screen starts with its root behind it.
        let stops = initial.path.isEmpty ? [initial] : [Location(initial.section), initial]
        history = stops
        cursor = stops.count - 1
    }

    var path: [Route] { paths[section] ?? [] }
    var location: Location { Location(section, path: path) }
    var canGoBack: Bool { cursor > 0 }
    var canGoForward: Bool { cursor < history.count - 1 }

    // MARK: - mutators that record

    /// A sidebar pick. Picking the row that is already selected does nothing
    /// (Finder behaviour); a deep link is the way to reset a section.
    func select(_ target: SectionID) {
        guard target != section else { return }
        Self.log.notice("switch \(self.section.rawValue, privacy: .public) -> \(target.rawValue, privacy: .public)")
        section = target
        record()
    }

    /// Pushes a screen on the current section.
    func push(_ route: Route) {
        paths[section, default: []].append(route)
        record()
    }

    /// The stack's own writes land here (a Back-button pop, a link push).
    /// Writing the path the model already holds is not a navigation, so the
    /// echo a programmatic change can produce is ignored rather than recorded
    /// twice.
    func setPath(_ newPath: [Route]) {
        guard newPath != path else { return }
        paths[section] = newPath
        record()
    }

    /// The same write, from the stack that belongs to `owner`. A stack that
    /// is on its way out can still write (an empty path, say) while Back,
    /// Forward or a sidebar pick has already made another section current;
    /// that write must not land in the new section.
    func setPath(_ newPath: [Route], in owner: SectionID) {
        guard owner == section else { return }
        setPath(newPath)
    }

    /// A deep link: a full location. It always replaces that section's path,
    /// so landing on a section you are already in returns it to the screen
    /// the link names instead of leaving a stale drill-down in place.
    func open(_ target: Location) {
        Self.log.notice("open \(target.section.rawValue, privacy: .public) depth \(target.path.count, privacy: .public)")
        section = target.section
        paths[target.section] = target.path
        record()
    }

    // MARK: - mutators that do not record

    func back() {
        guard canGoBack else { return }
        cursor -= 1
        apply(history[cursor])
    }

    func forward() {
        guard canGoForward else { return }
        cursor += 1
        apply(history[cursor])
    }

    // MARK: - private

    private func apply(_ stop: Location) {
        section = stop.section
        paths[stop.section] = stop.path
    }

    /// Appends the settled location. A new navigation after going back drops
    /// the forward stops; an unchanged location is not a stop.
    ///
    /// Invariant: from any location with a pushed screen, Back reaches that
    /// section's root before it leaves the section. Pushed screens have no
    /// system back button, so arriving on one from another section (a deep
    /// link, a sidebar pick onto a section that kept its stack) records the
    /// root first; otherwise the root would be unreachable.
    private func record() {
        let here = location
        guard history[cursor] != here else { return }
        history.removeSubrange((cursor + 1)...)
        if !here.path.isEmpty, history[cursor].section != here.section {
            history.append(Location(here.section))
        }
        history.append(here)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
        cursor = history.count - 1
    }
}
