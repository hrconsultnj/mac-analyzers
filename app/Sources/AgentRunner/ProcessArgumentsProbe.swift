import Foundation
import AnalyzersKit

// `agent-runner --probe-procargs` proves a process's arguments are read without
// its environment, and that what is shown never carries a credential's value.
// The kernel hands back one buffer: argc, the executable's path, the arguments,
// then the environment. Stand-in buffers cover the shapes that matter; a live
// case starts a throwaway program that rewrites its own title, the way
// `next-server` does, with a marker in its environment.

private func buffer(argc: Int32, path: String, padding: Int, _ pieces: [[UInt8]]) -> [UInt8] {
    var bytes = withUnsafeBytes(of: argc) { Array($0) }
    bytes += Array(path.utf8) + [0] + [UInt8](repeating: 0, count: padding)
    for piece in pieces { bytes += piece }
    return bytes
}
private func string(_ text: String) -> [UInt8] { Array(text.utf8) + [0] }
private func zeros(_ count: Int) -> [UInt8] { [UInt8](repeating: 0, count: count) }
private func parse(_ bytes: [UInt8]) -> [String] { bytes.withUnsafeBytes { ProcessArguments.parse($0) } }

func probeProcessArguments() -> Never {
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }
    let environment = [string("MA_PROBE_API_KEY=do-not-show-this"), string("HOME=/Users/example")]

    let plain = parse(buffer(argc: 3, path: "/usr/bin/tool", padding: 3,
                             [string("tool"), string("--port"), string("3000")] + environment))
    check("three arguments, then the environment: the three arguments", plain == ["tool", "--port", "3000"], "\(plain)")

    // a program that set its title: the title, then NULs where its other six arguments were
    let retitled = parse(buffer(argc: 7, path: "/usr/local/bin/node", padding: 1,
                                [string("next-server (v16.3.1)"), zeros(40)] + environment))
    check("a rewritten title with its other arguments blanked: the title alone",
          retitled == ["next-server (v16.3.1)"], "\(retitled)")
    check("…and nothing from the environment", !retitled.joined(separator: " ").contains("="))

    let empty = parse(buffer(argc: 3, path: "/bin/sh", padding: 0, [string("sh"), string(""), string("-c")] + environment))
    check("an empty argument is counted, not skipped", empty == ["sh", "-c"], "\(empty)")

    let cut = parse(buffer(argc: 9, path: "/bin/x", padding: 0, [string("x"), Array("half".utf8)]))
    check("a buffer that ends mid-argument: what is there, no crash", cut == ["x", "half"], "\(cut)")
    check("no arguments at all: nothing", parse(buffer(argc: 0, path: "/bin/x", padding: 0, [])).isEmpty)
    check("a buffer too short to hold a count: nothing", parse([1, 0]).isEmpty)

    // what is shown
    func shown(_ line: String) -> String { CommandLineDisplay.redacted(line) }
    func same(_ name: String, _ line: String, _ want: String) { check(name, shown(line) == want, shown(line)) }
    same("NAME=value after the program: the name only", "env SERVICE_API_KEY=value123", "env SERVICE_API_KEY=…")
    same("…whatever its name is", "node server.js NODE_ENV=production", "node server.js NODE_ENV=…")
    same("…and the rest of a value that has spaces", "title TERM_PROGRAM=My Terminal App HOME=/Users/example",
         "title TERM_PROGRAM=… HOME=…")
    same("the program's own name is never treated as NAME=value", "a=b.app --verbose", "a=b.app --verbose")
    same("--flag=value with a credential's name", "tool --auth-token=abc --port=3000", "tool --auth-token=… --port=3000")
    same("--flag value with a credential's name", "tool --password hunter2 --verbose", "tool --password … --verbose")
    same("a flag with no value is left alone", "tool --token --verbose", "tool --token --verbose")
    same("a password inside a web address", "git clone https://deploy:hunter2@example.com/repo.git",
         "git clone https://deploy:…@example.com/repo.git")
    same("an ordinary command line is unchanged", "node server.js --port 3000 ./public", "node server.js --port 3000 ./public")
    same("redacting twice changes nothing", shown("env A_TOKEN=x y --password p https://u:p@h/x"), shown("env A_TOKEN=x y --password p https://u:p@h/x"))
    // redacted first, then cut: a password whose "@" falls past the cut is still hidden
    let long = "git clone https://deploy:" + String(repeating: "p", count: 90) + "@example.com/repo.git"
    let row = CommandLineDisplay.shown(long)
    check("a row is redacted before it is cut", row.count <= 100 && !row.contains("ppp"), "\(row.count) characters")
    check("a display name is redacted where it is made",
          LiveProcess(pid: 1, residentMB: 1, rawName: "x SECRET_TOKEN=abc", kind: .app).rawName == "x SECRET_TOKEN=…")

    // live: programs that rewrite their title, started with an environment of exactly two
    // entries, a plainly named one and a credential-named one. On failure only counts and
    // names are printed, never the row's text: it could hold real environment values.
    let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first { FileManager.default.isExecutableFile(atPath: $0) }
        ?? ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map { "\($0)/node" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    func describe(_ name: String) -> String {
        let names = name.split(separator: " ").compactMap { token -> String? in
            guard let equals = token.firstIndex(of: "="), equals != token.startIndex else { return nil }
            return String(token[..<equals])
        }
        return "\(name.count) characters, \(names.count) NAME= token(s)\(names.isEmpty ? "" : ": " + names.prefix(6).joined(separator: ", "))"
    }
    /// Starts node on a short script that sets its title (so the title's words are in no argument
    /// and the arguments are few and short), waits for the title to show, and returns the row's text.
    let scripts = ProbeScratch.folder("ma-pa")
    func rowOfRetitled(script name: String, titleExpression: String, startsWith prefix: String) -> String? {
        guard let node else { return nil }
        let script = scripts.appending(path: name)
        guard (try? "process.title=\(titleExpression); setTimeout(() => {}, 20000)".write(to: script, atomically: true, encoding: .utf8)) != nil
        else { return nil }
        // Started through `env -i` so the environment is exactly these two entries IN THIS ORDER,
        // the plainly named one first: a dictionary's order is random, and with the credential
        // entry first the plain one would be hidden as "the rest of a value" whatever the rule.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.currentDirectoryURL = scripts
        child.arguments = ["-i", "MA_PROBE_PLAIN=plain-value-do-not-show", "MA_PROBE_API_KEY=secret-value-do-not-show",
                           node, script.lastPathComponent, "a", "b", "c"]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        guard (try? child.run()) != nil else { return nil }
        var name = ""
        for _ in 0..<80 {                                   // at most 8 s
            name = LiveStats.process(pid: Int(child.processIdentifier))?.rawName ?? ""
            if name.hasPrefix(prefix) { break }
            usleep(100_000)
        }
        child.terminate()
        child.waitUntilExit()
        return name
    }
    func noValues(_ name: String) -> Bool { !name.contains("do-not-show") }

    if let short = rowOfRetitled(script: "s.js", titleExpression: "['ma','probe','title'].join('-')", startsWith: "ma-probe-title") {
        check("live: a program that set a short title shows that title and nothing else",
              short.trimmingCharacters(in: .whitespaces) == "ma-probe-title", describe(short))
        check("live: no value from its environment is shown", noValues(short), describe(short))
    } else {
        print("SKIP  live cases: no node on this Mac, or it could not be started (the stand-in buffers above cover the shapes)")
    }
    // a title longer than the original arguments: the kernel then yields environment entries as
    // arguments, to `ps` too. Their names may show; their values never.
    if let longTitle = rowOfRetitled(script: "l.js", titleExpression: "'ma-probe-long-'+'x'.repeat(200)", startsWith: "ma-probe-long-") {
        check("live: a title longer than its arguments still shows no value from the environment",
              noValues(longTitle), describe(longTitle))
        // whether this Mac really handed environment entries back as arguments (it does with
        // current Node; if it ever stops, the check above is trivially true and this says so)
        print("      that case \(longTitle.contains("MA_PROBE_") ? "was exercised: environment names reached the row, values did not" : "was NOT exercised on this Mac: no environment name reached the row")")
    }

    try? FileManager.default.removeItem(at: scripts)      // `exit` below runs no `defer`
    print(failures == 0 ? "all hold" : "\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
}
