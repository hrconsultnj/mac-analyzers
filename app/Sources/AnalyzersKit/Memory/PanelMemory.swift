// PLACEHOLDER: the panel's own memory reader and pressure trace, to be DELETED when shell-builder's shared
// `MemoryTrend` (one sampler, one function for App/Wired/Compressed/Cached/Free/Swap) compiles. The panel's
// view (`MenuMemoryBlock`) is the only caller; it switches to the shared API and this file goes.

import Darwin
import Foundation
import Observation

/// What Activity Monitor's memory footer shows, as the menu-bar panel's Memory tab shows it. ONE source with the
/// main window's "Where Your Memory Is": the figures come from `MemoryBreakdown` (App + Wired + Compressed is
/// "Memory Used", File cache + purgeable is "Cached Files"), plus swap from `vm.swapusage`, so the panel, the window
/// and Activity Monitor read the same kernel counters.
public struct PanelMemory: Sendable, Equatable {
    public let breakdown: MemoryBreakdown
    /// `vm.swapusage`'s used figure; nil when the Mac would not say.
    public let swapUsedBytes: Int64?
    /// How much of memory is under pressure, 0 to 100: 100 minus `kern.memorystatus_level`, the percentage of memory
    /// the kernel still counts as available. nil when the Mac would not say.
    public let pressurePercent: Int?

    /// Reads the counters now. Cheap: three kernel calls, no process table.
    public static func take() -> PanelMemory? {
        guard let breakdown = MemoryBreakdown.current() else { return nil }
        return PanelMemory(breakdown: breakdown, swapUsedBytes: swapUsed(), pressurePercent: pressure())
    }

    public static func swapUsed() -> Int64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Int64(usage.xsu_used)
    }

    public static func pressure() -> Int? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 else { return nil }
        return min(100, max(0, 100 - Int(level)))
    }

    // the words, in Activity Monitor's order and spelling
    public var physicalText: String { MemorySize.text(breakdown.totalBytes) }
    public var usedText: String { MemorySize.text(breakdown.usedBytes) }
    public var cachedText: String { MemorySize.text(breakdown.cachedBytes) }
    public var swapText: String { swapUsedBytes.map(MemorySize.text) ?? "—" }
    public var appText: String { MemorySize.text(breakdown.appBytes) }
    public var wiredText: String { MemorySize.text(breakdown.wiredBytes) }
    public var compressedText: String { MemorySize.text(breakdown.compressedBytes) }
}

/// The last few minutes of memory pressure, for the panel's graph. Samples are taken ONLY while the panel's Memory
/// tab is on screen (the view's own task, cancelled when it goes), so a closed panel costs nothing; what was
/// recorded earlier stays for the next opening, with the gap between the two drawn as a gap.
@MainActor @Observable
public final class PanelPressureTrace {
    public static let shared = PanelPressureTrace()

    public struct Sample: Sendable, Equatable { public let date: Date; public let percent: Int }

    public private(set) var samples: [Sample] = []
    /// Five minutes of two-second samples.
    public static let window: TimeInterval = 300
    public static let interval: TimeInterval = 2
    /// A gap longer than this between two samples breaks the line.
    public static let gap: TimeInterval = 10

    public init() {}

    public func record(_ percent: Int?, at date: Date = Date()) {
        guard let percent else { return }
        samples.append(Sample(date: date, percent: percent))
        let oldest = date.addingTimeInterval(-Self.window)
        if let first = samples.firstIndex(where: { $0.date >= oldest }), first > 0 { samples.removeFirst(first) }
    }

    /// The samples as runs with no gap in them, each drawn as its own line.
    public var runs: [[Sample]] {
        var out: [[Sample]] = []
        for sample in samples {
            if let last = out.last?.last, sample.date.timeIntervalSince(last.date) <= Self.gap {
                out[out.count - 1].append(sample)
            } else {
                out.append([sample])
            }
        }
        return out
    }
}
