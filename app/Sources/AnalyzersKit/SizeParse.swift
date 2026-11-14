import Foundation

/// Round-trips the bash scripts' human-readable sizes ("2.0 GB", "188 MB",
/// "48 KB", "~43.5 GB") to bytes for sorting/summing and back for display —
/// one implementation instead of three per-parser copies.
public enum ByteSize {

    public static func parse(_ text: String) -> Int64? {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "~ "))
        let parts = cleaned.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return nil }
        let multiplier: Double
        switch parts[1].uppercased() {
        case "KB": multiplier = 1024
        case "MB": multiplier = 1024 * 1024
        case "GB": multiplier = 1024 * 1024 * 1024
        case "TB": multiplier = 1024 * 1024 * 1024 * 1024
        case "B": multiplier = 1
        default: return nil
        }
        return Int64(value * multiplier)
    }

    /// How a size is written, by where it is shown. The decimals are a MAXIMUM, never padding: exactly 5 GB is "5 GB",
    /// 5.4 is "5.4 GB", 18.63 is "18.63 GB".
    ///  - `axis`: chart axes and the readout under a crosshair, which are for reading change: two decimals.
    ///  - `figure`: a list of figures in the style of Activity Monitor's footer (the memory block, a screen's facts): two
    ///    decimals in gigabytes.
    ///  - `headline`: the big number at the top of a screen: one decimal.
    ///  - `cell`: a table or list cell, as Activity Monitor's columns: one decimal in gigabytes, none in megabytes or less.
    public enum Style: Sendable { case axis, figure, headline, cell }

    /// A size in the largest unit it fills (GB, MB, KB, B), the style's decimals, trailing zeros dropped.
    public static func text(_ bytes: Int64, _ style: Style) -> String {
        let value = Double(max(0, bytes))
        let gb = value / 1_073_741_824, mb = value / 1_048_576, kb = value / 1_024
        let gbDecimals = (style == .axis || style == .figure) ? 2 : 1
        func number(_ x: Double, _ decimals: Int) -> String {
            x.formatted(.number.precision(.fractionLength(0...decimals)).grouping(.never))
        }
        if gb >= 1 { return "\(number(gb, gbDecimals)) GB" }
        if mb >= 1 { return "\(number(mb, 0)) MB" }
        if kb >= 1 { return "\(number(kb, 0)) KB" }
        return "\(Int(value)) B"
    }

    /// A rate: one decimal under 10, none above ("4.2 MB/s", "286 MB/s"), KB/s below a megabyte.
    public static func rate(_ bytesPerSecond: Double) -> String {
        let mb = max(0, bytesPerSecond) / 1_048_576
        if mb >= 10 { return "\(mb.formatted(.number.precision(.fractionLength(0)).grouping(.never))) MB/s" }
        if mb >= 1 { return "\(mb.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))) MB/s" }
        return "\((max(0, bytesPerSecond) / 1_024).formatted(.number.precision(.fractionLength(0)).grouping(.never))) KB/s"
    }

    public static func format(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb >= 1_048_576 { return String(format: "%.1f GB", kb / 1_048_576) }
        if kb >= 1024 { return String(format: "%.0f MB", kb / 1024) }
        return String(format: "%.0f KB", kb)
    }
}
