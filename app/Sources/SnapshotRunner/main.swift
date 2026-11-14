// snapshot-runner — render a real screen of the app to a PNG without ever
// putting a window in front of anyone.
//
//   snapshot-runner <target> <out.png> [--size 1100x720] [--wait 3] [--fake-running|--fake-failed|--fake-review|--fake-pressure] [--sidebar shown|hidden|peek] [--toolbar-dump] [--escape] [--toggle-frames] [--scroll-end] [--scroll-sidebar] [--update-state uptodate|dev|available] [--appearance light|dark] [--view-tree] [--guard-log file] [--startup-inventory <file>] [--fake-running|--fake-failed|--fake-review] [--home <folder>] [--welcome <fresh|upgraded|continuing>:<step>]
//   snapshot-runner overview /tmp/overview.png
//
// <target> is any deep-link target the app understands (`monitor`, `caches`,
// `log:forensics`, …). The real main window is built with the real data
// stores, in an OffscreenWindow far outside every display (a render refuses to
// capture, and says why, when the window touches one), navigated to the target, given
// time to load, and drawn into a PNG from the window's own views (OffscreenWindow.snapshotPNG) —
// toolbar, sidebar and all; a window on no display cannot be imaged by `screencapture`.
//
// The window gets the same environment the app gives it: the guard store, the
// settings, ONE job store and ONE update state. `--fake-running` starts two
// throwaway jobs (a test script, never the engine, and a job index in a
// temporary folder) so the screens that show a running job can be looked at;
// both are stopped before the process exits. Without them the store still has a
// no-op script override, so no screen can start the real engine from here. `--fake-failed` runs one job whose
// test script fails, for the failed states. A target written `job:@job` is
// rewritten to the first of these jobs' ids. `--scroll-end` scrolls the
// screen's longest scroll view to its end before capturing, to look at the
// bottom of a list that does not fit the window. `--update-state` picks the
// state of the sidebar's version item (up to date, development build, update
// available) without asking the network. `--appearance light|dark` sets the app's
// appearance before anything is drawn (the system's setting is used without it):
// the one way to render a screen in dark mode, so nobody patches a private flag in.
//
// Why it exists: a screen can compile, pass every check and still be a list
// of file names nobody would use. The people and agents building screens
// need to LOOK at them, and looking must not mean taking over the owner's
// Mac. This process never activates, never appears in the Dock, and its
// window is never on a display.
import AppKit
import ToolWindows
import UIComponents
import SwiftUI
@_spi(TestSupport) import AnalyzersKit
import SettingsFeature

