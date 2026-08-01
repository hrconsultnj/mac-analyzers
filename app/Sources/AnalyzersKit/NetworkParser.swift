import AppKit
import Foundation

/// Parses network-snapshot.sh run blocks:
///   2026-08-01 02:44 | network snapshot | cumulative bytes since process launch
///   TOTAL in=142490799 out=708048784
///   Opera Helper pid=31146 in=1074927 out=235681240
public struct NetworkTalker: Identifiable, Sendable, Hashable {
    public let name: String
    public let pid: Int
    public let inBytes: Int64
    public let outBytes: Int64
    public var id: String { "\(pid)-\(name)" }

    public var totalBytes: Int64 { inBytes + outBytes }

    /// nettop truncates names — resolve the live process's real identity
    /// when the pid is still around (app bundle name, kernel comm, glossary).
    public var resolvedName: String {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let display = app.localizedName {
            return display
        }
        if let comm = ProcessLiveness.commandName(pid: pid) {
            return ProcessGlossary.friendlyName(for: comm) ?? comm
        }
        return ProcessGlossary.friendlyName(for: name) ?? name
    }
}

public struct NetworkSnapshot: Sendable {
    public let header: String
    public let totalIn: Int64
    public let totalOut: Int64
    public let talkers: [NetworkTalker]
}

public enum NetworkParser {

    /// Newest run block in the log, if any.
    public static func latest(fromLog url: URL) -> NetworkSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let blocks = text.components(separatedBy: "================================================================")
        guard let block = blocks.reversed().first(where: {
            $0.contains("network snapshot")
        }) else { return nil }
        return parse(block: block)
    }

    public static func parse(block: String) -> NetworkSnapshot? {
        var header = ""
        var totalIn: Int64 = 0
        var totalOut: Int64 = 0
        var talkers: [NetworkTalker] = []

        for rawLine in block.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.contains("| network snapshot |") {
                header = line
                continue
            }
            if line.hasPrefix("TOTAL ") {
                totalIn = value(of: "in", in: line) ?? 0
                totalOut = value(of: "out", in: line) ?? 0
                continue
            }
            guard let pidRange = line.range(of: #" pid=(\d+) "#, options: .regularExpression)
            else { continue }
            let name = String(line[line.startIndex..<pidRange.lowerBound])
            let pid = Int(line[pidRange].dropFirst(5).trimmingCharacters(in: .whitespaces)) ?? 0
            guard let inBytes = value(of: "in", in: line),
                  let outBytes = value(of: "out", in: line) else { continue }
            talkers.append(NetworkTalker(name: name, pid: pid,
                                         inBytes: inBytes, outBytes: outBytes))
        }
        guard !header.isEmpty else { return nil }
        return NetworkSnapshot(header: header, totalIn: totalIn,
                               totalOut: totalOut, talkers: talkers)
    }

    private static func value(of key: String, in line: String) -> Int64? {
        guard let range = line.range(of: "\(key)=(\\d+)", options: .regularExpression)
        else { return nil }
        return Int64(line[range].dropFirst(key.count + 1))
    }
}

public extension AnalyzersPaths {
    static let networkReports = home.appending(path: "mac-analyzers/reports/network")
    static let networkLog = networkReports.appending(path: "top-talkers.log")
    static let networkScript = suiteRoot.appending(path: "network-analyzer/network-snapshot.sh")
}
