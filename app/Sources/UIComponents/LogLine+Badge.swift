import AnalyzersKit
import SwiftUI

/// Log line to badge: the label and colour a line earns (KILLED, DRY, DONE …).
extension LogParser {

    public static func badge(for line: String) -> (text: String, color: Color)? {
        if line.contains(" KILLED ") { return ("Killed", .red) }
        if line.contains("CRITICAL") { return ("Critical", .red) }
        if line.contains(" SPIKE ") { return ("Spike", .orange) }
        if line.contains("WARNING") { return ("Warning", .orange) }
        if line.contains("CAP-EXCEEDED") { return ("Over Cap", .orange) }
        if line.contains("[KILLED]") || line.contains("[QUIT]") { return ("Closed", .red) }
        if line.contains("[DELETED]") { return ("Deleted", .red) }
        if line.contains("[EXEMPT]") { return ("Exempt", .blue) }
        if line.contains("[GONE]") { return ("Gone", .gray) }
        if line.contains("[DRY]") { return ("Dry", .blue) }
        if line.contains("DONE") { return ("Done", .green) }
        if line.contains("FORENSICS") { return (Names.crisisReport, .purple) }
        return nil
    }
}
