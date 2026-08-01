import SwiftUI
import AnalyzersKit

/// Logs tab: every log the suite writes, with an inline NEWEST-FIRST viewer
/// (append-only files read oldest-first in an editor — here the latest line
/// is always on top) and an Open-in-TextEdit escape hatch.
struct LogsSettingsView: View {

    private struct LogFile: Identifiable, Hashable {
        let name: String
        let url: URL
        var id: String { url.path }
    }

    private var logs: [LogFile] {
        var list: [LogFile] = [
            .init(name: "Memory — guard", url: AnalyzersPaths.guardLog),
            .init(name: "Memory — auto-clean", url: AnalyzersPaths.memoryAutoCleanLog),
            .init(name: "Memory — reclaim", url: AnalyzersPaths.reclaimLog),
            .init(name: "Storage — auto-clean", url: AnalyzersPaths.storageAutoCleanLog),
            .init(name: "Storage — login-items audit", url: AnalyzersPaths.loginItemsAuditLog),
        ]
        if let forensics = AnalyzersPaths.latestForensics() {
            list.append(.init(name: "Latest forensics report", url: forensics))
        }
        return list.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    @State private var selected: LogFile?
    @State private var lines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Log", selection: $selected) {
                    ForEach(logs) { log in
                        Text(log.name).tag(Optional(log))
                    }
                }
                .frame(maxWidth: 280)
                Spacer()
                if let selected {
                    Text(mtime(selected.url))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open in TextEdit") { GuardControl.openLog(selected.url) }
                        .controlSize(.small)
                    Button {
                        load()
                    } label: { Image(systemName: "arrow.clockwise") }
                        .controlSize(.small)
                }
            }

            Text("Newest entries first.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            List(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(color(for: line))
                    .lineLimit(2)
                    .listRowSeparator(.hidden)
            }
        }
        .padding(12)
        .onAppear {
            if selected == nil { selected = logs.first }
            load()
        }
        .onChange(of: selected) { load() }
    }

    private func load() {
        guard let url = selected?.url,
              let handle = try? FileHandle(forReadingFrom: url) else {
            lines = []
            return
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 131_072
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else {
            lines = []
            return
        }
        lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(400)
            .reversed()
            .map(String.init)
    }

    private func color(for line: String) -> Color {
        if line.contains(" KILLED ") || line.contains("CRITICAL") { return .red }
        if line.contains(" SPIKE ") || line.contains("WARNING")
            || line.contains("CAP-EXCEEDED") { return .orange }
        return .primary
    }

    private func mtime(_ url: URL) -> String {
        AnalyzersPaths.modificationDate(of: url)
            .map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) } ?? ""
    }
}
