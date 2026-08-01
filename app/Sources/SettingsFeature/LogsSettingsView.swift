import SwiftUI
import AnalyzersKit

/// Logs tab: every suite log behind icon segments (no dropdown), rendered
/// natively — parsed into RUN blocks (newest run first, lines in natural
/// order inside each run) instead of a raw text dump. TextEdit stays as the
/// escape hatch for the untouched file.
struct LogsSettingsView: View {

    private enum LogKind: String, CaseIterable, Identifiable {
        case guardLog, memoryClean, reclaim, storageClean, loginItems, forensics
        var id: String { rawValue }

        var title: String {
            switch self {
            case .guardLog: "Memory Guard"
            case .memoryClean: "Memory Auto-Clean"
            case .reclaim: "Memory Reclaim"
            case .storageClean: "Storage Auto-Clean"
            case .loginItems: "Login-Items Audit"
            case .forensics: "Forensics"
            }
        }

        var symbol: String {
            switch self {
            case .guardLog: "shield.lefthalf.filled"
            case .memoryClean: "memorychip"
            case .reclaim: "arrow.counterclockwise.circle"
            case .storageClean: "internaldrive"
            case .loginItems: "person.crop.circle.badge.questionmark"
            case .forensics: "stethoscope"
            }
        }

        var url: URL? {
            switch self {
            case .guardLog: AnalyzersPaths.guardLog
            case .memoryClean: AnalyzersPaths.memoryAutoCleanLog
            case .reclaim: AnalyzersPaths.reclaimLog
            case .storageClean: AnalyzersPaths.storageAutoCleanLog
            case .loginItems: AnalyzersPaths.loginItemsAuditLog
            case .forensics: AnalyzersPaths.latestForensics()
            }
        }
    }

    private struct LogRun: Identifiable {
        let id: Int
        let header: String
        let lines: [String]
    }

    @State private var kind: LogKind = .guardLog
    @State private var runs: [LogRun] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: $kind) {
                    ForEach(LogKind.allCases) { k in
                        Image(systemName: k.symbol).tag(k).help(k.title)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Spacer()
            }

            HStack {
                Label(kind.title, systemImage: kind.symbol)
                    .font(.headline)
                Text("newest first")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let url = kind.url {
                    Text(mtime(url)).font(.caption).foregroundStyle(.secondary)
                    Button("Open in TextEdit") { GuardControl.openLog(url) }
                        .controlSize(.small)
                    Button {
                        load()
                    } label: { Image(systemName: "arrow.clockwise") }
                        .controlSize(.small)
                }
            }

            if runs.isEmpty {
                ContentUnavailableView("Nothing logged yet",
                                       systemImage: kind.symbol,
                                       description: Text("This log appears after its first run."))
            } else {
                List {
                    ForEach(runs) { run in
                        Section {
                            ForEach(Array(run.lines.enumerated()), id: \.offset) { _, line in
                                row(for: line)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 8))
                            }
                        } header: {
                            Text(run.header)
                                .font(.callout.weight(.semibold))
                        }
                    }
                }
            }
        }
        .padding(12)
        .onAppear(perform: load)
        .onChange(of: kind) { load() }
    }

    // MARK: - row rendering

    @ViewBuilder private func row(for line: String) -> some View {
        if line.hasPrefix("### ") {
            Text(line.dropFirst(4))
                .font(.caption.weight(.semibold))
                .padding(.top, 4)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let badge = badge(for: line) {
                    Text(badge.text)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(badge.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(badge.color)
                }
                Text(cleaned(line))
                    .font(.caption.monospaced())
                    .foregroundStyle(badge(for: line) == nil ? .secondary : .primary)
                    .lineLimit(2)
            }
        }
    }

    private func badge(for line: String) -> (text: String, color: Color)? {
        if line.contains(" KILLED ") { return ("KILLED", .red) }
        if line.contains("CRITICAL") { return ("CRITICAL", .red) }
        if line.contains(" SPIKE ") { return ("SPIKE", .orange) }
        if line.contains("WARNING") { return ("WARN", .orange) }
        if line.contains("CAP-EXCEEDED") { return ("OVER CAP", .orange) }
        if line.contains("[KILLED]") || line.contains("[QUIT]") { return ("CLOSED", .red) }
        if line.contains("[DRY]") { return ("DRY", .blue) }
        if line.contains("DONE") { return ("DONE", .green) }
        if line.contains("FORENSICS") { return ("REPORT", .purple) }
        return nil
    }

    private func cleaned(_ line: String) -> String {
        line.replacingOccurrences(of: "[DRY]", with: "")
            .replacingOccurrences(of: "[KILLED]", with: "")
            .replacingOccurrences(of: "[QUIT]", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - parsing

    private func load() {
        guard let url = kind.url,
              let handle = try? FileHandle(forReadingFrom: url) else {
            runs = []
            return
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 131_072
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else {
            runs = []
            return
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        runs = text.contains("====")
            ? parseRunBlocks(lines)
            : parseDayGroups(lines)
    }

    /// Report-style logs: runs delimited by ===== separators; the first
    /// content line of each block is its header. Newest run first.
    private func parseRunBlocks(_ lines: [String]) -> [LogRun] {
        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines {
            if line.allSatisfy({ $0 == "=" }) {
                if !current.isEmpty { blocks.append(current); current = [] }
                continue
            }
            current.append(line)
        }
        if !current.isEmpty { blocks.append(current) }

        // pair header blocks ("memory-reclaim | DRY RUN | date" style one-liners)
        // with the body that follows; then newest first
        var result: [LogRun] = []
        var pendingHeader: String?
        for block in blocks {
            if block.count <= 2, let first = block.first, first.contains("|") {
                pendingHeader = block.joined(separator: " · ")
                continue
            }
            let header = pendingHeader ?? block.first ?? "Run"
            let body = pendingHeader == nil ? Array(block.dropFirst()) : block
            result.append(LogRun(id: result.count, header: header, lines: body))
            pendingHeader = nil
        }
        return result.reversed().prefix(12).map { $0 }
    }

    /// Event-style logs (guard): one line per event — group by day, newest
    /// day first, newest line first inside the day.
    private func parseDayGroups(_ lines: [String]) -> [LogRun] {
        var byDay: [(day: String, lines: [String])] = []
        for line in lines.suffix(400) {
            let day = String(line.prefix(10))
            if byDay.last?.day == day {
                byDay[byDay.count - 1].lines.append(line)
            } else {
                byDay.append((day, [line]))
            }
        }
        return byDay.reversed().enumerated().map { index, group in
            LogRun(id: index, header: group.day, lines: group.lines.reversed())
        }
    }

    private func mtime(_ url: URL) -> String {
        AnalyzersPaths.modificationDate(of: url)
            .map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) } ?? ""
    }
}
