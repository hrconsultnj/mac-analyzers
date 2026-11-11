// outline-probe — drives the shared `OutlineTable` headless, through the same
// public AppKit API a person's clicks end in, and prints what it finds.
//
//   snapshot-runner --outline-probe <action> [--rows P,K] [--levels N] [--hosted] [--seconds N]
//
// The window is never on a display: activation policy `prohibited`, alpha 0,
// ignoring the mouse, parked far away, shown with `orderBack` (never activated,
// never key). `scripts/outline-probe.sh` runs each action in a fresh process
// with `OS_ACTIVITY_DT_MODE=YES` and counts "reentrant operation" lines between
// the `@@MARK begin <action>` and `@@MARK end <action>` lines this prints on
// stderr; the counting is the driver's, so nothing in the component reads an
// environment variable.
//
// Actions: the thirteen of A1 (appear, expand1, collapse1, expandAll,
// expandAllOption, values, addChild, removeChild, addParent, removeParent,
// resort, filter10, filterBack, select), `soak`, `perf`, `preserve`, `diff`,
// `ticks`, `autosave`, `remembered`, `a2:<case>`, `a11:<case>:<n>`, `render <fixture> <out.png>`, `review:<case>`.
import AppKit
import Foundation
import Observation
import SwiftUI
import UIComponents

struct ProbeOptions {
    var parents = 200
    var kids = 5
    var levels = 2
    var hosted = false
    var seconds = 120

    init(_ arguments: [String]) {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let rows = value("--rows")?.split(separator: ",").compactMap({ Int($0) }), rows.count == 2 {
            parents = rows[0]; kids = rows[1]
        }
        levels = Int(value("--levels") ?? "") ?? 2
        hosted = arguments.contains("--hosted")
        seconds = Int(value("--seconds") ?? "") ?? 120
    }
}

func say(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func mark(_ text: String) {
    FileHandle.standardError.write(Data("@@MARK \(text)\n".utf8))
}

func spin(_ seconds: Double) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

func now() -> Double { ProcessInfo.processInfo.systemUptime }

/// CPU time of this thread, in ms: what a step cost, whatever else the Mac is doing.
func cpuMilliseconds() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e6 }

/// Runs the loop in 1 ms slices until three in a row are idle; the wall time in ms.
func settle(maxSeconds: Double = 20) -> Double {
    let start = now()
    var idle = 0
    while idle < 3 && now() - start < maxSeconds {
        let slice = now()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001))
        if now() - slice < 0.003 { idle += 1 } else { idle = 0 }
    }
    return (now() - start - 0.003) * 1000
}

@MainActor
func findOutline(in view: NSView) -> NSOutlineView? {
    if let outline = view as? NSOutlineView { return outline }
    for sub in view.subviews { if let found = findOutline(in: sub) { return found } }
    return nil
}

final class ProbeWindow: NSWindow {
    override func constrainFrameRect(_ frame: NSRect, to screen: NSScreen?) -> NSRect { frame }
}

/// One table in one invisible window.
@MainActor
final class ProbeHarness {
    let window: ProbeWindow
    private(set) var outline: NSOutlineView!
    let appearMilliseconds: Double

    init<Content: View>(_ content: Content, size: NSSize = NSSize(width: 520, height: 500)) {
        let host = NSHostingController(rootView: content.frame(minWidth: 500, minHeight: 400))
        window = ProbeWindow(contentViewController: host)
        window.styleMask = [.titled, .resizable]
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -9000, y: -9000))
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        mark("setup-begin")
        window.orderBack(nil)
        appearMilliseconds = settle()
        mark("setup-end")
        outline = window.contentView.flatMap(findOutline(in:))
    }
}

@MainActor
enum OutlineProbe {
    static func run(_ arguments: [String]) -> Never {
        guard let action = arguments.first else {
            FileHandle.standardError.write(Data("usage: snapshot-runner --outline-probe <action> [--rows P,K] [--levels N] [--hosted] [--seconds N]\n".utf8))
            exit(2)
        }
        let options = ProbeOptions(Array(arguments.dropFirst()))
        ProbeDefaults.removeOwn()          // a crashed earlier process may have had this pid
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let code: Int32
        switch action {
        case "soak": code = ProbeActions.soak(options)
        case "perf": code = ProbePerf.run(options)
        case "preserve": code = ProbeChecks.preserve(options)
        case "diff": code = ProbeChecks.diff()
        case "ticks": code = ProbeChecks.ticks()
        case "autosave": code = ProbeChecks.autosave()
        case "remembered": code = ProbeChecks.remembered()
        case "render": code = ProbeRender.run(Array(arguments.dropFirst()))
        case _ where action.hasPrefix("a2:"): code = ProbeChecks.a2(String(action.dropFirst(3)), options)
        case _ where action.hasPrefix("review:"): code = ProbeReview.run(String(action.dropFirst(7)))
        case "fit": code = ProbeFit.run()
        case _ where action.hasPrefix("monitor:"): code = ProbeMonitor.run(String(action.dropFirst(8)), options)
        case _ where action.hasPrefix("toolbar:"): code = ProbeToolbar.run(String(action.dropFirst(8)), Array(arguments.dropFirst()))
        case _ where action.hasPrefix("a11:"): code = ProbeFlat.run(String(action.dropFirst(4)))
        default: code = ProbeActions.single(action, options)
        }
        ProbeDefaults.removeOwn()          // what this process saved does not outlive it
        exit(code)
    }
}

/// Every probe saves table state (column sizes, open groups) under a name that carries its own process
/// id, and removes only keys carrying that id. Probes can therefore run side by side. This tool's
/// defaults are its own domain, never the app's, and no key without this pid in it is touched.
enum ProbeDefaults {
    static func removeOwn() {
        let pid = String(getpid())
        for key in UserDefaults.standard.dictionaryRepresentation().keys where carriesPID(key, pid) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// `.<pid>` or `-<pid>` followed by the end, a dot, a dash or a space: "probe-123", "probe.ticks.123.sections",
    /// never "probe-1234".
    private static func carriesPID(_ key: String, _ pid: String) -> Bool {
        for marker in [".", "-"] {
            var from = key.startIndex
            while let found = key.range(of: marker + pid, range: from..<key.endIndex) {
                let next = found.upperBound
                if next == key.endIndex || ".- ".contains(key[next]) { return true }
                from = found.upperBound
            }
        }
        return false
    }
}
