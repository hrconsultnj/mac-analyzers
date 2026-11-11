import CLibProc
import Darwin
import Foundation

/// Processor time, from the kernel's own accounting: the same
/// `proc_pid_rusage` call the memory numbers come from. A process's CPU
/// percentage is how much of that time it used between two looks, divided by
/// the time that passed — what Activity Monitor's %CPU column shows.
extension ProcTable {

    /// Processor time (user plus system) each readable process has ever used,
    /// in nanoseconds. The kernel only answers for the user's own processes,
    /// so others are absent — a screen shows nothing for them rather than 0.
    public static func cpuTimes(of pids: [Int32]) -> [Int: UInt64] {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        var times: [Int: UInt64] = [:]
        times.reserveCapacity(pids.count)
        for pid in pids where pid > 0 {
            var usage = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard status == 0 else { continue }
            // ticks of the CPU's own clock → nanoseconds (125/3 on Apple silicon)
            let ticks = usage.ri_user_time &+ usage.ri_system_time
            times[Int(pid)] = UInt64(Double(ticks) * Double(timebase.numer) / Double(max(timebase.denom, 1)))
        }
        return times
    }
}

/// Turns two looks at processor time into percentages. One meter lives as
/// long as the screen that shows them; the first look has nothing to compare
/// with, so it reports nothing until the second.
public struct CPUMeter: Sendable {
    private var last: [Int: UInt64] = [:]
    private var lastLook: ContinuousClock.Instant?

    public init() {}

    /// Takes a look and returns each process's CPU use since the previous
    /// look, as a percentage of one core (a process using two cores reads
    /// 200). Empty on the first look. A process whose total went DOWN is a
    /// recycled pid, not negative work, and is skipped.
    public mutating func look(at times: [Int: UInt64], now: ContinuousClock.Instant = .now) -> [Int: Double] {
        defer { last = times; lastLook = now }
        guard let before = lastLook else { return [:] }
        let elapsed = before.duration(to: now)
        let nanoseconds = Double(elapsed.components.seconds) * 1e9
            + Double(elapsed.components.attoseconds) / 1e9
        guard nanoseconds > 0 else { return [:] }
        var percent: [Int: Double] = [:]
        for (pid, total) in times {
            guard let earlier = last[pid], total >= earlier else { continue }
            percent[pid] = Double(total - earlier) / nanoseconds * 100
        }
        return percent
    }
}