let arguments = Array(CommandLine.arguments.dropFirst())
// `--outline-probe <action> …` drives the shared OutlineTable headless (OutlineProbe.swift); it never renders a screen
if arguments.first == "--outline-probe" { OutlineProbe.run(Array(arguments.dropFirst())) }
// `--probe-links`: every link that used to open an old Storage screen or the five-cleaner picker lands on a
// current screen (never on nothing, never on a view that no longer exists); exit 1 when one does not.
if arguments.first == "--probe-links" {
    let storage = ["actions:storageClean": "caches", "actions:janitor": "downloads", "actions:tempClean": "temp",
                   "log:storageClean": "caches", "log:janitor": "downloads", "log:tempSpace": "temp",
                   "log:spotlightAudit": "spotlight", "log:cleanupApps": "unused", "log:cleanupRecordings": "recordings",
                   "caches": "caches", "downloads": "downloads", "temp": "temp", "spotlight": "spotlight",
                   "unused": "unused", "recordings": "recordings", "disk": "disk",
                   "disk:capacity": "disk", "disk:caches": "caches", "disk:downloads": "downloads", "disk:temp": "temp",
                   "caches:projects": "caches", "caches:appCaches": "caches", "caches:developerTools": "caches"]
    var failures = 0
    for (target, section) in storage.sorted(by: { $0.key < $1.key }) {
        let landed = DeepLinkRouter.probeRouting(of: target)
        let ok = landed.contains("\"\(section)\"") && !landed.contains("unknown")
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(target) → \(section): \(landed.prefix(110))")
    }
    // every link Overview and the menu-bar panel send (Overview track): each must land on its screen
    let overview = ["disk:capacity": "disk", "caches:projects": "caches", "monitor": "monitor", "monitor:select:Opera": "monitor",
                    "trends": "trends", "trends:storage": "trends", "trends:memory": "trends", "undo": "undo",
                    "undo:servers": "undo", "undo:opened": "undo", "logs": "activity", "schedule": "prefsSchedule",
                    "update": "updates", "log:guardLog": "memoryGuard", "setup": "setup"]
    for (target, section) in overview.sorted(by: { $0.key < $1.key }) {
        let landed = DeepLinkRouter.probeRouting(of: target)
        let ok = landed.contains("\"\(section)\"") && !landed.contains("unknown")
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(target) → \(section): \(landed.prefix(110))")
    }
    for target in ["actions", "actions:memoryClean", "actions:reclaim"] {
        let landed = DeepLinkRouter.probeRouting(of: target)
        let ok = !landed.contains("unknown") && !landed.contains("storage")
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(target) → a Memory screen: \(landed.prefix(110))")
    }
    print(failures == 0 ? "\nno link reaches an old screen" : "\n\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
}
// A screen render starts from the target it was given, with nothing remembered from an earlier run
// (the saved location, the chosen tab, the opened groups): clear this tool's own defaults domain,
// never the app's. Only for a render: the probes above keep their own state per process, and
// wiping the whole domain under probes that run side by side broke them.
if let domain = Bundle.main.bundleIdentifier ?? Optional(ProcessInfo.processInfo.processName),
   domain != "com.mac-analyzers.app" {
    UserDefaults.standard.removePersistentDomain(forName: domain)
}
// the example screens (`review:fixture`) can be linked only in this process; this tool has no
// app bundle, so MA_CHANGELOG names the changelog What's New shows (read HERE, never by the app)
let changelog = ProcessInfo.processInfo.environment["MA_CHANGELOG"].map { URL(fileURLWithPath: $0) }
// the kinds a screen shows come from the checkout this tool was built from, not from whichever engine the person's
// own checkout holds: a render of work in progress must show that work's `kinds.json`
do {
    var checkout = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { checkout.deleteLastPathComponent() }
    let rules = checkout.appending(path: "memory-analyzer/rules/kinds.json")
    if FileManager.default.fileExists(atPath: rules.path) { KindCatalog.use(file: rules) }
}
// Called directly, never awaited: one `await` in this file's top-level code makes the whole of it
// an async task, and `NSApplication.run()` started inside a task never services the main dispatch
// queue, so the delayed capture below would never fire and the tool would sit there until killed
// (`scripts/check.sh snapshot` refuses a top-level await here). Top-level code is already on the
// main actor.
DeepLinkRouter.installFixtures(changelog: changelog)
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: snapshot-runner <target> <out.png> [--size WxH] [--wait seconds] [--fake-running|--fake-failed|--fake-review] [--scroll-end] [--update-state uptodate|dev|available] [--appearance light|dark]\n".utf8))
    exit(2)
}
var target = arguments[0]
let output = URL(fileURLWithPath: arguments[1])

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}
// `--home <folder>`: every path the app reads (reports, logs, ledgers) resolves under this folder instead of the account's
// home, so a screen can be looked at with a log of any size (a run of 6,000 items) without touching the real ones.
// Must come before anything asks for a path.
if let folder = option("--home") { AnalyzersPaths.useHome(URL(fileURLWithPath: folder)) }
// `--guard-log <file>`: show Memory Guard's history from this log instead of the real one.
if let log = option("--guard-log") { GuardHistory.useLog(at: URL(fileURLWithPath: log)) }
let sizeParts = (option("--size") ?? "1100x720").split(separator: "x").compactMap { Double($0) }
let size = NSSize(width: sizeParts.first ?? 1100, height: sizeParts.count > 1 ? sizeParts[1] : 720)
let wait = Double(option("--wait") ?? "3") ?? 3
let fakeRunning = arguments.contains("--fake-running")
let fakeFailed = arguments.contains("--fake-failed")
let fakeReview = arguments.contains("--fake-review")
/// `--fake-pressure`: the memory screens' history holds a stretch of warning and critical pressure (the Mac is at normal when it renders).
let fakePressure = arguments.contains("--fake-pressure")
/// `--hit-test-edge`: hit-test the content 4 points in from the window's leading edge (where the hover strip is) and
/// print what answers, so a control there is shown to still get the click; with `--sidebar hidden`.
let hitTestEdge = arguments.contains("--hit-test-edge")
/// `--toolbar-dump`: print each toolbar item's label and where its left edge is, in window points, so a button that must
/// not move between two states can be measured.
let toolbarDump = arguments.contains("--toolbar-dump")
/// `--escape`: just before the capture, send Escape through the application's event queue, so a render shows whether it puts the hover overlay away.
let sendEscape = arguments.contains("--escape")
/// `--toggle-frames`: record the window's frame, hide/show/hide the sidebar the way the menu item does, record it after each,
/// print them and exit 1 if the window changed size (a sidebar must show and hide INSIDE the window it is in).
let toggleFrames = arguments.contains("--toggle-frames")
/// `--sidebar shown|hidden|peek`: how the sidebar starts (peek is hidden with the hover overlay showing). Never remembered.
let sidebarState: SidebarPresentation = switch option("--sidebar") {
case "hidden": .hidden
case "peek": .peeking
default: .shown
}
/// `--then <target> [--then-at <seconds>]`: open a second target that long after launch (default 3 s), on the screen already
/// showing, as a link opened while a screen is open: how a period changed while its data is in view is rendered.
/// `--load-delay <seconds>`: reads of Trends and Memory Guard take that much longer, so the state while a new
/// period loads can be captured.
let thenTarget = option("--then")
let thenAt = Double(option("--then-at") ?? "3") ?? 3
let loadDelay = Double(option("--load-delay") ?? "0") ?? 0
let scrollToEnd = arguments.contains("--scroll-end")
/// `--scroll-sidebar`: scroll the sidebar (the narrowest scrollable view) to its last row.
let scrollSidebar = arguments.contains("--scroll-sidebar")
/// `--update-state uptodate|dev|available`: which state the sidebar's version item shows
/// (the network is not asked), to render every state of it.
let updateStateOption = option("--update-state")
/// `--appearance light|dark`: the app's appearance for this render. Anything else is refused.
let appearanceOption = option("--appearance")
if let appearanceOption, !["light", "dark"].contains(appearanceOption) {
    FileHandle.standardError.write(Data("snapshot-runner: --appearance takes light or dark, not \(appearanceOption)\n".utf8))
    exit(2)
}

