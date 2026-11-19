import SwiftUI
import AnalyzersKit

/// A group Stop with more than one program in it: every separate program is
/// listed, each with its own tick, so nothing is ended that was not chosen.
/// A lock guards only what Sparehold does by itself: programs of a live coding session
/// are listed with the reason, tickable like any other, and stopped only when the person ticks them.
/// What no one of this account can stop (another account's, a terminal session) is listed with its reason.
struct MonitorStopSheet: View {
    let group: String
    let programs: [StopTarget]
    let onCancel: () -> Void
    let onStop: ([StopTarget]) -> Void

    /// Nothing is ticked to begin with: ending several programs at once is a
    /// choice, not the default.
    @State private var ticked: Set<String>
    /// What stopping each program would reach (and, if it would be refused, why), worked out when
    /// the sheet opens: the rows say it before anything is chosen.
    @State private var reach: [String: String] = [:]

    init(group: String, programs: [StopTarget], preticked: Set<String> = [],
         onCancel: @escaping () -> Void, onStop: @escaping ([StopTarget]) -> Void) {
        self.group = group
        self.programs = programs
        self.onCancel = onCancel
        self.onStop = onStop
        _ticked = State(initialValue: preticked)
    }

    private var stoppable: [StopTarget] { programs.filter(\.isStoppableByPerson) }
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

            if let held = chosenProtection {
                Label(held, systemImage: "lock.fill")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
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
            for program in programs where program.isStoppableByPerson {
                if let text = MemoryStop.reachText(of: program, asPerson: true) { reach[program.id] = text }
            }
        }
    }

    /// What is said, above the button, when the ticked programs include ones Sparehold never stops by itself.
    private var chosenProtection: String? {
        let held = chosen.filter { $0.protection != nil }
        guard !held.isEmpty else { return nil }
        let which = held.count == 1 ? "One of these programs is" : "\(held.count) of these programs are"
        if !CodingAgentHosts.isAvailable {
            return "\(which) protected because Sparehold could not read its list of coding agents, so it cannot tell whether a live coding session is part of them. Any that is ends with them."
        }
        return "\(which) part of, or host, a live coding session. Sparehold never stops them by itself; stopping them here ends the session and loses any work in it that is not saved."
    }

    private var stopTitle: String {
        chosen.isEmpty ? "Stop" : "Stop \(chosen.count) \(chosen.count == 1 ? "Program" : "Programs")"
    }

    @ViewBuilder private func row(_ program: StopTarget) -> some View {
        if program.isStoppableByPerson {
            Toggle(isOn: Binding(get: { ticked.contains(program.id) },
                                 set: { if $0 { ticked.insert(program.id) } else { ticked.remove(program.id) } })) {
                HStack {
                    label(program)
                    if let held = program.protection {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary).help(held)
                    }
                    Spacer()
                    Text(program.totalText).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } else {
            HStack {
                Image(systemName: "nosign").foregroundStyle(.secondary)
                label(program)
                Spacer()
                Text(program.personRefusal ?? "").font(.caption).foregroundStyle(.secondary)
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
