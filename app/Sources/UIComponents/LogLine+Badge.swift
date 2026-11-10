import AnalyzersKit
import SwiftUI

/// Log line to badge: the label and colour a line earns (KILLED, DRY, DONE …).
extension LogParser {

    public static func badge(for line: String) -> (text: String, color: Color)? {
        if line.contains(" KILLED ") { return ("KILLED", .red) }
        if line.contains("CRITICAL") { return ("CRITICAL", .red) }
        if line.contains(" SPIKE ") { return ("SPIKE", .orange) }
        if line.contains("WARNING") { return ("WARN", .orange) }
        if line.contains("CAP-EXCEEDED") { return ("OVER CAP", .orange) }
        if line.contains("[KILLED]") || line.contains("[QUIT]") { return ("CLOSED", .red) }
        if line.contains("[DELETED]") { return ("DELETED", .red) }
        if line.contains("[EXEMPT]") { return ("EXEMPT", .blue) }
        if line.contains("[GONE]") { return ("GONE", .gray) }
        if line.contains("[DRY]") { return ("DRY", .blue) }
        if line.contains("DONE") { return ("DONE", .green) }
        if line.contains("FORENSICS") { return ("REPORT", .purple) }
        return nil
    }
}
