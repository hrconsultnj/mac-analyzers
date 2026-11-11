import Observation
import SwiftUI

/// Which rows are open on one screen, kept across window close and relaunch
/// (`@SceneStorage` is lost when the window closes on macOS).
///
/// Stored in the app's own preferences under `outline.expanded.<screen>`.
@MainActor @Observable
public final class RememberedExpansion<ID: Hashable & LosslessStringConvertible> {

    private let key: String
    private let touchedKey: String

    /// The ids of the open rows. Ids of rows that are not on screen at the
    /// moment (filtered out) stay in the set, so filtering back reopens them.
    public var ids: Set<ID> {
        didSet { store() }
    }

    /// Whether the person has opened or closed anything yet.
    @ObservationIgnored private var touched: Bool

    public init(screen: String) {
        key = "outline.expanded.\(screen)"
        touchedKey = "outline.expanded.\(screen).touched"
        let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids = Set(stored.compactMap { ID($0) })
        touched = UserDefaults.standard.bool(forKey: touchedKey)
    }

    /// For `OutlineTable(expanded:)`. A write through it is the person opening
    /// or closing something, so it ends the seeding.
    public var binding: Binding<Set<ID>> {
        Binding(get: { self.ids },
                set: { self.touched = true; UserDefaults.standard.set(true, forKey: self.touchedKey); self.ids = $0 })
    }

    /// The first time this screen shows rows: open what the screen's default
    /// says (few groups: open; many: closed). Never changes anything once the
    /// person has opened or closed a row.
    public func seedIfUntouched(_ defaultOpen: @autoclosure () -> Set<ID>) {
        guard !touched else { return }
        let seed = defaultOpen()
        if seed != ids { ids = seed }
    }

    private func store() {
        UserDefaults.standard.set(ids.map(\.description).sorted(), forKey: key)
    }
}
