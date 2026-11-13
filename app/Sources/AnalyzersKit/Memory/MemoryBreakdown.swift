import Darwin
import Foundation

/// Where physical memory is right now, in Activity Monitor's own terms — so
/// "Memory Used" here is the same sum the system shows: app + wired +
/// compressed. Cached files are deliberately NOT part of "used": macOS hands
/// them back the moment an app asks for room.
public struct MemoryBreakdown: Sendable, Equatable {
    public let totalBytes: Int64
    /// Anonymous memory apps and services are actively holding.
    public let appBytes: Int64
    /// Kernel, drivers, graphics — can't be moved or compressed.
    public let wiredBytes: Int64
    /// What the compressor OCCUPIES in RAM…
    public let compressedBytes: Int64
    /// …and how much idle app memory is packed inside it.
    public let compressedOriginalBytes: Int64
    /// File cache plus purgeable memory — reclaimable on demand.
    public let cachedBytes: Int64

    public var usedBytes: Int64 { appBytes + wiredBytes + compressedBytes }
    public var freeBytes: Int64 { max(0, totalBytes - usedBytes - cachedBytes) }

    public static func current() -> MemoryBreakdown? {
        guard let reading = VMReading.take() else { return nil }
        return make(from: reading.stats, pageSize: reading.pageSize)
    }

    /// The five figures from one reading of the kernel's counters. The block, the memory bar and every memory screen
    /// build theirs here, so they agree at the same moment.
    static func make(from stats: vm_statistics64, pageSize: vm_size_t) -> MemoryBreakdown {
        func bytes(_ pages: UInt64) -> Int64 { Int64(pages) * Int64(pageSize) }
        let purgeable = UInt64(stats.purgeable_count)
        let anonymous = UInt64(stats.internal_page_count)
        return MemoryBreakdown(
            totalBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            appBytes: bytes(anonymous > purgeable ? anonymous - purgeable : 0),
            wiredBytes: bytes(UInt64(stats.wire_count)),
            compressedBytes: bytes(UInt64(stats.compressor_page_count)),
            compressedOriginalBytes: bytes(stats.total_uncompressed_pages_in_compressor),
            cachedBytes: bytes(UInt64(stats.external_page_count) + purgeable))
    }
}

/// One `host_statistics64(HOST_VM_INFO64)` reading and the page size it counts in.
struct VMReading {
    let stats: vm_statistics64
    let pageSize: vm_size_t

    static func take() -> VMReading? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        return VMReading(stats: stats, pageSize: pageSize)
    }
}
