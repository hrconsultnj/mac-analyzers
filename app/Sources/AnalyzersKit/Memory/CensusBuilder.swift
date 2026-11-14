import Darwin
import Foundation

/// Takes one census. Lives for a single `MemoryCensus.take()` call: it reads
/// the process table once in `init`, and the extensions answer questions
/// about that one snapshot (so every answer agrees with every other).
///
/// A class only so the extensions can share its lookups' memo tables; it
/// never leaves the thread that created it.
final class CensusBuilder {

    /// One process as the kernel reports it.
    struct Entry {
        let pid: Int
        let ppid: Int
        let uid: UInt32
        /// Executable path, or "pid N" when the kernel won't say.
        let path: String
        let residentMB: Int
        /// Memory footprint — Activity Monitor's "Memory" column.
        var bytes: Int64
        /// false when nothing would report a size for it.
        var measured: Bool
    }

    let me = getuid()
    private(set) var table: [Int: Entry] = [:]

    // memo tables for the extensions (see each file)
    var ownerMemo: [Int: Int] = [:]
    var argvMemo: [Int: String] = [:]
    var classMemo: [Int: (category: CensusGroup.Category, name: String, appPath: String?)] = [:]
    var appIdentifiersMemo: [(id: String, name: String, path: String)]?
    var appInfoMemo: [String: (bundleID: String?, category: String?)] = [:]
    var kindEnvironmentMemo: KindEnvironment?
    /// The kinds, read once for this census so every answer comes from the same file.
    let kinds = KindCatalog.current

    var unmeasuredCount: Int { table.values.filter { !$0.measured }.count }

    init() {
        readEveryProcess()
        fillInSystemOwnedSizes()
    }

    /// Identity for all; memory where the kernel allows it (the user's own).
    private func readEveryProcess() {
        for pid in ProcTable.allPIDs() where pid > 0 {
            guard let identity = ProcTable.identity(of: pid) else { continue }
            let usage = ProcTable.usage(of: pid)
            table[Int(pid)] = Entry(
                pid: Int(pid), ppid: identity.ppid, uid: identity.uid,
                path: ProcTable.executablePath(of: pid),
                residentMB: Int((usage?.resident ?? 0) / 1_048_576),
                bytes: Int64(usage?.footprint ?? 0),
                measured: usage != nil)
        }
    }

    /// The kernel only sizes the user's OWN processes; macOS's daemons come
    /// from the one system tool allowed to read them.
    private func fillInSystemOwnedSizes() {
        let unread = table.values.filter { !$0.measured }.map(\.pid)
        guard !unread.isEmpty else { return }
        let privileged = PrivilegedFootprints.current()
        for pid in unread {
            guard let bytes = privileged[Int32(pid)] else { continue }
            table[pid]?.bytes = bytes
            table[pid]?.measured = true
        }
    }
}
