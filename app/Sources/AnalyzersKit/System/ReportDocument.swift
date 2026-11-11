import Foundation

/// One report the analyzers wrote, named for a person: "Memory Report — Nov 10,
/// 9:30 AM", not `report-0930.md`.
public struct ReportDocument: Identifiable, Hashable, Sendable {

    public enum Kind: String, Sendable, CaseIterable, Identifiable {
        public var id: String { rawValue }

        case memory, storage

        public var title: String { self == .memory ? Names.Report.memory : Names.Report.storage }
        /// The tab: "Memory", "Storage".
        public var tabTitle: String { self == .memory ? Names.Group.memory : Names.Group.storage }
        public var symbol: String { self == .memory ? "memorychip" : "internaldrive" }
        public var jobKind: JobKind { self == .memory ? .memoryReport : .storageReport }
        var folder: URL { self == .memory ? AnalyzersPaths.memoryReports : AnalyzersPaths.storageReports }
    }

    public let kind: Kind
    public let url: URL
    /// When the report was written.
    public let date: Date
    public var id: String { url.path }

    public var title: String { kind.title }

    /// "Nov 10, 9:30 AM"
    public var whenWritten: String {
        "\(date.formatted(.dateTime.month(.abbreviated).day())), \(date.formatted(.dateTime.hour().minute()))"
    }

    /// "Memory Report — Nov 10, 9:30 AM"
    public var displayName: String {
        "\(title) — \(whenWritten)"
    }

    public var fileSize: Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }

    public func text() -> String? { try? String(contentsOf: url, encoding: .utf8) }
}

public enum ReportLibrary {

    /// Every report on disk, newest first. A report is `report-*.md` inside a
    /// dated folder; `latest.md` is only a link to one of them.
    public static func all() -> [ReportDocument] {
        let fm = FileManager.default
        var found: [ReportDocument] = []
        for kind in ReportDocument.Kind.allCases {
            guard let days = try? fm.contentsOfDirectory(
                at: kind.folder, includingPropertiesForKeys: nil) else { continue }
            for day in days where day.hasDirectoryPath {
                guard let files = try? fm.contentsOfDirectory(
                    at: day, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                for file in files where file.lastPathComponent.hasPrefix("report-")
                    && file.pathExtension == "md" {
                    let date = written(file: file, day: day)
                    found.append(ReportDocument(kind: kind, url: file, date: date))
                }
            }
        }
        return found.sorted { $0.date > $1.date }
    }

    /// The day comes from the folder, the time from the file name
    /// (`report-0930.md`, or the older `report-2026-05-07_1509.md`); the
    /// file's own modification time is the fallback.
    static func written(file: URL, day: URL) -> Date {
        let stem = file.deletingPathExtension().lastPathComponent
        let hhmm = stem.split(whereSeparator: { $0 == "-" || $0 == "_" }).last.map(String.init) ?? ""
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        if hhmm.count == 4,
           let date = formatter.date(from: "\(day.lastPathComponent) \(hhmm)") {
            return date
        }
        return (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}

/// One month's reports of a kind, with what they add up to.
public struct ReportMonth: Identifiable, Hashable, Sendable {
    public let date: Date
    public let reports: [ReportDocument]
    public var id: Date { date }
    public var totalBytes: Int64 { reports.reduce(0) { $0 + $1.fileSize } }
    public var summary: String {
        "\(reports.count) \(reports.count == 1 ? "report" : "reports") · \(ByteSize.format(totalBytes))"
    }

    /// Newest month first, each month newest report first.
    public static func months(of reports: [ReportDocument]) -> [ReportMonth] {
        let calendar = Calendar.current
        return Dictionary(grouping: reports) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        }
        .map { ReportMonth(date: $0.key, reports: $0.value.sorted { $0.date > $1.date }) }
        .sorted { $0.date > $1.date }
    }
}
