import Foundation

/// Parsed guard forensics snapshot — "Activity Monitor's Memory tab, frozen
/// at the moment of crisis."
public struct ForensicsProcessRow: Identifiable, Hashable, Sendable {
    public let rssKB: Int
    public let pid: Int
    public let ppid: Int
    public let etime: String
    public let args: String
    public var id: Int { pid }

    public var rssMB: Int { rssKB / 1024 }
    public var rssText: String { String(format: "%.1f GB", Double(rssKB) / 1_048_576) }
    public var friendlyName: String {
        ProcessGlossary.friendlyName(for: args) ?? shortName
    }
    public var shortName: String {
        if let range = args.range(of: #"([^/]+)\.app"#, options: .regularExpression) {
            return String(args[range].dropLast(4))
        }
        return String(args.split(separator: " ").first.map {
            $0.split(separator: "/").last.map(String.init) ?? String($0)
        } ?? args)
    }
}

public struct ForensicsSnapshot: Sendable {
    public let header: String
    public let pressureLevel: Int?
    public let swapLine: String?
    public let physMemLine: String?
    public let processes: [ForensicsProcessRow]
}

public enum ForensicsParser {

    public static func parse(fileAt path: String) -> ForensicsSnapshot? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var header = ""
        var pressure: Int?
        var swap: String?
        var physMem: String?
        var rows: [ForensicsProcessRow] = []
        var inProcesses = false

        for raw in text.split(separator: "\n") {
            let line = String(raw)
            if line.hasPrefix("===") {
                header = line.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
                continue
            }
            if line.contains("top 25 by RSS") { inProcesses = true; continue }
            if line.hasPrefix("---") { continue }
            if line.hasPrefix("kern.memorystatus_vm_pressure_level:") {
                pressure = Int(line.components(separatedBy: ": ").last ?? "")
                continue
            }
            if line.hasPrefix("vm.swapusage:") {
                swap = String(line.dropFirst(13)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("PhysMem:") {
                physMem = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if inProcesses {
                // "rssKB pid ppid etime args…" (args may contain spaces)
                let fields = line.split(separator: " ", maxSplits: 4,
                                        omittingEmptySubsequences: true)
                guard fields.count >= 5,
                      let rss = Int(fields[0]), let pid = Int(fields[1]),
                      let ppid = Int(fields[2]) else { continue }
                rows.append(ForensicsProcessRow(
                    rssKB: rss, pid: pid, ppid: ppid,
                    etime: String(fields[3]), args: String(fields[4])))
            }
        }
        return ForensicsSnapshot(header: header, pressureLevel: pressure,
                                 swapLine: swap, physMemLine: physMem,
                                 processes: rows)
    }
}
