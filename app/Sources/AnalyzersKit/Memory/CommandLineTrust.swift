import Foundation

/// Whether what the process table says a process IS can be believed yet.
///
/// A Stop decides what to reach from command lines: which process is a terminal session, which is a
/// coding agent. Two states make a command line say nothing true: it cannot be read at all (the process
/// is between fork and exec, or ending), or it is still the one its parent had, which is what a child
/// shows for the moments after fork and before exec. A process started a moment ago whose command line
/// is exactly its parent's has not become itself yet, and a session that is about to start could be
/// hiding in it. For those, Stop and Quit wait: "could not tell, so nothing was stopped", and the next
/// refresh tries again. A process of another account is never judged here (its arguments are never
/// readable, and it cannot be signalled anyway).
enum CommandLineTrust {

    /// How long after it started a process may still show its parent's command line.
    static let settleWindow: TimeInterval = 3

    /// Why this process's command line cannot be trusted yet, or nil when it can.
    static func doubt(pid: Int32, now: Date = Date()) -> String? {
        guard let who = ProcTable.identity(of: pid), who.uid == getuid() else { return nil }
        // a zombie has ended: its arguments are gone for good and there is nothing in it to signal or to hide
        // a session. Judging it would refuse every program that leaks one, forever.
        guard !isZombie(pid), let birth = ProcessTree.Birth.of(pid) else { return nil }
        let age = now.timeIntervalSince1970 - (TimeInterval(birth.seconds) + TimeInterval(birth.microseconds) / 1_000_000)
        let parent = who.ppid > 1 ? ProcTable.rawCommandLine(of: Int32(who.ppid)) : nil
        return judge(command: ProcTable.rawCommandLine(of: pid), parent: parent, age: age)
    }

    /// The rule itself, on what was read. `command` nil is "the kernel would not say"; "" is "readable, all empty".
    /// A command line identical to the parent's counts as unsettled only for the first `settleWindow` seconds:
    /// a subshell keeps its parent's command line for its whole life, so the doubt must end. The window is not
    /// what protects a Stop (a process that has settled is read again at the moment of every signal, with its
    /// start time); it only keeps a Stop from deciding on the few moments between fork and exec.
    static func judge(command: String?, parent: String?, age: TimeInterval) -> String? {
        guard let command else { return "its command line could not be read" }
        guard age < settleWindow, let parent, parent == command else { return nil }
        return "it has only just started and still shows the command line of the program that started it"
    }

    private static func isZombie(_ pid: Int32) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size >= MemoryLayout<kinfo_proc>.stride else { return false }
        return info.kp_proc.p_stat == SZOMB
    }

    /// The refusal for the first process of these that cannot be told yet, or nil.
    static func refusal(pids: [Int32], name: String, action: String = "stopped") -> String? {
        for pid in pids {
            if let why = doubt(pid: pid) {
                return "Mac Analyzers could not tell what \(name) is running (\(why)), so nothing was \(action). Try again in a moment."
            }
        }
        return nil
    }
}
