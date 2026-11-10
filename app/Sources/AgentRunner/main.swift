// agent-runner — the compiled launchd entry point for the bash engine.
//
// Exists because Background Task Management refuses to attribute a background
// item whose ProgramArguments[0] is a bare shell script (no Team ID to hold
// responsible — DTS-confirmed; see tasks-plans/research/login-items-btm-*).
// The installed plists point HERE (inside the app bundle, sharing the app's
// signing identity), and this binary immediately BECOMES the engine script
// via execv — the engine stays bash, only the doorway is compiled.
import Foundation
import AnalyzersKit

let args = Array(CommandLine.arguments.dropFirst())

// `agent-runner --probe-setup` prints the same checklist the Setup screen
// shows, as plain text. Support can ask for its output, and it is the only
// way to see the verdicts on a Mac you cannot click through.
if args.first == "--probe-setup" {
    let engine = EngineStatus.probe()
    let report = SetupAudit.probe(
        notifications: SetupCheck(id: "notifications", title: "Alerts",
                                  why: "", verdict: .unset,
                                  detail: "not queryable outside the app"),
        loginItem: SetupCheck(id: "login", title: "Opens at login",
                              why: "", verdict: .unset,
                              detail: "not queryable outside the app"))
    print("engine: \(engine.summary)  root: \(AnalyzersPaths.suiteRoot.path)")
    print("bundled: \(AnalyzersPaths.usingBundledEngine)")
    for check in report.checks {
        let mark: String
        switch check.verdict {
        case .ready: mark = "OK   "
        case .blocking: mark = "BLOCK"
        case .degraded: mark = "WARN "
        case .unset: mark = "-    "
        }
        print("\(mark) \(check.title): \(check.detail)")
    }
    print("\(report.ready)/\(report.total) ready · usable: \(report.isUsable)")
    exit(report.isUsable ? 0 : 1)
}

// `agent-runner --probe-memory [--all]` prints the Monitor pane's full
// memory census as text: where physical memory is, then every process group
// with its total. Same numbers the pane shows; `--all` lists every group
// instead of the 40 largest.
if args.first == "--probe-memory" {
    let census = MemoryCensus.take()
    if let memory = census.breakdown {
        print("in use \(MemorySize.text(memory.usedBytes)) of \(MemorySize.text(memory.totalBytes))"
              + "  =  app \(MemorySize.text(memory.appBytes))"
              + " + wired \(MemorySize.text(memory.wiredBytes))"
              + " + compressed \(MemorySize.text(memory.compressedBytes))"
              + " (holding \(MemorySize.text(memory.compressedOriginalBytes)))")
        print("cached files \(MemorySize.text(memory.cachedBytes))"
              + " · free \(MemorySize.text(memory.freeBytes))")
    }
    print("\(census.processCount) processes in \(census.groups.count) groups hold"
          + " \(MemorySize.text(census.totalBytes))"
          + " · \(census.unmeasuredCount) could not be measured")
    for category in CensusGroup.Category.allCases {
        let groups = census.groups(in: category)
        print("\n\(category.title): \(MemorySize.text(census.totalBytes(in: category)))"
              + " · \(census.processCount(in: category)) processes · \(groups.count) groups")
        let shown = args.contains("--all") ? groups : Array(groups.prefix(40))
        for group in shown {
            let size = MemorySize.text(group.totalBytes)
            let pad = String(repeating: " ", count: max(0, 9 - size.count))
            print("  \(pad)\(size)  ×\(group.members.count)  \(group.name)"
                  + ((group.partsSummary ?? group.role).map { "  — \($0)" } ?? ""))
        }
        if shown.count < groups.count {
            let rest = groups.dropFirst(shown.count)
            print("  … \(rest.count) smaller groups hold"
                  + " \(MemorySize.text(rest.reduce(0) { $0 + $1.totalBytes }))")
        }
    }
    exit(0)
}

guard let script = args.first,
      FileManager.default.isExecutableFile(atPath: script) else {
    FileHandle.standardError.write(
        Data("usage: agent-runner /absolute/path/engine-script.sh [args…]\n".utf8))
    exit(2)
}
var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
cArgs.append(nil)
execv(script, &cArgs)   // the kernel honors the script's shebang
perror("agent-runner execv")
exit(1)