@MainActor
final class Snapshot: NSObject, NSApplicationDelegate {
    var window: OffscreenWindow!
    let store = GuardLogStore()
    let config = ConfigStore()
    /// A job index in a temporary folder: a snapshot never writes the real one.
    let scratch = FileManager.default.temporaryDirectory
        .appending(path: "ma-snapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
    lazy var jobs = JobStore(ledger: JobLedger(url: scratch.appending(path: "app-jobs.jsonl")))
    /// This binary has no Info.plist, so the version a bundled app reads from its
    /// bundle comes from the repository's VERSION file here — the render then
    /// shows what the installed app would.
    let updates: UpdateState = {
        let version = (try? String(contentsOf: AnalyzersPaths.suiteRoot.appending(path: "VERSION"), encoding: .utf8))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "0"
        // the stamp build.sh would have written, read from git here instead
        func git(_ args: [String]) -> String {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", AnalyzersPaths.suiteRoot.path] + args
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return "" }
            let out = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let state = updateStateOption {
            let preset: (commits: Int, latest: String) = switch state {
            case "dev": (3, version)
            case "available": (0, "999.0.0")
            default: (0, version)
            }
            let forced = UpdateState(build: BuildInfo(release: version, commitsAfter: preset.commits, localChanges: false))
            forced.preset(latest: preset.latest)
            // the development channels: `beta-behind|beta-current|beta-ahead|beta-offline|copy-behind|copy-dirty|copy-current|copy-differs`
            let commit = String(repeating: "a", count: 40)
            let fixtures: [String: (UpdateChannel, ChannelState, String?, CloneFacts)] = [
                "beta-behind": (.beta, .behind(changes: 5, uncommitted: false), "9f3c2e1 · Show what each cleanup moved to the Trash",
                                CloneFacts(branch: "development", isDirty: false, fingerprint: "clean", relation: .same)),
                "beta-current": (.beta, .upToDate, nil, CloneFacts(branch: "development", isDirty: false, fingerprint: "clean", relation: .same)),
                "beta-ahead": (.beta, .ahead(Names.ChannelText.notOnGitHub), nil, CloneFacts(branch: "development", isDirty: true, fingerprint: "x", relation: .same)),
                "beta-offline": (.beta, .unknown(Names.ChannelText.offline), nil, CloneFacts(branch: "development", isDirty: false, fingerprint: "clean", relation: .same)),
                "copy-behind": (.thisCopy, .behind(changes: 3, uncommitted: true), nil, CloneFacts(branch: "feature/update-channels", isDirty: true, fingerprint: "x", relation: .cloneAhead(3))),
                "copy-dirty": (.thisCopy, .behind(changes: 0, uncommitted: true), nil, CloneFacts(branch: "development", isDirty: true, fingerprint: "x", relation: .same)),
                "copy-current": (.thisCopy, .upToDate, nil, CloneFacts(branch: "development", isDirty: false, fingerprint: "clean", relation: .same)),
                "copy-differs": (.thisCopy, .differs(Names.ChannelText.installHadChangesCloneLost), nil, CloneFacts(branch: "development", isDirty: false, fingerprint: "clean", relation: .same)),
            ]
            if let fixture = fixtures[state] {
                // a "current" state is one a clean build can be in; the others come from a build with changes
                let isCurrent = state == "beta-current" || state == "copy-current"
                let channelBuild = BuildInfo(release: version, commitsAfter: 3, localChanges: !isCurrent, commit: commit, branch: "development", treeHash: isCurrent ? "clean" : "x")
                let channelState = UpdateState(build: channelBuild)
                channelState.preset(latest: version)
                channelState.preset(channel: fixture.0, state: fixture.1, newest: fixture.2, cloneBranch: fixture.3.branch, facts: fixture.3)
                return channelState
            }
            return forced
        }
        let parts = git(["describe", "--tags", "--long", "--match", "v[0-9]*"]).split(separator: "-")
        let ahead = parts.count >= 3 ? Int(parts[parts.count - 2]) : nil
        return UpdateState(build: BuildInfo(release: version, commitsAfter: ahead,
                                            localChanges: !git(["status", "--porcelain"]).isEmpty))
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if fakePressure { MemoryTrend.shared.replace(with: Self.pressureHistory()) }
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        SnapshotScratch.arm(scratch)     // removed however this ends (a stop signal included)
        // A snapshot must never run the real engine, whatever screen it opens: a
        // screen that starts a job when it appears (Network, with no snapshot yet)
        // would otherwise write the owner's logs. Every job this store runs is a
        // script that does nothing; `--fake-*` swaps in the throwaway ones.
        let nothing = scratch.appending(path: "no-op-engine.sh")
        try? "#!/bin/bash\nexit 0\n".write(to: nothing, atomically: true, encoding: .utf8)
        chmod(nothing.path, 0o755)
        jobs.scriptOverride = nothing
        // `--startup-inventory <file>` shows Login & Startup Items from a fixture
        if let fixture = option("--startup-inventory") { StartupInventory.useFile(URL(fileURLWithPath: fixture)) }
        // the recording sources of the checkout this tool was built from: the person's own clone may be older
        var checkout = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { checkout.deleteLastPathComponent() }
        let sources = checkout.appending(path: "lib/recording-sources.tsv")
        if FileManager.default.fileExists(atPath: sources.path) { RecordingSourceCatalog.useList(at: sources) }
        if fakeRunning || fakeFailed || fakeReview { startFakeJobs() }
        if updateStateOption == nil { Task { await updates.check() } }
        // `--welcome <state:step>` (`fresh:3`) draws the Welcome window's own content at the size it has (use `--size 560x680`), not
        // the example inside the main window: the target is then only a placeholder
        let root: AnyView = option("--welcome").map { example in
            AnyView(WelcomeFlowView(fixture: example)
                .environment(store).environment(config).environment(jobs).environment(updates))
        } ?? AnyView(MainWindowView(restoresLocation: false, sidebar: sidebarState)
            .environment(store)
            .environment(config)
            .environment(jobs)
            .environment(updates))
        let controller = NSHostingController(rootView: root)
        controller.sceneBridgingOptions = [.toolbars, .title]   // SwiftUI toolbars become the window's

        window = OffscreenWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        // `--appearance light|dark` pins the window's appearance, whatever the system is set to
        if let look = option("--appearance") {
            window.appearance = NSAppearance(named: look == "light" ? .aqua : .darkAqua)
        }
        window.contentViewController = controller
        if let a = appearanceOption { window.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
        window.toolbarStyle = .unified
        window.setContentSize(size)
        // far outside every display: drawn by the window server, seen by nobody; `capture()` refuses to run
        // if the window is on one anyway
        window.placeOffscreen()      // shows the window WITHOUT activating the app

        if toggleFrames {
            let start = 0.8 + wait
            var frames: [(String, NSRect)] = []
            func record(_ name: String) { frames.append((name, window.frame)); print("frame \(name): \(window.frame)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + start) { record("start") }
            for (index, name) in ["after first toggle", "after second toggle", "after third toggle"].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + start + Double(index) * 1.5 + 0.3) {
                    NotificationCenter.default.post(name: NotifyChannel.toggleSidebarInternal, object: nil)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + start + Double(index) * 1.5 + 1.5) { record(name) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + start + 5.2) { [self] in
                let sizes = Set(frames.map { "\($0.1.size.width)x\($0.1.size.height)" })
                let origins = Set(frames.map { "\($0.1.origin.x),\($0.1.origin.y)" })
                let same = sizes.count == 1 && origins.count == 1
                print(same ? "PASS the window frame did not change" : "FAIL the window frame changed: sizes \(sizes), origins \(origins)")
                finish(same ? 0 : 1)
            }
        }
        if sendEscape {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + wait - 1.5) { [self] in
                let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                              charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)
                if let escape { NSApp.sendEvent(escape) }
            }
        }
        if toolbarDump {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + wait - 0.5) { [self] in
                for item in window.toolbar?.items ?? [] {
                    guard let view = item.view else { continue }
                    let frame = view.convert(view.bounds, to: nil)
                    print("toolbar item \(item.itemIdentifier.rawValue) label=\(item.label) x=\(Int(frame.minX)) width=\(Int(frame.width))")
                }
            }
        }
        if hitTestEdge {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + wait - 0.5) { [self] in
                guard let content = window.contentView else { return }
                for y in [content.bounds.height * 0.3, content.bounds.height * 0.5, content.bounds.height * 0.7] {
                    let point = content.convert(NSPoint(x: 4, y: y), to: content.superview)
                    var chain: [String] = []
                    var view = content.hitTest(point)
                    while let current = view, chain.count < 4 { chain.append(String(describing: type(of: current))); view = current.superview }
                    print("hit at x=4, y=\(Int(y)): \(chain.joined(separator: " <- "))")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NotificationCenter.default.post(name: NotifyChannel.openPaneInternal, object: nil,
                                            userInfo: ["target": target])
        }
        if loadDelay > 0 {
            // from the second target on: the first read is quick, the one a change starts is slow
            DispatchQueue.main.asyncAfter(deadline: .now() + thenAt - 0.2) {
                Task { await LoadCoordinator.shared.slowDown(prefixes: ["trends.", "guard.history"], by: loadDelay) }
            }
        }
        if let thenTarget {
            DispatchQueue.main.asyncAfter(deadline: .now() + thenAt) {
                NotificationCenter.default.post(name: NotifyChannel.openPaneInternal, object: nil,
                                                userInfo: ["target": thenTarget])
            }
        }
        if scrollToEnd {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + wait - 1) { self.scrollLongestToEnd() }
        }
        if scrollSidebar {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + wait - 1) { self.scrollLongestToEnd(leftmost: true) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + wait + (toggleFrames ? 8 : 0)) { self.capture() }
    }

