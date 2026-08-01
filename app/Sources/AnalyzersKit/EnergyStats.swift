import AppKit
import CLibProc
import Foundation

/// Per-process ENERGY since launch — the battery-blame ledger. Reads the
/// kernel's own accounting (proc_pid_rusage energy counters, no sudo, no
/// powermetrics): who actually drained the battery, not who looks busy.
public struct EnergyEntry: Identifiable, Sendable {
    public let pid: Int
    public let name: String
    public let energyNJ: UInt64

    public var id: Int { pid }

    /// Milliwatt-hours: 1 mWh = 3.6e9 nJ.
    public var mWh: Double { Double(energyNJ) / 3.6e9 }

    public var energyText: String {
        mWh >= 1000 ? String(format: "%.2f Wh", mWh / 1000)
                    : String(format: "%.0f mWh", mWh)
    }
}

public enum EnergyStats {

    /// Top energy consumers among live processes, descending. Cumulative
    /// since each process launched — same honesty note as the network pane.
    public static func snapshot(limit: Int = 25) -> [EnergyEntry] {
        var pids = [Int32](repeating: 0, count: 4096)
        let byteCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        guard byteCount > 0 else { return [] }
        let count = Int(byteCount) / MemoryLayout<Int32>.stride

        var entries: [EnergyEntry] = []
        for i in 0..<min(count, pids.count) {
            let pid = pids[i]
            guard pid > 500 else { continue }
            var info = rusage_info_current()
            let result = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard result == 0, info.ri_energy_nj > 0 else { continue }
            let name = ProcessLiveness.commandName(pid: Int(pid)) ?? "pid \(pid)"
            entries.append(EnergyEntry(pid: Int(pid), name: name,
                                       energyNJ: info.ri_energy_nj))
        }
        return entries.sorted { $0.energyNJ > $1.energyNJ }
            .prefix(limit).map { $0 }
    }
}
