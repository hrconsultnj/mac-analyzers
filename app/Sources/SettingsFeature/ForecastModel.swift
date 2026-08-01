import Foundation
import AnalyzersKit

/// Disk-runway forecast from the storage log's own "Free space now" series —
/// a least-squares line through (date, freeGiB). Honest thresholds: no
/// forecast until ≥5 points spanning ≥7 days, and only when the trend is
/// actually downward.
enum ForecastModel {

    struct Runway {
        let daysToFull: Double
        var text: String {
            daysToFull > 42 ? "~\(Int((daysToFull / 7).rounded())) weeks"
                            : "~\(Int(daysToFull.rounded())) days"
        }
        var urgent: Bool { daysToFull < 30 }
    }

    private static let headerDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func diskRunway() -> Runway? {
        var points: [(t: Double, freeGiB: Double)] = []
        for run in LogParser.runs(for: .storageClean) {
            guard let date = headerDate.date(from: String(run.header.prefix(16))),
                  let line = run.lines.first(where: { $0.contains("Free space now:") }),
                  let range = line.range(of: #"([\d.]+)Gi"#, options: .regularExpression),
                  let gib = Double(line[range].dropLast(2))
            else { continue }
            points.append((date.timeIntervalSince1970 / 86_400, gib))
        }
        guard points.count >= 5,
              let minT = points.map(\.t).min(),
              let maxT = points.map(\.t).max(),
              maxT - minT >= 7
        else { return nil }

        // least squares over (day, freeGiB)
        let n = Double(points.count)
        let sumT = points.map(\.t).reduce(0, +)
        let sumF = points.map(\.freeGiB).reduce(0, +)
        let sumTF = points.map { $0.t * $0.freeGiB }.reduce(0, +)
        let sumTT = points.map { $0.t * $0.t }.reduce(0, +)
        let denom = n * sumTT - sumT * sumT
        guard denom != 0 else { return nil }
        let slope = (n * sumTF - sumT * sumF) / denom      // GiB per day
        guard slope < -0.01 else { return nil }             // flat/up = no story

        let latestFree = points.max(by: { $0.t < $1.t })!.freeGiB
        let days = latestFree / abs(slope)
        guard days.isFinite, days > 0 else { return nil }
        return Runway(daysToFull: days)
    }
}
