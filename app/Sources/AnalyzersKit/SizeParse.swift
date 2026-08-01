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

    public static func format(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb >= 1_048_576 { return String(format: "%.1f GB", kb / 1_048_576) }
        if kb >= 1024 { return String(format: "%.0f MB", kb / 1024) }
        return String(format: "%.0f KB", kb)
    }
}
