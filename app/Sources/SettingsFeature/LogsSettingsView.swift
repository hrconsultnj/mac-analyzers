import SwiftUI
import AnalyzersKit
import UIComponents

/// One log's pane (pushed from the Logs landing screen or a sidebar child),
/// on the shared PaneScaffold — parsed into RUN blocks (newest run first,
/// lines in natural order inside each run) instead of a raw text dump.
/// TextEdit stays as the escape hatch for the untouched file.
struct LogsSettingsView: View {

    private struct LogRun: Identifiable {
        let id: Int
        let header: String
        let lines: [String]
    }

    let kind: LogKind
    @State private var runs: [LogRun] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaneScaffold(symbol: kind.symbol, color: kind.tileColor, title: kind.title,
                     caption: "Newest entries first — the file itself is never modified.") {
            Section {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("All Logs", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    if let url = kind.url {
                        Text(mtime(url)).font(.caption).foregroundStyle(.secondary)
                        Button("Open in TextEdit") { GuardControl.openLog(url) }
                        Button {
                            load()
                        } label: { Image(systemName: "arrow.clockwise") }
                            .help("Refresh")
                    }
                }
            }
            if runs.isEmpty {
                Section {
                    Text("Nothing logged yet — this log appears after its first run.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(runs) { run in
                Section {
                    ForEach(Array(run.lines.enumerated()), id: \.offset) { _, line in
                        row(for: line)
                    }
                } header: {
                    Text(run.header)
                        .font(.callout.weight(.semibold))
                }
            }
        }
        // our in-content "All Logs" button is the back affordance; the
        // native chevron rendered as an awkward floating glass circle here
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: load)
        .onChange(of: kind) { load() }
    }

    // MARK: - row rendering

    @ViewBuilder private func row(for line: String) -> some View {
        if line.hasPrefix("### ") {
            Text(line.dropFirst(4))
                .font(.caption.weight(.semibold))
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
