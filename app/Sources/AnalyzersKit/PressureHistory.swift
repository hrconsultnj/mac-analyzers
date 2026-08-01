import AppKit
import Foundation
import Observation
import os

/// Rolling 30-minute memory history for the menu-bar sparkline: one sample
/// every 30 seconds of "how much of RAM is genuinely in use" (active + wired
/// + compressed over physical), straight from mach host statistics — the
/// same signal family the guard's pressure checks watch.
@Observable
@MainActor
public final class PressureHistory {

    public private(set) var samples: [Double] = []

    private var timer: Timer?
    private let capacity = 60          // 60 × 30 s = 30 minutes

    public init() {
        record()
        let t = Timer(timeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.record() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func record() {
        guard let fraction = Self.usedFraction() else { return }
        samples.append(fraction)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        Logger(subsystem: "com.mac-analyzers.app", category: "sparkline")
            .notice("sample \(self.samples.count, privacy: .public): \(Int(fraction * 100), privacy: .public)% used")
    }

    /// active + wired + compressed pages over physical RAM (0…1).
    private static func usedFraction() -> Double? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = Double(getpagesize())
        let usedBytes = (Double(info.active_count) + Double(info.wire_count)
                         + Double(info.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        return min(1, max(0, usedBytes / total))
    }
}

/// Draws the sparkline as a TEMPLATE image (black + alpha) so the menu bar
/// tints it correctly for light/dark/translucent backdrops.
public enum SparklineRenderer {

    public static func image(values: [Double],
                             size: CGSize = CGSize(width: 42, height: 14)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard values.count > 1 else { return true }
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let stepX = rect.width / CGFloat(values.count - 1)
            // fixed 0…1 scale — a calm Mac draws low, pressure draws high;
            // no auto-normalizing (that would make quiet noise look dramatic)
            for (index, value) in values.enumerated() {
                let x = rect.minX + CGFloat(index) * stepX
                let y = rect.minY + 1.5 + (rect.height - 3) * CGFloat(value)
                if index == 0 {
                    path.move(to: NSPoint(x: x, y: y))
                } else {
                    path.line(to: NSPoint(x: x, y: y))
                }
            }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Chip glyph + sparkline as ONE template image — MenuBarExtra labels
    /// render a single image reliably; multiple sibling images do not.
    public static func labelImage(chip: NSImage?, values: [Double],
                                  sparkSize: CGSize = CGSize(width: 42, height: 14)) -> NSImage {
        let chipSide: CGFloat = 18
        let gap: CGFloat = 5
        let width = chipSide + gap + sparkSize.width
        let height: CGFloat = 18
        let composed = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            if let chip {
                chip.draw(in: NSRect(x: 0, y: (height - chipSide) / 2,
                                     width: chipSide, height: chipSide))
            }
            let spark = image(values: values, size: sparkSize)
            spark.draw(in: NSRect(x: chipSide + gap, y: (height - sparkSize.height) / 2,
                                  width: sparkSize.width, height: sparkSize.height))
            return true
        }
        composed.isTemplate = true
        return composed
    }
}
