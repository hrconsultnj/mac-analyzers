// snapshot-runner — render a real screen of the app to a PNG without ever
// putting a window in front of anyone.
//
//   snapshot-runner <target> <out.png> [--size 1100x720] [--wait 3] [--fake-running|--fake-failed|--fake-review] [--scroll-end] [--update-state uptodate|dev|available]
//   snapshot-runner overview /tmp/overview.png
//
// <target> is any deep-link target the app understands (`monitor`, `caches`,
// `log:forensics`, …). The real main window is built with the real data
// stores, placed far outside every display, navigated to the target, given
// time to load, and captured — toolbar, sidebar and all.
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
// available) without asking the network.
//
// Why it exists: a screen can compile, pass every check and still be a list
// of file names nobody would use. The people and agents building screens
// need to LOOK at them, and looking must not mean taking over the owner's
// Mac. This process never activates, never appears in the Dock, and its
// window is never on a display.
import AppKit
import SwiftUI
@_spi(TestSupport) import AnalyzersKit
import SettingsFeature

let arguments = Array(CommandLine.arguments.dropFirst())
// `--outline-probe <action> …` drives the shared OutlineTable headless (OutlineProbe.swift); it never renders a screen
if arguments.first == "--outline-probe" { OutlineProbe.run(Array(arguments.dropFirst())) }
// the example screens (`review:fixture`) can be linked only in this process
await MainActor.run { DeepLinkRouter.installFixtures() }
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: snapshot-runner <target> <out.png> [--size WxH] [--wait seconds] [--fake-running|--fake-failed|--fake-review] [--scroll-end] [--update-state uptodate|dev|available]\n".utf8))
    exit(2)
}
var target = arguments[0]
let output = URL(fileURLWithPath: arguments[1])

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}
let sizeParts = (option("--size") ?? "1100x720").split(separator: "x").compactMap { Double($0) }
let size = NSSize(width: sizeParts.first ?? 1100, height: sizeParts.count > 1 ? sizeParts[1] : 720)
let wait = Double(option("--wait") ?? "3") ?? 3
let fakeRunning = arguments.contains("--fake-running")
let fakeFailed = arguments.contains("--fake-failed")
let fakeReview = arguments.contains("--fake-review")
let scrollToEnd = arguments.contains("--scroll-end")
/// `--update-state uptodate|dev|available`: which state the sidebar's version item shows
/// (the network is not asked), to render every state of it.
let updateStateOption = option("--update-state")

@MainActor
final class Snapshot: NSObject, NSApplicationDelegate {
    var window: NSWindow!
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
            let forced = UpdateState(installed: version,
                                     build: BuildInfo(release: version, commitsAfter: preset.commits, localChanges: false))
            forced.preset(latest: preset.latest)
            return forced
        }
        let parts = git(["describe", "--tags", "--long", "--match", "v[0-9]*"]).split(separator: "-")
        let ahead = parts.count >= 3 ? Int(parts[parts.count - 2]) : nil
        return UpdateState(installed: version,
                           build: BuildInfo(release: version, commitsAfter: ahead,
                                            localChanges: !git(["status", "--porcelain"]).isEmpty))
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        // A snapshot must never run the real engine, whatever screen it opens: a
        // screen that starts a job when it appears (Network, with no snapshot yet)
        // would otherwise write the owner's logs. Every job this store runs is a
        // script that does nothing; `--fake-*` swaps in the throwaway ones.
        let nothing = scratch.appending(path: "no-op-engine.sh")
        try? "#!/bin/bash\nexit 0\n".write(to: nothing, atomically: true, encoding: .utf8)
        chmod(nothing.path, 0o755)
        jobs.scriptOverride = nothing
        if fakeRunning || fakeFailed || fakeReview { startFakeJobs() }
        if updateStateOption == nil { Task { await updates.check() } }
        let root = MainWindowView(restoresLocation: false)
            .environment(store)
            .environment(config)
            .environment(jobs)
            .environment(updates)
        let controller = NSHostingController(rootView: root)
        controller.sceneBridgingOptions = [.toolbars, .title]   // SwiftUI toolbars become the window's

        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.contentViewController = controller
        window.toolbarStyle = .unified
        window.setContentSize(size)
        // far outside every display: drawn by the window server, seen by nobody
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFrontRegardless()      // shows the window WITHOUT activating the app

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NotificationCenter.default.post(name: NotifyChannel.openPaneInternal, object: nil,
                                            userInfo: ["target": target])
        }
        if scrollToEnd {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + wait - 1) { self.scrollLongestToEnd() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + wait) { self.capture() }
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

    private func finish(_ code: Int32) -> Never {
        // stop the throwaway jobs and give their process trees a moment to go
        for job in jobs.jobs { job.cancel() }
        Thread.sleep(forTimeInterval: fakeRunning ? 1.5 : 0)
        try? FileManager.default.removeItem(at: scratch)
        exit(code)
    }

    /// The tallest scroll view in the window, taken to its last row.
    private func scrollLongestToEnd() {
        var best: NSScrollView?
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.frame.height > scroll.contentView.bounds.height,
               document.frame.height > (best?.documentView?.frame.height ?? 0) {
                best = scroll
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
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.path]
        do {
            try capture.run()
            capture.waitUntilExit()
        } catch {
            FileHandle.standardError.write(Data("snapshot-runner: could not run screencapture: \(error)\n".utf8))
            finish(1)
        }
        let made = FileManager.default.fileExists(atPath: output.path)
        print(made ? "\(target) → \(output.path)  (window title: \(window.title))"
                   : "snapshot-runner: nothing was captured for \(target)")
        finish(made ? 0 : 1)
    }
}

let app = NSApplication.shared
let delegate = Snapshot()
app.delegate = delegate
app.setActivationPolicy(.accessory)        // no Dock icon, never frontmost
app.run()
