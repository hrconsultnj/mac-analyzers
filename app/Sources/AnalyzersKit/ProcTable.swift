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

    /// Every live pid — the ONE place the table is listed.
    ///
    /// `proc_listallpids` takes a buffer size in BYTES but returns a COUNT of
    /// pids. Reading that count as a byte length (and dividing by four again)
    /// made every sweep stop a quarter of the way through the table — on a
    /// Mac with ~1,000 processes, roughly 750 of them were never looked at.
    public static func allPIDs() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // headroom: processes can appear between the size query and the read
        var pids = [Int32](repeating: 0, count: Int(estimate) + 128)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        guard count > 0 else { return [] }
        return Array(pids.prefix(min(Int(count), pids.count)))
    }

    /// Memory the kernel accounts to one process. `footprint` is the number
    /// Activity Monitor's Memory column shows (private + compressed, counted
    /// once); `resident` is RSS, the number the guard acts on. nil when the
    /// kernel refuses — it only answers for processes the user owns.
    public static func usage(of pid: Int32) -> (resident: UInt64, footprint: UInt64)? {
        var usage = rusage_info_current()
        let ok = withUnsafeMutablePointer(to: &usage) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard ok == 0 else { return nil }
        return (usage.ri_resident_size, usage.ri_phys_footprint)
    }

    /// Parent + owner, readable for EVERY process (unlike memory, the kernel
    /// does not restrict this to the user's own). nil when the pid is gone.
    public static func identity(of pid: Int32) -> (ppid: Int, uid: UInt32)? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return (Int(info.pbsi_ppid), info.pbsi_uid)
    }

    public static func sweep(minimumMB: Int) -> [RawProc] {
        var result: [RawProc] = []
        result.reserveCapacity(64)
        for pid in allPIDs() {
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

    static func parentPID(of pid: Int32) -> Int {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
        return Int(info.kp_eproc.e_ppid)
    }

    /// KERN_ARGMAX never changes while the system is up — ask once.
    private static let argMax: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        return sysctl(&mib, 2, &value, &size, nil, 0) == 0 && value > 0 ? Int(value) : 0
    }()

    /// Full argv via KERN_PROCARGS2 (what `ps -o args` shows), falling back
    /// to the executable path. Only called for processes over the floor.
    ///
    /// The buffer is deliberately NOT zero-filled: it is ARGMAX (1 MB) and
    /// the kernel writes only the bytes it reports back, so clearing it first
    /// cost a megabyte of memset per process — fine for a few dozen rows,
    /// wasteful for the full census.
    static func commandLine(of pid: Int32) -> String {
        guard argMax > MemoryLayout<Int32>.stride else { return executablePath(of: pid) }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: argMax, alignment: MemoryLayout<Int32>.alignment)
        defer { buffer.deallocate() }
        var bufferSize = argMax
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, buffer, &bufferSize, nil, 0) == 0,
              bufferSize > MemoryLayout<Int32>.stride
        else { return executablePath(of: pid) }

        // the arguments and nothing after them: the environment follows in the same buffer
        // (see `ProcessArguments`)
        let args = ProcessArguments.parse(UnsafeRawBufferPointer(start: buffer, count: bufferSize))
        let joined = args.joined(separator: " ")
        return joined.isEmpty ? executablePath(of: pid) : joined
    }

    static func executablePath(of pid: Int32) -> String {
        // proc_pidpath takes an untyped pointer, so the buffer is bytes and
        // only the returned length (no terminating NUL) is decoded
        var buffer = [UInt8](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "pid \(pid)" }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
