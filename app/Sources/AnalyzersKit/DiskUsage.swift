import Foundation

/// Boot-volume capacity right now (the "purgeable-aware" free-space number —
/// the same important-usage figure Finder shows, not raw df).
public struct DiskUsage: Sendable, Equatable {
    public let totalBytes: Int64
    public let freeBytes: Int64

    public init(totalBytes: Int64, freeBytes: Int64) { self.totalBytes = totalBytes; self.freeBytes = freeBytes }

    public var usedBytes: Int64 { totalBytes - freeBytes }
    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
    /// Nearly full: the screen says so in words and colours the bar, whatever any forecast says.
    public var isLow: Bool { usedFraction >= 0.9 }
    public var lowText: String { "Low on space: \(freeText) free, \(Int((usedFraction * 100).rounded())) percent used." }
    public var usedText: String { Self.gb(usedBytes) }
    public var totalText: String { Self.gb(totalBytes) }
    public var freeText: String { Self.gb(freeBytes) }

    static func gb(_ bytes: Int64) -> String {
        String(format: "%.0f GB", Double(bytes) / 1_000_000_000)
    }
}
