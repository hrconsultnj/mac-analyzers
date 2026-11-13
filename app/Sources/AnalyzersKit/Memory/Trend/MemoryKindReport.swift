import Foundation

/// What one memory screen says, as data: the headline, the facts under it, the charts and the sentences about what can and
/// cannot be shown. The screens draw it and `agent-runner --probe-memory-kinds` prints it, so what the probe proves is what
/// a person reads. Built from the samples of `MemoryTrend`; the headline is the newest sample, the same reading the block shows.
public struct MemoryKindReport: Sendable {

    public struct Series: Sendable, Identifiable {
        public enum Unit: Sendable { case bytes, bytesPerSecond }
        public let name: String
        /// Which block row's colour it takes (identity follows the entity, never its rank).
        public let tint: MemoryKind
        /// A second series of the same kind is told apart by its line, not by colour alone.
        public let dashed: Bool
        public let points: [(date: Date, value: Double)]
        public var id: String { name }
    }

    public struct Chart: Sendable, Identifiable {
        public let title: String
        public let unit: Series.Unit
        public let series: [Series]
        public var id: String { title }
    }

    public struct Band: Sendable {
        public let date: Date
        public let level: Int
    }

    public let kind: MemoryKind
    public let headline: String
    public let caption: String
    public let facts: [(label: String, value: String)]
    public let charts: [Chart]
    /// The pressure level over time, for the screen that shows it.
    public let pressure: [Band]
    /// What this screen does not show, and why, in sentences.
    public let notes: [String]
    public let since: Date?

    public static func pressureWord(_ level: Int) -> String {
        switch level {
        case ..<2: "Normal"
        case 2..<4: "Warning"
        default: "Critical"
        }
    }

    /// A rate: one decimal under 10, none above ("4.2 MB/s", "286 MB/s"), KB/s below a megabyte.
    public static func rateText(_ bytesPerSecond: Double) -> String { ByteSize.rate(bytesPerSecond) }

    /// An axis label or a crosshair readout: up to two decimals, trailing zeros dropped.
    public static func axisBytesText(_ bytes: Double) -> String { ByteSize.text(Int64(bytes), .axis) }

