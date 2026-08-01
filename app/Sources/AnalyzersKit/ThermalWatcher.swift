import AppKit
import Foundation
import Observation
import os

/// Watches the OS thermal state (the signal behind "my Mac got slow for no
/// reason" — macOS throttles silently). On elevation it writes a receipt
/// with the top CPU users at that moment and hands the caller a
/// notification-ready summary; recovery is logged too.
@Observable
@MainActor
public final class ThermalWatcher {

    public private(set) var state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    /// Called on elevation to serious/critical: (title, message).
    private var onElevation: ((String, String) -> Void)?
    private var lastNotified: ProcessInfo.ThermalState = .nominal
    private var observer: NSObjectProtocol?

    public nonisolated static let logURL = AnalyzersPaths.suiteRoot
        .appending(path: "reports/thermal.log")

    /// One watcher, many surfaces — started once by the app delegate.
    public static let shared = ThermalWatcher()

    public init() {}

    public func start(onElevation: @escaping (String, String) -> Void) {
        self.onElevation = onElevation
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.stateChanged() }
        }
    }

    private func stateChanged() {
        let new = ProcessInfo.processInfo.thermalState
        let old = state
        state = new
        guard new != old else { return }

        let stamp = Self.timestamp()
        switch new {
        case .serious, .critical:
            let hogs = Self.topCPU()
            let label = new == .critical ? "CRITICAL" : "SERIOUS"
            appendLog("\(stamp) THROTTLE \(label) — macOS is slowing the CPU. Top: \(hogs)")
            if new.rawValue > lastNotified.rawValue {
                lastNotified = new
                onElevation?(
                    "Your Mac is throttling (\(label.lowercased()))",
                    "macOS is slowing the CPU to cool down. Busiest right now: \(hogs).")
            }
        case .fair:
            appendLog("\(stamp) THERMAL fair — warm but not throttling")
        default:
            if old == .serious || old == .critical {
                appendLog("\(stamp) RECOVERED — thermal state back to normal")
            }
            lastNotified = .nominal
        }
    }

    /// "next-server 182%, Chrome 96%" — the names to blame in the receipt.
    private static func topCPU(limit: Int = 3) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pcpu,comm", "-r"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "unknown" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return "unknown" }
        let rows = text.split(separator: "\n").dropFirst().prefix(limit).compactMap { line -> String? in
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let pct = Double(parts[0]) else { return nil }
            return "\(parts[1].trimmingCharacters(in: .whitespaces)) \(Int(pct))%"
        }
        return rows.isEmpty ? "unknown" : rows.joined(separator: ", ")
    }

    private func appendLog(_ line: String) {
        let url = Self.logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((line + "\n").utf8).write(to: url)
        }
        Logger(subsystem: "com.mac-analyzers.app", category: "thermal")
            .notice("\(line, privacy: .public)")
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    public var label: String {
        switch state {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Throttling"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    public var isElevated: Bool {
        state == .serious || state == .critical
    }
}
