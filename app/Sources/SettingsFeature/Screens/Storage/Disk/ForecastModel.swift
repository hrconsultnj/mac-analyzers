import Foundation
import AnalyzersKit

/// The Disk runway, for the Overview's health report and home screen. The arithmetic and the
/// whole-log read live in `DiskRunway` (AnalyzersKit), where a probe can print it.
enum ForecastModel {

    struct Runway {
        let daysToFull: Double
        var text: String { DiskRunway(daysToFull: daysToFull, points: 0).text }
        var urgent: Bool { daysToFull < 30 }
    }

    static func diskRunway() -> Runway? {
        DiskRunway.current().map { Runway(daysToFull: $0.daysToFull) }
    }
}
