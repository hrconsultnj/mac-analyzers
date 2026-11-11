import AnalyzersKit
import SwiftUI

/// How a guard event looks wherever it is listed: symbol, colour and badge.
/// One map for the menu, the Memory Guard log and the Trends drill-downs.
extension GuardEvent {

    public var symbol: String {
        switch kind {
        case .killed: "xmark.octagon.fill"
        case .stopFailed: "xmark.octagon"
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
        case .spike, .capExceeded, .pressureWarning, .warning, .stopFailed: .orange
        case .cpuHog, .forensics: .purple
        }
    }

    public var badge: (String, Color)? {
        switch kind {
        case .killed: ("Killed", .red)
        case .stopFailed: ("Not Stopped", .orange)
        case .spike: ("Spike", .orange)
        case .capExceeded: ("Over Cap", .orange)
        case .pressureWarning: ("Pressure", .orange)
        case .pressureCritical: ("Critical", .red)
        case .cpuHog: ("CPU", .purple)
        case .forensics: nil
        case .warning: ("Warning", .orange)
        }
    }
}