    /// Throwaway jobs run by a test script: one running with one waiting behind
    /// it, or one that fails.
    private func startFakeJobs() {
        let script = scratch.appending(path: "fake-engine.sh")
        let body = fakeReview ? """
        #!/bin/bash
        echo "memory auto-clean  |  DRY RUN  |  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "### Helper processes whose app has closed"
        """ : fakeFailed ? """
        #!/bin/bash
        echo "memory auto-clean  |  DRY RUN  |  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "### Looking for helper processes whose app has closed"
        echo "the process table could not be read" >&2
        exit 3
        """ : """
        #!/bin/bash
        echo "memory auto-clean  |  DRY RUN  |  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "### Looking for helper processes whose app has closed"
        for i in $(seq 1 400); do echo "checked process $i of 400"; sleep 0.4; done
        """
        try? body.write(to: script, atomically: true, encoding: .utf8)
        chmod(script.path, 0o755)
        jobs.scriptOverride = script
        if fakeReview {
            // a fresh preview that found three processes, with its own block "found" in the log
            jobs.outcomeOverride = { _, header in
                let lines = ["### Helper processes whose app has closed",
                             "[DRY]   310 MB  pid=4242  orphan — next-server (no session or terminal in its project)",
                             "[DRY]   120 MB  pid=4243  orphan — chrome-headless-shell (parent gone)",
                             "[DRY]    64 MB  pid=4244  orphan — node (no parent)"]
                let banner = header ?? "memory auto-clean  |  DRY RUN"
                return JobOutcome(parsed: .reap(ReapParser.parse(runHeader: banner, lines: lines)),
                                  run: LogRun(id: 0, header: banner, lines: lines), match: .exact)
            }
        }
        let first = jobs.enqueue(JobRequest(kind: .memoryClean, intent: .preview), trigger: .user)
        if fakeRunning {
            jobs.enqueue(JobRequest(kind: .storageClean, intent: .preview, options: JobOptions(deep: true)), trigger: .user)
        }
        target = target.replacingOccurrences(of: "@job", with: first.id.uuidString)
    }

