import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Login-Items Audit pane: verdict cards with per-row copyable remediation
/// commands — the wall of sudo one-liners becomes buttons.
struct LoginItemsView: View {

    private enum Filter: String, CaseIterable {
        case all = "All"
        case orphans = "Orphans"
        case needsSudo = "Needs Sudo"
        case leftover = "Leftover?"
        case skipped = "Skipped"
    }

    @State private var run: LoginItemsRun?
    @State private var filter: Filter = .all
    @State private var copiedID: String?

    var body: some View {
        PaneScaffold(symbol: "person.crop.circle.badge.questionmark", color: .brown,
                     title: "Login-Items Audit",
                     caption: "Launch agents and login items whose app is gone — with the exact removal command per row.") {
            Section {
                HStack {
                    FilterChipsBar(
                        chips: Filter.allCases.map { f in
                            .init(f, f.rawValue, count: count(f), color: chipColor(f))
                        },
                        selection: $filter
                    )
                    Spacer(minLength: 8)
                    Button("Open in TextEdit") { GuardControl.openLog(AnalyzersPaths.loginItemsAuditLog) }
                    Button {
                        load()
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                }
                if let run {
                    HStack(spacing: 6) {
                        BadgeCapsule(text: run.dryRun ? "DRY RUN" : "APPLIED",
                                     color: run.dryRun ? .blue : .green)
                        Text(run.header)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let run {
                if filteredSections(run).isEmpty {
                    Section {
                        Label("No orphaned login items — Login Items are clean.",
                              systemImage: "checkmark.shield")
                            .foregroundStyle(.green)
                    }
                }
                ForEach(filteredSections(run), id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            } else {
                Section {
                    Text("No audit run logged yet — it runs with the storage suite, or run login-items-audit.sh for a fresh pass.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - rows

    @ViewBuilder private func entryRow(_ entry: LoginItemEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            DataCard(symbol: symbol(for: entry.verdict), color: color(for: entry.verdict),
                     title: entry.displayName,
                     subtitle: subtitle(for: entry),
                     badge: (entry.verdict.rawValue, color(for: entry.verdict)))
            if let cmd = entry.sudoCommand {
                HStack(spacing: 6) {
                    Text(cmd)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                    Button(copiedID == entry.id ? "Copied ✓" : "Copy command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                        copiedID = entry.id
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 28)
            }
        }
    }

    private func subtitle(for entry: LoginItemEntry) -> String {
        var parts: [String] = [entry.label]
        if let note = entry.note { parts.append(note) }
        else if let target = entry.targetPath { parts.append(target) }
        else if let plist = entry.plistPath { parts.append(plist) }
        return parts.joined(separator: " · ")
    }

    // MARK: - filtering + styling

    private func matches(_ entry: LoginItemEntry, _ f: Filter) -> Bool {
        switch f {
        case .all: true
        case .orphans: entry.verdict == .orphan || entry.verdict == .removed
        case .needsSudo: entry.verdict == .orphanSudo
        case .leftover: entry.verdict == .leftover
        case .skipped: entry.verdict == .skip
        }
    }

    private func count(_ f: Filter) -> Int {
        run.map { $0.allEntries.filter { matches($0, f) }.count } ?? 0
    }

    private func filteredSections(_ run: LoginItemsRun)
        -> [(title: String, entries: [LoginItemEntry])] {
        run.sections
            .map { (title: $0.title, entries: $0.entries.filter { matches($0, filter) }) }
            .filter { !$0.entries.isEmpty }
    }

    private func chipColor(_ f: Filter) -> Color {
        switch f {
        case .all: .brown
        case .orphans: .red
        case .needsSudo: .orange
        case .leftover: .yellow
        case .skipped: .gray
        }
    }

    private func symbol(for verdict: LoginItemEntry.Verdict) -> String {
        switch verdict {
        case .orphan, .orphanSudo: "link.badge.plus"
        case .removed: "trash"
        case .leftover: "questionmark.folder"
        case .skip: "eye.slash"
        }
    }

    private func color(for verdict: LoginItemEntry.Verdict) -> Color {
        switch verdict {
        case .orphan: .red
        case .orphanSudo: .orange
        case .removed: .green
        case .leftover: .yellow
        case .skip: .gray
        }
    }

    private func load() {
        let runs = LogParser.runs(for: .loginItems)
        guard let newest = runs.first else {
            run = nil
            return
        }
        run = LoginItemsParser.parse(runHeader: newest.header, lines: newest.lines)
    }
}
