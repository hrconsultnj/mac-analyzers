import AppKit
import AnalyzersKit
import SwiftUI
import UIComponents

/// The side panel for one Activity row, and the body of the pushed job screen.
///
/// A running job shows its output as it arrives and can be stopped. A finished
/// one shows the result the task's own parser read, what to do next, and the
/// output it printed. A run nobody tracked in this app (the schedule's, or
/// Terminal's) shows the lines its log holds.
struct ActivityInspector: View {
    let row: ActivityRow?
    let model: ActivityModel

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if let row {
            content(for: row)
        } else {
            ContentUnavailableView("Select a run", systemImage: "list.bullet.rectangle",
                                   description: Text("Pick a row to see its output and what it found."))
        }
    }

    private func job(for row: ActivityRow) -> Job? {
        row.jobID.flatMap { id in store.jobs.first { $0.id == id } }
    }

    @ViewBuilder private func content(for row: ActivityRow) -> some View {
        let live = job(for: row)
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            header(row)
            if let live {
                JobStatusView(job: live)
            } else {
                resultLine(row)
            }
            if let live, live.state.isFinished || live.isActive {
                if let note = live.note {
                    Label(note, systemImage: "info.circle")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            actions(row, live: live)
            if let live {
                LiveOutputView(job: live)
                    .frame(maxHeight: .infinity)
            } else {
                RunLinesView(lines: model.lines(for: row))
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(Tokens.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ row: ActivityRow) -> some View {
        HStack(spacing: Tokens.Space.m) {
            IconTile(symbol: row.symbol, color: row.tint, side: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.headline)
                Text(subtitle(row))
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func subtitle(_ row: ActivityRow) -> String {
        var parts = [row.trigger == .you ? "Started by you" : "Started by \(row.trigger.rawValue.lowercased())"]
        if let started = row.started {
            parts.append(started.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
        }
        return parts.joined(separator: " · ")
    }

    /// For a run with no live job: the result as the table shows it.
    private func resultLine(_ row: ActivityRow) -> some View {
        Label(row.result, systemImage: row.isFailed ? "exclamationmark.triangle.fill"
                                   : row.status == .stopped ? "stop.circle.fill" : "checkmark.circle.fill")
            .foregroundStyle(row.isFailed ? Tokens.Status.caution.tint : .primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func actions(_ row: ActivityRow, live: Job?) -> some View {
        HStack {
            if let target = row.ownerTarget {
                Button("Open \(row.title)") { navigator.open(target: target) }
            }
            Button("Copy Details") { copy(row, live: live) }
            if let url = row.log?.url {
                Button("Show Raw Log") { GuardControl.openLog(url) }
            }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
    }

    private func copy(_ row: ActivityRow, live: Job?) {
        let lines = live?.lines ?? model.lines(for: row)
        var text = "\(row.title) — \(subtitle(row))\n\(row.result)"
        if let header = row.header { text += "\n\(header)" }
        if !lines.isEmpty { text += "\n\n" + lines.joined(separator: "\n") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// A finished run's lines from its log, monospaced like live output.
struct RunLinesView: View {
    let lines: [String]

    var body: some View {
        if lines.isEmpty {
            Text("No output was kept for this run.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(Tokens.Typography.mono)
                            .foregroundStyle(line.hasPrefix("### ") ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(Tokens.Space.m)
            }
            .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
        }
    }
}
