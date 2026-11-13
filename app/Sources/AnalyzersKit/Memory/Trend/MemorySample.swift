import Darwin
import Foundation
import IOKit

/// One look at memory: the five figures of the Monitor's block (from the same reading, so they agree), the counters that
/// make rates, swap, the pressure level and the graphics driver's allocation. Everything here is readable without
/// privileges (see `tasks-plans/research/app/memory-kinds-readable-unprivileged-2026-11-13.md`).
public struct MemorySample: Sendable, Equatable {
    public let date: Date
    public let breakdown: MemoryBreakdown
    public let swapUsedBytes: Int64
    public let swapTotalBytes: Int64
    /// Pressure level as the kernel gives it: 1 normal, 2 warning, 4 critical.
    public let pressureLevel: Int
    /// What the graphics driver has allocated (system-wide), when it could be read.
    public let graphicsBytes: Int64?
    /// Lifetime counters, in pages of `pageSize`; a rate is the difference between two samples over the time between them.
    public let swapIns: UInt64
    public let swapOuts: UInt64
    public let compressions: UInt64
    public let decompressions: UInt64
    public let pageSize: Int64

    public init(date: Date, breakdown: MemoryBreakdown, swapUsedBytes: Int64, swapTotalBytes: Int64, pressureLevel: Int,
                graphicsBytes: Int64?, swapIns: UInt64, swapOuts: UInt64, compressions: UInt64, decompressions: UInt64,
                pageSize: Int64) {
        self.date = date
        self.breakdown = breakdown
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressureLevel = pressureLevel
        self.graphicsBytes = graphicsBytes
        self.swapIns = swapIns
        self.swapOuts = swapOuts
        self.compressions = compressions
        self.decompressions = decompressions
        self.pageSize = pageSize
    }

    /// Reads memory now. `graphics` is carried over from an earlier sample when the caller reads it less often.
    public static func read(graphics: Int64?) -> MemorySample? {
        guard let reading = VMReading.take() else { return nil }
        let stats = reading.stats
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) != 0 { level = 1 }
        return MemorySample(
            date: Date(),
            breakdown: MemoryBreakdown.make(from: stats, pageSize: reading.pageSize),
            swapUsedBytes: swapOK ? Int64(swap.xsu_used) : 0,
            swapTotalBytes: swapOK ? Int64(swap.xsu_total) : 0,
            pressureLevel: Int(level),
            graphicsBytes: graphics,
            swapIns: stats.swapins, swapOuts: stats.swapouts,
            compressions: stats.compressions, decompressions: stats.decompressions,
            pageSize: Int64(reading.pageSize))
    }

    /// Swap used and its file space now, or nil when the system does not say.
    public static func readSwap() -> (used: Int64, total: Int64)? {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return nil }
        return (Int64(swap.xsu_used), Int64(swap.xsu_total))
    }

    /// The graphics driver's "In use system memory", or nil when no driver reports it. Vendor-specific key (read from the
    /// IORegistry, unprivileged); the figure is what the driver allocated, not a statement that those pages are wired.
    public static func readGraphicsBytes() -> Int64? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var total: Int64 = 0
        var found = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let used = stats["In use system memory"] as? NSNumber else { continue }
            total += used.int64Value
            found = true
        }
        return found ? total : nil
    }

    // MARK: - rates

    /// Pages per second between two samples, in bytes per second.
    private func rate(_ now: UInt64, _ before: UInt64, since earlier: MemorySample) -> Double {
        let seconds = date.timeIntervalSince(earlier.date)
        guard seconds > 0, now >= before else { return 0 }
        return Double(now - before) * Double(pageSize) / seconds
    }
    public func swapInRate(since earlier: MemorySample) -> Double { rate(swapIns, earlier.swapIns, since: earlier) }
    public func swapOutRate(since earlier: MemorySample) -> Double { rate(swapOuts, earlier.swapOuts, since: earlier) }
    public func compressionRate(since earlier: MemorySample) -> Double { rate(compressions, earlier.compressions, since: earlier) }
    public func decompressionRate(since earlier: MemorySample) -> Double { rate(decompressions, earlier.decompressions, since: earlier) }
}
