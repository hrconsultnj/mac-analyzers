import Foundation

/// Remembers where the user was when the main window closed. Plain
/// `UserDefaults`, not `@SceneStorage`: macOS destroys scene storage when a
/// window closes, and a closed window is this app's normal state. History is
/// not saved — it lasts one session.
@MainActor
enum NavigationPersistence {
    static let key = "nav.location"

    static func save(_ location: Location, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(location) else { return }
        defaults.set(data, forKey: key)
    }

    /// The saved location, or Overview when there is none, it cannot be read,
    /// or it names a screen this build no longer has.
    static func restore(from defaults: UserDefaults = .standard) -> Location {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode(Location.self, from: data),
              SectionRegistry.contains(saved.section)
        else { return SectionRegistry.home }
        // a job does not outlive the session that ran it
        let path = saved.path.filter { if case .job = $0 { false } else { true } }
        return Location(saved.section, path: path)
    }
}
