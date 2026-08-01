import Darwin
import Foundation

/// Answers "is the process this log line talked about STILL the one running?"
/// pid existence alone lies twice — pids get recycled and a killed process can
/// linger as a zombie — so identity is: same pid + same command name + the
/// process started BEFORE the event was logged.
public enum ProcessLiveness {

    public static func isStillRunning(pid: Int, name: String, loggedAt: Date) -> Bool {
        guard pid > 0, pid <= Int(Int32.max) else { return false }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0,
              size >= MemoryLayout<kinfo_proc>.stride,
              info.kp_proc.p_pid == Int32(pid),
              info.kp_proc.p_stat != 5 /* SZOMB — dead, parent hasn't reaped */
        else { return false }

        // Identity: kernel comm is MAXCOMLEN(16)-truncated; the log name may
        // carry decoration ("next-server (v16.2.6)") — compare first tokens,
        // truncation-tolerant in both directions.
        let comm = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }.lowercased()
        let logged = (name.split(separator: " ").first.map(String.init) ?? name).lowercased()
        if !comm.isEmpty, !logged.isEmpty,
           !logged.hasPrefix(comm), !comm.hasPrefix(String(logged.prefix(16))) {
            return false        // pid recycled by a different program
        }

        // pid recycled by the SAME program (dev servers restart constantly):
        // a process born after the log line can't be the one it described.
        let start = info.kp_proc.p_starttime
        let started = Date(timeIntervalSince1970:
            TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
        return started <= loggedAt.addingTimeInterval(2)
    }
}

public extension GuardEvent {
    /// nil when the event has no process to check (pressure, forensics, …).
    var isProcessStillRunning: Bool? {
        guard let pid else { return nil }
        return ProcessLiveness.isStillRunning(pid: pid, name: processName, loggedAt: date)
    }
}
