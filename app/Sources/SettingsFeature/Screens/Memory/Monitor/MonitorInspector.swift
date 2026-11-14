import SwiftUI
import AnalyzersKit
import UIComponents

/// The panel beside the table. With nothing selected it explains where the
/// memory is; with a row selected it says what that row is, what it is made
/// of, and offers its Stop or Quit.
struct MonitorInspector: View {
    let model: MonitorModel
    let row: MonitorRow?
    let begin: (MonitorStop) -> Void
    let showDetails: (MonitorRow) -> Void

    var body: some View {
        if let row {
            RowDetail(row: row, icon: model.icons[row.id], begin: begin, showDetails: showDetails)
        } else {
            MemoryExplained(model: model)
        }
    }
}

// MARK: - a selected row

private struct RowDetail: View {
    let row: MonitorRow
    let icon: NSImage?
    let begin: (MonitorStop) -> Void
    let showDetails: (MonitorRow) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Memory", value: row.memoryText)
                LabeledContent("CPU", value: row.cpuText)
                LabeledContent(row.processCount == 1 ? "Process" : "Processes",
                               value: row.pid.map { row.processCount == 1 ? "pid \($0)" : "\(row.processCount)" }
                                   ?? "\(row.processCount)")
                if !row.detail.isEmpty { LabeledContent("What it is", value: row.detail) }
                if let kind = row.processKind { LabeledContent(Names.Column.kind, value: kind.name) }
            } header: {
                HStack {
                    if let icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                    Text(row.name).font(.headline)
                }
            }
            if row.hasChildren {
                Section(row.kind == .group && row.category == .tools ? "Programs" : "Made Up of") {
                    ForEach(row.children.prefix(8)) { child in
                        LabeledContent {
                            Text(child.memoryText).monospacedDigit()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(child.name)
                                Text(child.detail.isEmpty
                                     ? "\(child.processCount) \(child.processCount == 1 ? "process" : "processes")"
                                     : child.detail)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if row.children.count > 8 {
                        Text("and \(row.children.count - 8) more")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                if let verb = row.stopVerb {
                    Button("\(verb) \(row.name)…") { begin(row.stop) }
                } else if let reason = row.lockedReason {
                    Label(reason, systemImage: "lock.fill").foregroundStyle(.secondary)
                }
                // something the person may stop, with a word of care: a Connection Tool, a background service
                if row.stopVerb != nil, let held = row.leftAlone {
                    Label(held, systemImage: "shield.lefthalf.filled").foregroundStyle(.secondary)
                }
                if row.pid != nil || row.iconPID != nil {
                    Button(Names.Monitor.showDetails) { showDetails(row) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - nothing selected: where memory is

private struct MemoryExplained: View {
    let model: MonitorModel
    @Environment(Navigator.self) private var navigator

    var body: some View {
        Form {
            if let memory = model.breakdown {
                Section(Names.Monitor.whereYourMemoryIs) {
                    legend(.app, .blue, memory.appBytes, "Held right now by the apps and processes in the table.")
                    legend(.wired, .indigo, memory.wiredBytes,
                           "macOS itself — the kernel, drivers and graphics. Can't be moved or squeezed.")
                    legend(.compressed, .purple, memory.compressedBytes,
                           "Idle memory macOS squeezed to make room — \(MemorySize.text(memory.compressedOriginalBytes, .figure)) of it packed into this.")
                    legend(.cached, .teal, memory.cachedBytes,
                           "Recently used files kept for speed. Not counted as in use — handed back the moment an app needs the room.")
                    legend(.free, nil, memory.freeBytes, "Untouched.")
                    if let swap = MemorySample.readSwap() {
                        legend(.swap, .brown, swap.used, "Memory macOS moved to the disk. Of \(MemorySize.text(swap.total, .figure)) of swap space.")
                    }
                }
            }
            Section {
                Text("A group's total counts compressed memory at its full size, so the groups add up to roughly App Memory plus what is packed inside Compressed."
                     + (model.unmeasured > 0
                        ? " \(model.unmeasured) processes could not be measured and count as zero."
                        : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("\(model.processCount.formatted()) processes are running")
            }
        }
        .formStyle(.grouped)
    }

    /// A row of the block: its figure, a sentence, and an arrow to the screen of its own.
    private func legend(_ kind: MemoryKind, _ color: Color?, _ bytes: Int64, _ explanation: String) -> some View {
        Button { navigator.push(.memory(.kind(kind))) } label: {
            LabeledContent {
                HStack(spacing: Tokens.Space.s) {
                    Text(MemorySize.text(bytes, .figure)).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            } label: {
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Circle().fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.quaternary))
                            .frame(width: Tokens.Icon.dot, height: Tokens.Icon.dot)
                            .accessibilityHidden(true)
                        Text(kind.title)
                    }
                    Text(explanation).font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a screen about \(kind.title)")
    }
}
