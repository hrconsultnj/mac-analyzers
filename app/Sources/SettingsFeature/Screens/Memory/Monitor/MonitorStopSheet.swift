import SwiftUI
import AnalyzersKit

/// A group Stop with more than one program in it: every separate program is
/// listed, each with its own tick, so nothing is ended that was not chosen.
/// Programs that belong to a live coding-agent session are listed too, but
/// locked — they are never part of a group stop.
struct MonitorStopSheet: View {
    let group: String
    let programs: [StopTarget]
    let onCancel: () -> Void
    let onStop: ([StopTarget]) -> Void

    /// Nothing is ticked to begin with: ending several programs at once is a
    /// choice, not the default.
    @State private var ticked: Set<String> = []
    /// What stopping each program would reach (and, if it would be refused, why), worked out when
    /// the sheet opens: the rows say it before anything is chosen.
    @State private var reach: [String: String] = [:]

    private var stoppable: [StopTarget] { programs.filter(\.isStoppable) }
    private var chosen: [StopTarget] { stoppable.filter { ticked.contains($0.id) } }
    private var chosenBytes: Int64 { chosen.reduce(0) { $0 + $1.totalBytes } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stop \(group) Programs")
                    .font(.headline)
                Text("\(group) is \(programs.count) separate programs, not one. Choose the ones to stop.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            List {
                ForEach(programs) { program in
                    row(program)
                }
            }

            HStack {
                Button(Names.Review.selectAll) { ticked = Set(stoppable.map(\.id)) }
                    .disabled(stoppable.isEmpty || ticked.count == stoppable.count)
                Button(Names.Review.selectNone) { ticked = [] }
                    .disabled(ticked.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(stopTitle, role: .destructive) { onStop(chosen) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 360)
        .task {
            for program in programs where program.isStoppable {
                if let text = MemoryStop.reachText(of: program) { reach[program.id] = text }
            }
        }
    }

    private var stopTitle: String {
        chosen.isEmpty ? "Stop" : "Stop \(chosen.count) \(chosen.count == 1 ? "Program" : "Programs")"
    }

    @ViewBuilder private func row(_ program: StopTarget) -> some View {
        if let reason = program.lockedReason {
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                label(program)
                Spacer()
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        } else if program.isStoppable {
            Toggle(isOn: Binding(get: { ticked.contains(program.id) },
                                 set: { if $0 { ticked.insert(program.id) } else { ticked.remove(program.id) } })) {
                HStack { label(program); Spacer(); Text(program.totalText).foregroundStyle(.secondary).monospacedDigit() }
            }
        } else {
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                label(program)
                Spacer()
                Text("Belongs to another account").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func label(_ program: StopTarget) -> some View {
        VStack(alignment: .leading) {
            Text(MonitorTree.rowName(program.name))
            Text([[program.whereItRuns.map { "in \($0)" },
                   "\(program.members.count) \(program.members.count == 1 ? "process" : "processes")"]
                    .compactMap { $0 }.joined(separator: " · "),
                  reach[program.id]]
                .compactMap { $0 }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
