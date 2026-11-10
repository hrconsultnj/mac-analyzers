import AnalyzersKit
import SwiftUI

/// How a guard event looks wherever it is listed: symbol, colour and badge.
/// One map for the menu, the Memory Guard log and the Trends drill-downs.
extension GuardEvent {

    public var symbol: String {
        switch kind {
        case .killed: "xmark.octagon.fill"
        case .spike: "arrow.up.right"
        case .capExceeded: "gauge.with.needle"
        case .pressureWarning, .pressureCritical: "exclamationmark.triangle.fill"
        case .cpuHog: "cpu"
        case .forensics: "stethoscope"
        case .warning: "exclamationmark.triangle"
        }
    }

    public var tint: Color {
        switch kind {
        case .killed, .pressureCritical: .red
        case .spike, .capExceeded, .pressureWarning, .warning: .orange
        case .cpuHog, .forensics: .purple
        }
    }

    public var badge: (String, Color)? {
        switch kind {
        case .killed: ("KILLED", .red)
        case .spike: ("SPIKE", .orange)
        case .capExceeded: ("OVER CAP", .orange)
        case .pressureWarning: ("PRESSURE", .orange)
        case .pressureCritical: ("CRITICAL", .red)
        case .cpuHog: ("CPU", .purple)
        case .forensics: nil
        case .warning: ("WARN", .orange)
        }
    }
}
