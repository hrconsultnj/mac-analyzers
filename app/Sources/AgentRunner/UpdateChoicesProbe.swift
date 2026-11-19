@_spi(TestSupport) import AnalyzersKit
import Foundation

/// `--probe-versions`, the update window's half: what a person's choices do (Check Automatically, Skip This Version, Remind Me
/// Later), the notes of every version between this copy and the one offered, and the words of the status card.
@MainActor
enum UpdateChoicesProbe {

    static func run(report: (String, Bool, String) -> Void) {
        let defaults = UserDefaults.standard
        let keys = [UpdateChoices.automaticKey, UpdateChoices.skippedKey, UpdateChoices.notifiedKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }

        report("checking automatically is on until switched off", UpdateChoices.automatic, "")
        report("a new version is announced", UpdateChoices.shouldNotify(of: "2.73.1"), "")
        UpdateChoices.didNotify(of: "2.73.1")
        report("   once: not again while it is the one announced", !UpdateChoices.shouldNotify(of: "2.73.1"), "")
        UpdateChoices.remindLater()
        report("Remind Me Later: it is announced again at the next automatic check", UpdateChoices.shouldNotify(of: "2.73.1"), "")
        UpdateChoices.skip("2.73.1")
        report("Skip This Version: that version is never announced", !UpdateChoices.shouldNotify(of: "2.73.1") && UpdateChoices.isSkipped("2.73.1"), "")
        UpdateChoices.remindLater()
        report("   not even after Remind Me Later", !UpdateChoices.shouldNotify(of: "2.73.1"), "")
        report("   but a newer version is", UpdateChoices.shouldNotify(of: "2.73.2"), "")
        report("   and a beta of that version is a different version", UpdateChoices.shouldNotify(of: "2.73.1-beta.1"), "")
        UpdateChoices.automatic = false
        report("Check Automatically off: nothing is announced", !UpdateChoices.shouldNotify(of: "9.9.9"), "")
        UpdateChoices.automatic = true

        // the notes of every version between this copy and the one offered, newest first
        let changelog = """
        ## Next

        - Beta notes. <!-- wn: open=update icon=sparkles title="Beta Notes" -->

        ## v2.73.1 — Third
        <!-- wn: released=2026-11-20 -->

        - Third release. <!-- wn: open=guard icon=shield.lefthalf.filled title="Third" -->

        ## v2.73.0 — Second
        <!-- wn: released=2026-11-18 -->

        - Second release. <!-- wn: open=app icon=macwindow title="Second" -->

        ## v2.72.0 — First
        <!-- wn: released=2026-11-14 -->

        - First release. <!-- wn: open=setup icon=checklist title="First" -->
        """
        func titles(_ notes: [ReleaseNote]) -> String { notes.map { $0.version.map { "v\($0)" } ?? $0.title }.joined(separator: ", ") }
        report("a copy on 2.72.0 offered 2.73.1 reads the two releases after it, newest first",
               titles(ReleaseNote.forUpdate(changelog: changelog, installed: "2.72.0", offered: "2.73.1", label: "2.73.1")) == "v2.73.1, v2.73.0",
               titles(ReleaseNote.forUpdate(changelog: changelog, installed: "2.72.0", offered: "2.73.1", label: "2.73.1")))
        report("   a beta of the version after it adds the beta's own notes on top, and not the release it leads to",
               titles(ReleaseNote.forUpdate(changelog: changelog, installed: "2.72.0", offered: "2.73.1-beta.1", label: "2.73.1 Beta")) == "2.73.1 Beta, v2.73.0",
               titles(ReleaseNote.forUpdate(changelog: changelog, installed: "2.72.0", offered: "2.73.1-beta.1", label: "2.73.1 Beta")))
        report("   a development copy of 2.72.1 is offered the same releases",
               titles(ReleaseNote.forUpdate(changelog: changelog, installed: "2.72.1-dev.5+abc1234", offered: "2.73.1", label: "2.73.1")) == "v2.73.1, v2.73.0", "")
        report("   one version apart: only that version",
               titles(ReleaseNote.forUpdate(changelog: changelog, installed: "2.73.0", offered: "2.73.1", label: "2.73.1")) == "v2.73.1", "")
        report("   nothing newer: no notes",
               ReleaseNote.forUpdate(changelog: changelog, installed: "2.73.1", offered: "2.73.1", label: "2.73.1").isEmpty, "")

        // the words of the status card
        func state(_ build: BuildInfo, latest: String?, reached: Bool? = true) -> UpdateState {
            let state = UpdateState(build: build, clone: { nil })
            state.preset(latest: latest, reached: reached)
            return state
        }
        let release = BuildInfo(release: "2.72.0", commitsAfter: 0, commit: "8e2c9b0" + String(repeating: "0", count: 33), releaseTag: "v2.72.0")
        func words(_ label: String, _ state: UpdateState, _ title: String, _ detail: String) {
            let ok = state.statusTitle == title && state.statusDetail == detail
            report("\(label): \"\(state.statusTitle)\" / \"\(state.statusDetail)\"", ok, ok ? "" : "expected \"\(title)\" / \"\(detail)\"")
        }
        words("up to date", state(release, latest: "2.72.0"), "Mac Analyzers is up to date", "You have v2.72.0.")
        words("a release is out", state(release, latest: "2.73.1"), "Mac Analyzers 2.73.1 is available", "You have v2.72.0.")
        let dev = BuildInfo(release: "2.72.0", commitsAfter: 12, commit: "8e2c9b0" + String(repeating: "0", count: 33), releaseTag: "v2.72.0")
        words("a Dev copy names itself", state(dev, latest: "2.72.0"), "Dev · 8e2c9b0", dev.developmentSentence(latest: "2.72.0"))
        words("GitHub could not be reached", state(release, latest: nil, reached: false), "Couldn't check for updates", Names.ChannelText.offline)
        let beta = state(release, latest: "2.72.0")
        beta.preset(channel: .beta, state: .offered("2.73.1 Beta"), newest: "2.73.1 Beta", betaTargetVersion: "2.73.1-beta.1")
        words("a beta is offered on Beta", beta, "Mac Analyzers 2.73.1 Beta is available", "You have v2.72.0.")
        report("   and the offer is the beta, by its internal version and its name",
               beta.offered?.version == "2.73.1-beta.1" && beta.offered?.label == "2.73.1 Beta", "\(String(describing: beta.offered))")
        report("a downloaded copy lists Releases and Beta, never This Copy", state(release, latest: "2.72.0").channels == [.releases, .beta], "")
        let downloaded = state(release, latest: "2.73.1")
        var fallbackCalled = false
        downloaded.installHandler = { _, _, _ in fallbackCalled = true; return false }
        downloaded.requestInstall()
        report("a downloaded copy (no clone) pressing Install on Releases does not wedge phase in .installing",
               downloaded.phase == .idle && fallbackCalled, "phase: \(downloaded.phase), handler called: \(fallbackCalled)")
    }
}
