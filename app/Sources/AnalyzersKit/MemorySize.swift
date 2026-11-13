import Foundation

/// One formatter for every memory figure on screen. Sizes under a gigabyte
/// stay in megabytes — "0.0 GB" for a 40 MB helper says nothing, and small
/// processes are exactly the ones that add up unnoticed.
public enum MemorySize {
    /// A cell of a table or list: one decimal in gigabytes, none in megabytes ("3.4 GB", "827 MB", "<1 MB").
    public static func text(_ bytes: Int64) -> String { text(bytes, .cell) }

    /// The same figure written for where it is shown (`ByteSize.Style`): "<1 MB" stays for the cell style.
    public static func text(_ bytes: Int64, _ style: ByteSize.Style) -> String {
        if style == .cell, bytes < 1_048_576 { return bytes > 0 ? "<1 MB" : "0 MB" }
        return ByteSize.text(bytes, style)
    }
}
