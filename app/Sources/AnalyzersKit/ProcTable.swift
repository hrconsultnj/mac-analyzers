import CLibProc
import Darwin
import Foundation

/// The process table without forking anything.
///
/// Every live view used to reach `/bin/ps` — three separate fork/exec pairs
/// per guard-store reload, each re-reading the whole table. The kernel will
/// answer the same questions directly (`proc_listallpids` + `proc_pid_rusage`
/// + `sysctl`), so this does that instead.
///
/// The one genuinely expensive call is fetching a process's full argv
/// (KERN_PROCARGS2), which the dev-tool patterns need — so it is fetched
/// ONLY for processes that already passed the memory floor, which is a few
/// dozen rather than several hundred.
public struct RawProc: Sendable {
    public let pid: Int
    public let ppid: Int
    public let residentMB: Int
    public let command: String        // argv when available, else exec path
}

public enum ProcTable {

    public static func sweep(minimumMB: Int) -> [RawProc] {
        var pids = [Int32](repeating: 0, count: 8192)
        let byteCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        guard byteCount > 0 else { return [] }
        let count = min(Int(byteCount) / MemoryLayout<Int32>.stride, pids.count)

        var result: [RawProc] = []
        result.reserveCapacity(64)
        for index in 0..<count {
            let pid = pids[index]
            guard pid > 500 else { continue }

            // memory first — cheap, and it filters out almost everything
            var usage = rusage_info_current()
            let ok = withUnsafeMutablePointer(to: &usage) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard ok == 0 else { continue }
            let rssMB = Int(usage.ri_resident_size / (1024 * 1024))
            guard rssMB >= minimumMB else { continue }

            result.append(RawProc(pid: Int(pid),
                                  ppid: parentPID(of: pid),
                                  residentMB: rssMB,
                                  command: commandLine(of: pid)))
        }
        return result
    }

    /// Ancestry needs parents that may sit UNDER the memory floor (a slim
    /// launcher owning fat helpers is the normal shape). This fetches just
    /// enough for the climb — no argv, so it stays cheap.
    public static func lightweight(pid: Int) -> RawProc? {
        let pid32 = Int32(pid)
        guard pid > 0 else { return nil }
        var usage = rusage_info_current()
        let ok = withUnsafeMutablePointer(to: &usage) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid32, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard ok == 0 else { return nil }
        return RawProc(pid: pid,
                       ppid: parentPID(of: pid32),
                       residentMB: Int(usage.ri_resident_size / (1024 * 1024)),
                       command: executablePath(of: pid32))
    }

    private static func parentPID(of pid: Int32) -> Int {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
        return Int(info.kp_eproc.e_ppid)
    }

    /// Full argv via KERN_PROCARGS2 (what `ps -o args` shows), falling back
    /// to the executable path. Only called for processes over the floor.
    private static func commandLine(of pid: Int32) -> String {
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        var mibMax: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mibMax, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else {
            return executablePath(of: pid)
        }
        var buffer = [CChar](repeating: 0, count: Int(argMax))
        var bufferSize = Int(argMax)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &bufferSize, nil, 0) == 0,
              bufferSize > MemoryLayout<Int32>.stride
        else { return executablePath(of: pid) }

        // layout: [argc: Int32][exec path\0][padding \0s][argv0\0][argv1\0]…
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        let bytes = buffer.prefix(bufferSize).map { UInt8(bitPattern: $0) }
        var cursor = MemoryLayout<Int32>.stride
        func nextString() -> String? {
            while cursor < bytes.count, bytes[cursor] == 0 { cursor += 1 }
            guard cursor < bytes.count else { return nil }
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
            return String(decoding: bytes[start..<cursor], as: UTF8.self)
        }
        guard nextString() != nil else { return executablePath(of: pid) }  // exec path
        var args: [String] = []
        for _ in 0..<max(argc, 1) {
            guard let arg = nextString() else { break }
            args.append(arg)
        }
        let joined = args.joined(separator: " ")
        return joined.isEmpty ? executablePath(of: pid) : joined
    }

    private static func executablePath(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }
}