    /// Ninety seconds of history ending now at two-second steps: calm, then a warning stretch, a critical one, then calm again.
    private static func pressureHistory() -> [MemorySample] {
        guard let base = MemorySample.read(graphics: nil) else { return [] }
        let end = Date().addingTimeInterval(-2)
        return (0..<45).map { step in
            let level = step < 15 ? 1 : step < 27 ? 2 : step < 33 ? 4 : 1
            return MemorySample(date: end.addingTimeInterval(Double(step - 44) * 2), breakdown: base.breakdown,
                                swapUsedBytes: base.swapUsedBytes, swapTotalBytes: base.swapTotalBytes, pressureLevel: level,
                                pressurePercent: level == 1 ? 26 + (step % 5) * 2 : level == 2 ? 60 + (step % 6) * 3 : 90 + step % 4,
                                graphicsBytes: base.graphicsBytes, swapIns: base.swapIns, swapOuts: base.swapOuts,
                                compressions: base.compressions, decompressions: base.decompressions, pageSize: base.pageSize)
        }
    }

    private func finish(_ code: Int32) -> Never {
        // stop the throwaway jobs and give their process trees a moment to go
        for job in jobs.jobs { job.cancel() }
        Thread.sleep(forTimeInterval: fakeRunning ? 1.5 : 0)
        try? FileManager.default.removeItem(at: scratch)
        exit(code)
    }

