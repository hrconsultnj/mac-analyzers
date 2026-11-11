import Foundation
import AnalyzersKit
import os

/// Turns a deep-link target string into a place in the app.
///
/// Three inputs reach it, all with the same strings: `macanalyzers://pane/<target>`,
/// `--pane <target>`, and the in-process `com.mac-analyzers.open-pane`
/// notification (which the Pro overlay posts raw with `"support"`). Each group
/// declares the targets for its own screens as data; the router consults every
/// group's fixed aliases first and only then the dynamic resolvers, so a
/// prefix rule in one group can never shadow an exact target in another.
@MainActor
public enum DeepLinkRouter {

    private static let log = Logger(subsystem: "com.mac-analyzers.app", category: "router")

    /// Targets that show a screen with example data, for looking at it headless. Empty
    /// in the app people install: only `SnapshotRunner` calls `installFixtures()`, so
    /// no URL, `--pane` or notification can reach one.
    private static var fixtureTargets: [String: Resolution] = [:]

    /// Makes the example screens linkable (`review:fixture`) and, for a run with no app bundle,
    /// names the changelog What's New reads. Called by SnapshotRunner, nothing else.
    public static func installFixtures(changelog: URL? = nil) {
        ReleaseNote.useDevelopmentFile(changelog)
        fixtureTargets = ["review:fixture": .main(Location(OverviewGroup.activity, path: [.overview(.reviewFixture)]))]
            .merging(StorageGroup.fixtureTargets) { _, storage in storage }
    }

    static func resolve(_ target: String) -> Resolution {
        let key = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fixture = fixtureTargets[key] { return fixture }
        for group in SectionRegistry.groups {
            if let resolution = group.aliases[key] { return resolution }
        }
        for group in SectionRegistry.groups {
            if let resolution = group.resolveDynamic?(key) { return resolution }
        }
        return .unknown
    }

    /// Which window a link belongs in. Asked by the always-alive receivers
    /// BEFORE any window is opened, so a link to a preference never has to
    /// bring up the main window first. Every preference link still lands in
    /// the main window (the interim Settings rows) until a Settings window
    /// exists; that phase returns `.preferences` here and edits only
    /// `PreferencesGroup`.
    public enum LinkWindow: Equatable {
        case main
        case preferences(tab: String)
    }

    public static func window(for target: String?) -> LinkWindow {
        guard let target, case .preferences(let tab) = resolve(target) else { return .main }
        log.notice("preferences tab \(tab, privacy: .public) has no window of its own yet — using the main window")
        return .main
    }

    /// Resolves and navigates; an unknown target is logged and ignored.
    static func open(_ target: String, in navigator: Navigator) {
        switch resolve(target) {
        case .main(let location):
            navigator.open(location)
        case .mainWithIntent(let location, let intent):
            navigator.open(location)
            navigator.setIntent(intent)
        case .preferences(let tab):
            // no Settings window yet: the interim row stands in for the tab
            navigator.open(PreferencesGroup.interimLocation(forTab: tab))
        case .unknown:
            log.notice("ignored unknown deep-link target \(target, privacy: .public)")
        }
    }
}

extension Navigator {
    /// For a screen that sends the user somewhere by deep-link name — the same
    /// strings the menu bar and notifications use.
    func open(target: String) {
        DeepLinkRouter.open(target, in: self)
    }
}
