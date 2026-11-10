import Foundation

/// Boot-volume capacity right now (the "purgeable-aware" free-space number —
/// the same important-usage figure Finder shows, not raw df).
public struct DiskUsage: Sendable, Equatable {
    public let totalBytes: Int64
    public let freeBytes: Int64

    public var usedBytes: Int64 { totalBytes - freeBytes }
    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
    public var usedText: String { Self.gb(usedBytes) }
    public var totalText: String { Self.gb(totalBytes) }
    public var freeText: String { Self.gb(freeBytes) }

    static func gb(_ bytes: Int64) -> String {
        String(format: "%.0f GB", Double(bytes) / 1_000_000_000)
    }
}
