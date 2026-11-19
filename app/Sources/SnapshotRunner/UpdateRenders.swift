import Foundation
import AnalyzersKit
import SettingsFeature

/// What the update window and the alerts of "Check for Updates…" look like, for `snapshot-runner`:
/// `--update-window` draws the window's own content (use `--size 520x560`), `--update-alert up-to-date|unreachable|clone|dev`
/// draws the system alert the command shows, from the alert's own views, without showing it (`UpdateAlerts.picture`).
enum UpdateRenders {

    /// A changelog with two releases and a beta's own unreleased notes: what `notesForOffered` reads at a tag.
    static let fixtureChangelog = """
    ## Next

    - The Updates screen follows the channel you pick. <!-- wn: open=update icon=sparkles title="Channels on Updates" -->
    - Check for Updates opens a window with the notes of every version in between. <!-- wn: open=update icon=arrow.down.circle title="Update Window" -->

    ## v2.73.1 — Smaller fixes
    <!-- wn: released=2026-11-20 -->

    - Memory Guard's tabs remember the one you used last. <!-- wn: open=guard icon=shield.lefthalf.filled title="Guard Tabs Remembered" -->

    ## v2.73.0 — A new Sparehold screen
    <!-- wn: released=2026-11-18 -->

    - The Sparehold item at the foot of the sidebar opens a screen about the app. <!-- wn: open=app icon=macwindow title="The Sparehold Screen" -->
    - Old Recordings reads every place a recording app saves. <!-- wn: open=recordings icon=film.stack title="Recording Sources" -->

    ## v2.72.0 — Setup and a welcome
    <!-- wn: released=2026-11-14 -->

    - A welcome that sets the app up the first time. <!-- wn: open=setup icon=checklist title="Welcome" -->
    """

    @MainActor static func updateWindow(kind: String) -> UpdateAvailableView {
        let beta = kind == "beta"
        let offered = beta ? "2.73.1 Beta" : "2.73.1"
        let notes = ReleaseNote.forUpdate(changelog: fixtureChangelog, installed: "2.72.0",
                                          offered: beta ? "2.73.1-beta.1" : "2.73.1", label: offered)
        return UpdateAvailableView(offered: offered, installed: "2.72.0", notes: notes, skip: {}, remindLater: {}, install: {})
    }

    /// Draws the alert of `kind` into a PNG and exits: 0 written, 1 when it could not be drawn. The alert itself is built and
    /// drawn in SettingsFeature (`UpdateAlerts.picture`) and never shown.
    @MainActor static func render(kind: String, updates: UpdateState, to output: URL, appearance: String?) -> Never {
        guard let png = UpdateAlerts.picture(kind: kind, updates: updates, dark: appearance == "dark") else {
            FileHandle.standardError.write(Data("snapshot-runner: the alert could not be drawn\n".utf8)); exit(1)
        }
        guard (try? png.write(to: output)) != nil else { exit(1) }
        print("update alert → \(output.path)")
        exit(0)
    }
}
