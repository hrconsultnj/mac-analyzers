import SwiftUI
import AnalyzersKit

/// One guard event on its own screen: what happened, the program it was about
/// (named, with the app or project, the memory it held at the time and
/// whether it is still running), what the guard did and why — and, for a
/// crisis report, what was using the memory, by app. The log's own lines are
/// one level down.
struct GuardEntryScreen: View {
    let id: String

    @State private var row: GuardHistory.Row?
    @State private var report: CrisisReportSummary?
    @State private var stillRunning: Bool?
    @State private var loaded = false

    var body: some View {
        Group {
            if let row {
                content(for: row)
            } else if loaded {
                EmptyState(Names.Guard.eventGone, systemImage: "clock.arrow.circlepath",
                                       description: Text("It has aged out of the log, so there is nothing more to show."))
            } else {
                LoadingState()
            }
        }
        .navigationTitle(row?.title ?? "Event")
        .task { await load() }
    }

    private func content(for row: GuardHistory.Row) -> some View {
        let lead = row.lead
        return Form {
            Section(Names.Guard.whatHappened) {
                LabeledContent("Event", value: row.title)
                LabeledContent("When", value: whenText(row))
                if row.isGroup {
                    LabeledContent("Times", value: "\(row.count) times")
                }
                Text(row.outcome).foregroundStyle(.secondary)
            }
            if lead.kind != .pressure, lead.kind != .crisisReport {
                Section(Names.Guard.theProgram) {
                    LabeledContent("Name", value: lead.subject)
                    if let project = lead.project { LabeledContent("Project", value: project) }
                    if let memory = lead.memoryText { LabeledContent("Memory at the time", value: memory) }
                    if let pid = lead.pid { LabeledContent("Process ID", value: String(pid)) }
                    if let stillRunning {
                        LabeledContent("Right now", value: stillRunning ? "Still running" : "Has ended")
                    }
                }
            }
            if let report {
                reportSections(report)
            }
            Section(Names.Guard.whyTheGuardDoesThis) {
                Text(lead.why).foregroundStyle(.secondary)
            }
            if row.isGroup {
                Section(Names.Guard.eachTime) {
                    ForEach(row.entries.reversed()) { entry in
                        LabeledContent(entry.date.formatted(date: .abbreviated, time: .standard),
                                       value: entry.memoryText ?? entry.cpuPercent.map { "above \($0)%" } ?? "")
                    }
                }
            }
            Section {
                // one disclosed block, not rows: the raw lines
                DisclosureGroup(Names.Guard.showRawLines) {
                    Text(row.rawText)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func reportSections(_ report: CrisisReportSummary) -> some View {
        Section(Names.Guard.whatWasUsingMemory) {
            Text(report.headline)
            ForEach(report.apps.prefix(10)) { app in
                LabeledContent {
                    Text(app.memoryText).monospacedDigit()
                } label: {
                    VStack(alignment: .leading) {
                        Text(app.name)
                        Text([app.processCount == 1 ? "1 process" : "\(app.processCount) processes",
                              app.agentSession.map { "part of a \($0) session" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if report.apps.count > 10 {
                Text("and \(report.apps.count - 10) more").foregroundStyle(.secondary)
            }
        }
        Section(Names.Guard.macAtThatMoment) {
            if let pressure = report.pressure { LabeledContent("Memory pressure", value: pressure) }
            if let memory = report.physicalMemory { LabeledContent("Physical memory", value: memory) }
            if let swap = report.swap { LabeledContent("Swap", value: swap) }
        }
    }

    private func whenText(_ row: GuardHistory.Row) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        return row.isGroup
            ? "\(row.start.formatted(style)) to \(row.end.formatted(style))"
            : row.start.formatted(style)
    }

    private func load() async {
        // the list's own read, shared: opening an entry does not read the log again. A group's id carries its first
        // entry's time, and a group that straddles the period's start begins later in a shorter read, so the entry is
        // looked up in the same period the list showed; a link from elsewhere (a notification, the panel) whose row
        // is not in that period falls back to the longest read.
        var found = await GuardHistoryModel.history(window: GuardHistoryModel.savedWindow())?.row(id: id)
        if found == nil {
            found = await GuardHistoryModel.history(days: GuardHistory.windowDays)?.row(id: id)
        }
        row = found
        report = found?.lead.reportPath.flatMap(CrisisReportSummary.read(path:))
        stillRunning = found?.lead.isStillRunning
        loaded = true
    }
}