    public static func make(_ kind: MemoryKind, samples: [MemorySample]) -> MemoryKindReport? {
        guard let now = samples.last else { return nil }
        let b = now.breakdown
        func series(_ name: String, _ tint: MemoryKind, dashed: Bool = false, _ value: (MemorySample) -> Double) -> Series {
            Series(name: name, tint: tint, dashed: dashed, points: samples.map { ($0.date, value($0)) })
        }
        /// A rate needs two samples; the first has none.
        func rates(_ name: String, _ tint: MemoryKind, dashed: Bool = false, _ rate: (MemorySample, MemorySample) -> Double) -> Series {
            Series(name: name, tint: tint, dashed: dashed, points: zip(samples.dropFirst(), samples).map { ($0.date, rate($0, $1)) })
        }
        let installed = MemorySize.text(b.totalBytes, .headline)
        let note = "The figures on this screen are read from the kernel's own counters every two seconds while a memory screen is open; the chart keeps the last 30 minutes and starts again if the screens were closed for over a minute."
        switch kind {
        case .app:
            return MemoryKindReport(
                kind: kind, headline: MemorySize.text(b.appBytes, .headline), caption: "of \(installed) installed",
                facts: [("Used by apps and tools", MemorySize.text(b.appBytes, .figure)),
                        ("Wired, compressed and cached", MemorySize.text(b.wiredBytes + b.compressedBytes + b.cachedBytes, .figure))],
                charts: [Chart(title: Names.MemoryKind.app, unit: .bytes, series: [series(Names.MemoryKind.app, .app) { Double($0.breakdown.appBytes) }])],
                pressure: [],
                notes: ["The table lists what can be measured: every process of your own account. Processes of other accounts, including macOS's own, cannot be sized by an app, so what they hold is part of the total and not of the table.", note],
                since: samples.first?.date)
        case .wired:
            var facts = [("Wired", MemorySize.text(b.wiredBytes, .figure))]
            if let graphics = now.graphicsBytes { facts.append(("Graphics driver has allocated", MemorySize.text(graphics, .figure))) }
            var lines = [series("Wired", .wired) { Double($0.breakdown.wiredBytes) }]
            if now.graphicsBytes != nil {
                lines.append(series("Graphics allocated", .free, dashed: true) { Double($0.graphicsBytes ?? 0) })
            }
            return MemoryKindReport(
                kind: kind, headline: MemorySize.text(b.wiredBytes, .headline), caption: "of \(installed) installed",
                facts: facts, charts: [Chart(title: Names.MemoryKind.wired, unit: .bytes, series: lines)], pressure: [],
                notes: ["macOS does not say what wired memory is made of to an app that is not it: only the total can be read. The graphics figure is what the graphics driver has allocated, system-wide; not all of it is wired.", note],
                since: samples.first?.date)
        case .compressed:
            let ratio = b.compressedBytes > 0 ? Double(b.compressedOriginalBytes) / Double(b.compressedBytes) : 0
            let saved = max(0, b.compressedOriginalBytes - b.compressedBytes)
            return MemoryKindReport(
                kind: kind, headline: MemorySize.text(b.compressedBytes, .headline), caption: "holding \(MemorySize.text(b.compressedOriginalBytes, .figure)) of memory",
                facts: [("Taken in memory", MemorySize.text(b.compressedBytes, .figure)),
                        ("Holds, uncompressed", MemorySize.text(b.compressedOriginalBytes, .figure)),
                        ("Squeezed", ratio > 0 ? String(format: "%.1f to 1", ratio) : "—"),
                        ("Room it gives back", MemorySize.text(saved, .figure))],
                charts: [Chart(title: Names.MemoryKind.compressed, unit: .bytes, series: [
                            series("Taken in memory", .compressed) { Double($0.breakdown.compressedBytes) },
                            series("Holds, uncompressed", .compressed, dashed: true) { Double($0.breakdown.compressedOriginalBytes) }]),
                         Chart(title: "Squeezing and Reading Back", unit: .bytesPerSecond, series: [
                            rates("Squeezed per second", .compressed) { $0.compressionRate(since: $1) },
                            rates("Read back per second", .compressed, dashed: true) { $0.decompressionRate(since: $1) }])],
                pressure: [],
                notes: ["No program can be asked how much of ITS memory is compressed: the system gives that only to its own tools. The table below is what the system's own `top` reports, read when this screen opens (and when you ask), for every process of the Mac, macOS's included.", note],
                since: samples.first?.date)
        case .cached:
            return MemoryKindReport(
                kind: kind, headline: MemorySize.text(b.cachedBytes, .headline), caption: "kept for speed",
                facts: [("Cached files and purgeable memory", MemorySize.text(b.cachedBytes, .figure))],
                charts: [Chart(title: Names.MemoryKind.cached, unit: .bytes, series: [series(Names.MemoryKind.cached, .cached) { Double($0.breakdown.cachedBytes) }])],
                pressure: [],
                notes: ["Which files are cached, and which program they belong to, cannot be read by an app: only the total can. It is not counted as in use because macOS gives it back as soon as it is needed.", note],
                since: samples.first?.date)
        case .free:
            return MemoryKindReport(
                kind: kind, headline: MemorySize.text(b.freeBytes, .headline), caption: "pressure: \(pressureWord(now.pressureLevel).lowercased())",
                facts: [("Free", MemorySize.text(b.freeBytes, .figure)), ("In use (apps, wired, compressed)", MemorySize.text(b.usedBytes, .figure)),
                        ("Memory pressure", pressureWord(now.pressureLevel))],
                charts: [Chart(title: Names.MemoryKind.free, unit: .bytes, series: [series(Names.MemoryKind.free, .free) { Double($0.breakdown.freeBytes) }])],
                pressure: samples.map { Band(date: $0.date, level: $0.pressureLevel) },
                notes: ["Pressure is the system's own verdict on whether memory is keeping up: normal, warning or critical. Free memory on its own says little, because macOS fills spare room with cached files on purpose.", note],
                since: samples.first?.date)
        case .swap:
            let share = now.swapTotalBytes > 0 ? Double(now.swapUsedBytes) / Double(now.swapTotalBytes) : 0
            var facts = [("Used", MemorySize.text(now.swapUsedBytes, .figure)), ("Of", MemorySize.text(now.swapTotalBytes, .figure)),
                         ("Share used", String(format: "%.0f%%", share * 100))]
            if samples.count >= 2, let earlier = samples.dropLast().last {
                facts.append(("Moved to disk now", rateText(now.swapOutRate(since: earlier))))
                facts.append(("Read back now", rateText(now.swapInRate(since: earlier))))
            }
            return MemoryKindReport(
                kind: kind, headline: MemorySize.text(now.swapUsedBytes, .headline), caption: "of \(MemorySize.text(now.swapTotalBytes, .figure)) swap file space",
                facts: facts,
                charts: [Chart(title: Names.MemoryKind.swap, unit: .bytes, series: [series(Names.MemoryKind.swap, .swap) { Double($0.swapUsedBytes) }]),
                         Chart(title: "Moving to and from the Disk", unit: .bytesPerSecond, series: [
                            rates("Moved to disk per second", .swap) { $0.swapOutRate(since: $1) },
                            rates("Read back per second", .swap, dashed: true) { $0.swapInRate(since: $1) }])],
                pressure: [],
                notes: ["Swap is not per program: the system does not say which program's memory is on the disk. The size of the swap file space grows when the Mac needs it.", note],
                since: samples.first?.date)
        }
    }
}