    /// The tallest scroll view in the window, taken to its last row; with `leftmost` the narrowest (the sidebar).
    private func scrollLongestToEnd(leftmost: Bool = false) {
        var best: NSScrollView?
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.frame.height > scroll.contentView.bounds.height {
                if leftmost {
                    // the sidebar is the narrowest scroll view (the detail's spans the window, under it)
                    if scroll.frame.width < (best?.frame.width ?? .greatestFiniteMagnitude) { best = scroll }
                } else if document.frame.height > (best?.documentView?.frame.height ?? 0) {
                    best = scroll
                }
            }
            view.subviews.forEach(visit)
        }
        if let content = window.contentView { visit(content) }
        guard let scroll = best, let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let end = document.frame.height - clip.bounds.height + scroll.contentInsets.bottom
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: document.isFlipped ? end : -scroll.contentInsets.top))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func capture() {
        // the hard guard: a window on a display ends the run here, before anything is captured
        window.requireOffscreen(before: "capture \(target)")
        print("snapshot-runner: \(window.placementReport())")
        // drawn from the window's own views: a window parked on no display cannot be imaged by the window server
        // (`screencapture -l` says "could not create image from window"), and this needs no display at all
        if arguments.contains("--view-tree"), let frameView = window.contentView?.superview {
            func dump(_ view: NSView, _ depth: Int) {
                guard depth < 14 else { return }
                let f = view.frame
                print(String(repeating: "  ", count: depth) + "\(type(of: view)) (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)))\(view.isHidden ? " hidden" : "")\(view.wantsLayer ? " layer:\(type(of: view.layer!))" : "")")
                for sub in view.subviews { dump(sub, depth + 1) }
            }
            dump(frameView, 0)
        }
        do { try window.writeSnapshot(to: output) } catch {
            FileHandle.standardError.write(Data("snapshot-runner: no picture was made: \(error)\n".utf8))
            finish(1)
        }
        // the window cannot be smaller than the app's own minimum: say so instead of letting a
        // "760" render pass for 760
        let actual = window.contentView?.frame.size ?? size
        let clamped = abs(actual.width - size.width) > 1 || abs(actual.height - size.height) > 1
        if clamped {
            print("snapshot-runner: asked for \(Int(size.width))x\(Int(size.height)); the window's minimum made it \(Int(actual.width))x\(Int(actual.height))")
        }
        let made = FileManager.default.fileExists(atPath: output.path)
        print(made ? "\(target) → \(output.path)  (window title: \(window.title))"
                   : "snapshot-runner: nothing was captured for \(target)")
        finish(made ? 0 : 1)
    }
}

let app = NSApplication.shared
if let appearanceOption { app.appearance = NSAppearance(named: appearanceOption == "dark" ? .darkAqua : .aqua) }
let delegate = Snapshot()
app.delegate = delegate
app.setActivationPolicy(.accessory)        // no Dock icon, never frontmost
app.run()
