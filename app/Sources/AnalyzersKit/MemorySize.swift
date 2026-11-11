import Foundation

/// One formatter for every memory figure on screen. Sizes under a gigabyte
/// stay in megabytes — "0.0 GB" for a 40 MB helper says nothing, and small
/// processes are exactly the ones that add up unnoticed.
public enum MemorySize {
    public static func text(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        if mb >= 10 { return String(format: "%.0f MB", mb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return bytes > 0 ? "<1 MB" : "0 MB"
    }
}
