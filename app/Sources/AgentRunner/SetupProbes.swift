import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-setup`, `--probe-setup-fixtures` and `--probe-fda`: Setup's rows as text, judged on example states,
// and the Full Disk Access spot-check as this program reads it. See SetupItems.swift.

private func printRows(_ items: [SetupItem]) {
    for tab in SetupTab.allCases {
        print("\n[\(tab.title)]  \(SetupItems.needing(items, in: tab)) need you")
        for item in SetupItems.items(items, in: tab) {
            let action = item.actionTitle.map { "  [\($0)]" } ?? ""
            let kind = item.needsYou ? "problem" : item.state.needsPerson ? "choice " : "       "
            print("  \(item.state.label.padding(toLength: 27, withPad: " ", startingAt: 0)) \(kind) \(item.title): \(item.evidence)\(action)")
        }
    }
}

/// The rows, read live. Notifications can't be asked without an app bundle; the rest are real reads.
@MainActor func probeSetupLive() async -> Never {
    let inputs = await SetupInputs.read()
    let items = SetupItems.build(inputs)
    print("version: \(BuildInfo.current.versionText)")
    print("engine: root \(AnalyzersPaths.suiteRoot.path)  bundled: \(AnalyzersPaths.usingBundledEngine)")
    print(SetupItems.subtitle(items))
    printRows(items)
    exit(items.contains { $0.needsYou } ? 1 : 0)
}

/// What `agent-runner` itself can read of the protected folders: one line per place, `id outcome [errno]`.
func probeFullDiskAccess() -> Never {
    let results = FullDiskAccessProbe.check()
    print("place outcome")
    for place in ProtectedPlaces.all {
        switch results[place.id] ?? .missing {
        case .readable: print("\(place.id) readable")
        case .denied: print("\(place.id) denied 1")
        case .missing: print("\(place.id) missing")
        case .other(let code): print("\(place.id) other \(code)")
        }
    }
    exit(0)
}

/// Judges the rows on every example state. Exit 1 when a rule breaks.
func probeSetupFixtures() -> Never {
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "PASS  " : "FAIL  ") + name + (detail.isEmpty ? "" : ": " + detail))
        if !ok { failures += 1 }
    }
    func rows(_ name: String) -> [SetupItem] { SetupItems.build(SetupFixtures.inputs(name)) }
    func item(_ id: String, _ name: String) -> SetupItem? { rows(name).first { $0.id == id } }

    for name in SetupFixtures.names {
        let items = rows(name)
        print("\n== \(name): \(SetupItems.subtitle(items))")
        printRows(items)
        print("")
        // every row is a read, except the one remembered flag that is pending removal
        let remembered = items.filter { !$0.source.isRead }
        check("\(name): every row's state is read, not remembered (but Automation, pending removal)",
              remembered.allSatisfy { $0.id == "automation" && $0.source == .remembered(pendingRemoval: true) }, remembered.map(\.id).joined(separator: ", "))
        // one row per thing, one action at most, and a button only with an action
        check("\(name): ids are unique, and a title goes with an action", Set(items.map(\.id)).count == items.count
              && items.allSatisfy { ($0.actionTitle == nil) == ($0.action == nil) })
        // the rows that need the person come first in each tab
        check("\(name): in each tab the rows that need you come first", SetupTab.allCases.allSatisfy { tab in
            // problems, then the choices still open, then what is On or can't be told
            let tiers = SetupItems.items(items, in: tab).map { $0.needsYou ? 0 : $0.state.needsPerson ? 1 : 2 }
            return tiers == tiers.sorted()
        })
        check("\(name): the three tabs are all there and hold rows", SetupTab.allCases.allSatisfy { !SetupItems.items(items, in: $0).isEmpty })
        // the subtitle counts the rows that need you
        let needing = items.filter(\.needsYou).count
        check("\(name): the subtitle says how many need you",
              SetupItems.subtitle(items) == (needing == 0 ? "Everything is set up" : needing == 1 ? "1 thing needs you" : "\(needing) things need you"))
        // a row that only System Settings can change hands you there; Time Machine and the rest are not a hand-off
        for row in items { if case .openSettings(let pane)? = row.action { check("\(name): \(row.id) hands off to \(pane.rawValue)", pane.link.hasPrefix("x-apple.systempreferences:") && !pane.path.isEmpty) } }
    }

    check("all on: nothing needs you", rows("allOn").allSatisfy { !$0.needsYou && !$0.state.needsPerson })
    check("all off: the guard is Needs You and every cleaner Off", item("job.\(EngineStatus.guardLabel)", "allOff")?.state == .needsYou
          && EngineStatus.cleanerLabels.allSatisfy { item("job.\($0)", "allOff")?.state == .off })
    // only real problems count: an optional permission or a list left empty is a choice, not a thing that needs you
    let problems = Set(rows("allOff").filter(\.needsYou).map(\.id))
    let cleaners = EngineStatus.cleanerLabels.map { "job.\($0)" }
    let expected = Set(["notifications", "fullDiskAccess", "cap", "job.\(EngineStatus.guardLabel)"] + cleaners)
    check("all off: only the real problems are counted (not Time Machine, login, the lists, recording folders, the settings file)",
          problems == expected, "counted: \(problems.sorted())")
    check("all off: the subtitle counts exactly those", SetupItems.subtitle(rows("allOff")) == "\(expected.count) things need you")
    check("choices stay in view but are not counted: Time Machine, login, Never Close, Recording Folders",
          ["timeMachine", "login", "neverClose", "mayQuit", "recordings", "config"].allSatisfy { id in
              item(id, "allOff").map { !$0.needsYou && $0.state.needsPerson && $0.weight == .choice } ?? false })
    check("the tab badges count the same problems", SetupTab.allCases.map { SetupItems.needing(rows("allOff"), in: $0) } == [2, 4, 1],
          "\(SetupTab.allCases.map { SetupItems.needing(rows("allOff"), in: $0) })")
    check("a login item waiting for approval is a problem, not a choice", item("login", "waiting")?.needsYou == true)
    check("recording folders that need macOS's permission are a problem", item("recordings", "waiting")?.needsYou == true)
    check("no background report yet: Full Disk Access says so and never guesses", item("fullDiskAccess", "noReport")?.state == .cantTell
          && item("fullDiskAccess", "noReport")?.evidence.contains("haven't reported yet") == true)
    check("all off: Full Disk Access is Off, with the folders named", item("fullDiskAccess", "allOff")?.state == .off
          && item("fullDiskAccess", "allOff")?.evidence.contains("Mail") == true)
    check("all off: notifications are Not Asked Yet with the one prompt", item("notifications", "allOff")?.state == .notAskedYet
          && item("notifications", "allOff")?.action == .allowNotifications)
    check("all off: the memory limit is Needs You with the suggestion", item("cap", "allOff")?.state == .needsYou
          && item("cap", "allOff")?.action == .setMemoryCap(SetupItems.suggestedCapMB(installedMB: 32 * 1024)))
    check("waiting: the login item is Needs You and opens its pane", item("login", "waiting")?.state == .needsYou
          && item("login", "waiting")?.action == .openSettings(.loginItems))
    check("waiting: Full Disk Access opens its pane", item("fullDiskAccess", "waiting")?.action == .openSettings(.fullDiskAccess))
    check("app only: Full Disk Access says only the app can see them", item("fullDiskAccess", "appOnly")?.state == .onlyApp)
    check("the Recording Folders row opens the Sources window", item("recordings", "allOn")?.action == .change("recordings:sources"))

    // Full Disk Access: the rule on stand-in readings (EPERM counts, anything else does not)
    let places = ProtectedPlaces.all
    func all(_ outcome: PlaceOutcome) -> [String: PlaceOutcome] { Dictionary(uniqueKeysWithValues: places.map { ($0.id, outcome) }) }
    check("Full Disk Access: every place readable by both is On, saying when the jobs checked",
          FullDiskAccessProbe.verdict(app: all(.readable), agent: all(.readable), agentChecked: Date()).state == .on
          && FullDiskAccessProbe.verdict(app: all(.readable), agent: all(.readable), agentChecked: Date().addingTimeInterval(-7200)).evidence.contains("they checked"))
    check("Full Disk Access: readable here with no report from the jobs is Can't Tell, never On",
          FullDiskAccessProbe.verdict(app: all(.readable), agent: nil).state == .cantTell)
    check("Full Disk Access: denied for the app is Off", FullDiskAccessProbe.verdict(app: all(.denied), agent: nil).state == .off)
    check("Full Disk Access: readable here, denied for the jobs is Only the App Can See Them",
          FullDiskAccessProbe.verdict(app: all(.readable), agent: all(.denied)).state == .onlyApp)
    check("Full Disk Access: nothing exists on a fresh account, so Can't Tell", FullDiskAccessProbe.verdict(app: all(.missing), agent: nil).state == .cantTell)
    check("Full Disk Access: EACCES is not counted as a missing permission", FullDiskAccessProbe.verdict(app: all(.other(13)), agent: nil).state != .off)
    var mixed = all(.readable); mixed[places[0].id] = .denied
    check("Full Disk Access: one place denied is Off, naming it", FullDiskAccessProbe.verdict(app: mixed, agent: nil).state == .off
          && FullDiskAccessProbe.verdict(app: mixed, agent: nil).evidence.contains(places[0].name))
    // the spot-check's own reader maps errors the same way: a folder that is there, one that is not
    let here = FullDiskAccessProbe.read(ProbeScratch.folder("ma-probe-setup").path), gone = FullDiskAccessProbe.read("/no/such/folder/anywhere")
    check("the reader: a folder it can open is readable, a missing one is missing", here == .readable && gone == .missing, "\(here) \(gone)")
    check("the list never reads the permission database folder, or another app's container (which can raise a prompt)",
          !places.contains { $0.path.contains("com.apple.TCC") || $0.path.contains("Library/Containers") || $0.path.contains("Group Containers") })
    // what the background jobs write, and what Setup reads back (a scratch file: nothing of the person's)
    let reportFile = ProbeScratch.folder("ma-probe-background").appending(path: "background-access.json")
    check("no report file yet: nothing is read", BackgroundAccess.read(at: reportFile) == nil)
    let written = Date(timeIntervalSince1970: 1_800_000_000)
    BackgroundAccess.record(to: reportFile, now: written, outcomes: ["mail": .denied, "safari": .readable, "messages": .missing])
    let back = BackgroundAccess.read(at: reportFile)
    check("a job's report comes back with its time and each place's outcome", back?.checked == written && back?.places["mail"] == .denied
          && back?.places["safari"] == .readable && back?.places["messages"] == .missing, "\(String(describing: back))")
    // due only when the answer on disk is old: a restarted guard does not write it again and again
    BackgroundAccess.recordIfDue(to: reportFile, minimumAge: 3600, now: Date(), outcomes: { ["mail": .readable] })
    check("a second start within the interval writes nothing", BackgroundAccess.read(at: reportFile)?.places["mail"] == .denied)
    // time-boxed: a read that stalls never holds the job up
    let slowFile = ProbeScratch.folder("ma-probe-background-slow").appending(path: "background-access.json")
    let began = Date()
    BackgroundAccess.recordIfDue(to: slowFile, minimumAge: 0, timeout: 0.3, outcomes: { Thread.sleep(forTimeInterval: 3); return ["mail": .readable] })
    check("a stalled read lets the job start after the time box", Date().timeIntervalSince(began) < 1.5, "\(Date().timeIntervalSince(began)) s")
    try? "not json".write(to: reportFile, atomically: true, encoding: .utf8)
    check("a damaged report is no report", BackgroundAccess.read(at: reportFile) == nil)
    // the hand-off panes
    check("every pane names the exact path and what to switch on", [SetupPane.fullDiskAccess, .notifications, .loginItems, .automation].allSatisfy {
        $0.path.contains("›") && !$0.instruction.isEmpty && $0.link.hasPrefix("x-apple.systempreferences:com.apple.")
    })
    check("only Full Disk Access offers the app's icon to drag in", SetupPane.fullDiskAccess.offersDrag && !SetupPane.notifications.offersDrag)

    print(failures == 0 ? "\nPASS  every check holds" : "\n\(failures) checks FAILED")
    ProbeScratch.finish(failures == 0 ? 0 : 1)
}
