import Foundation
import AnalyzersKit

/// What the ACP engines need on this Mac, found the same way a shell finds
/// it: `PATH` search for the adapter's Node runtime and the vendor binaries,
/// `--version` probes for the cards' labels. Nothing here installs anything —
/// the install affordances on the Agents screen run the vendors' own official
/// commands in a visible Terminal window, after the screen states what will
/// run. Sparehold never bundles or silently installs another vendor's binary.
public enum EngineInstall: Sendable {

    /// The absolute path of an executable name, or nil. The lookup walks the
    /// SAME `PATH` the scheduled engine runs get (`EngineProcess.enginePath`),
    /// so a binary the terminals see, the agent sees too — and the app never
    /// reads the environment itself (the env check's allowlist is
    /// AgentRunner/SnapshotRunner/EngineProcess/Paths).
    public static func locate(_ name: String) -> String? {
        let path = EngineProcess.enginePath(home: AnalyzersPaths.home.path)
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// `<binary> --version`, first line, or nil — the card's version label.
    public static func version(ofBinary name: String) -> String? {
        guard let path = locate(name) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return text.components(separatedBy: .newlines).first
        } catch {
            return nil
        }
    }

    /// One engine's install state, as the Agents screen shows it.
    public struct Detection: Equatable, Sendable {
        public let binaryName: String
        public let binaryPath: String?
        public let version: String?
        public let nodePresent: Bool
        public let npxPath: String?

        /// Ready to run through its ACP adapter.
        public var isReady: Bool { binaryPath != nil && npxPath != nil }
        /// The one-line why, when it is not ready.
        public var notReadySentence: String? {
            if binaryPath == nil, !nodePresent {
                return "Needs Node.js (nodejs.org) and the \(binaryName) CLI — neither is on PATH yet."
            }
            if binaryPath == nil {
                return "The \(binaryName) CLI is not on PATH. Install it with the button above; sign-in happens in \(binaryName), never here."
            }
            if npxPath == nil {
                return "Needs Node.js and npx to run the ACP adapter (nodejs.org)."
            }
            return nil
        }
    }

    public static func detect(vendorBinary: String) -> Detection {
        Detection(
            binaryName: vendorBinary,
            binaryPath: locate(vendorBinary),
            version: version(ofBinary: vendorBinary),
            nodePresent: locate("node") != nil,
            npxPath: locate("npx"))
    }

    /// The official install command a card offers to run in Terminal — the
    /// vendors' own documented commands, stated before anything runs.
    public static func officialInstallCommand(forBinary name: String) -> String {
        switch name {
        case "claude": "npm install -g @anthropic-ai/claude-code"
        case "codex": "npm install -g @openai/codex"
        default: "npm install -g \(name)"
        }
    }
}
