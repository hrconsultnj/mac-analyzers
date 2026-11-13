import AppKit
import AnalyzersKit
import SwiftUI
import UIComponents

/// One run's screen, pushed from Activity, the toolbar status item, a finish
/// notification or a link. It is a data screen: the run's name and its one-line outcome
/// in the toolbar, then
///
///  - what happened: a line of facts (when, how long, who started it, how it ended);
///  - while it runs: the step, Stop, and the live output filling the screen;
///  - a waiting preview: "Review and Apply", which opens that task's screen;
///  - the results: the task's own results view if its group supplied one
///    (`SidebarGroup.runResults`), otherwise `RunResultsDefault`: the run's categories as
///    tabs (with counts) and, inside, its rows grouped under what they belong to, in the
///    shared read-only review table;
///  - in the toolbar: Open <Task>, Copy Details and Show Raw Output (one level down).
///
/// Nothing here opens another app.
struct ActivityInspector: View {
    let row: ActivityRow?
    let model: ActivityModel

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var outcome: ActivityOutcome?
    @State private var tab = RunTab(rawValue: "")

    var body: some View {
        if let row {
            screen(for: row)
        } else {
            ContentUnavailableView("Select a Run", systemImage: "list.bullet.rectangle",
                                   description: Text("Pick a run to see what it did."))
        }
    }

    private func job(for row: ActivityRow) -> Job? {
        row.jobID.flatMap { id in store.jobs.first { $0.id == id } }
    }

    private func screen(for row: ActivityRow) -> some View {
        let live = job(for: row)
        let sections = outcome?.sections.filter { !$0.items.isEmpty } ?? []
        let tabs = sections.map { RunTab(section: $0) }
        let current = tabs.contains(tab) ? tab : (tabs.first ?? tab)
        return DataScreen(title: row.title,
                          subtitle: [row.kindOfRun, statusSentence(row, live: live)].compactMap { $0 }.joined(separator: " · ")) {
            VStack(alignment: .leading, spacing: 0) {
                facts(row).padding([.horizontal, .top]).padding(.bottom, Tokens.Space.m)
                banners(row, live: live)
                results(row, live: live, sections: sections, current: current)
            }
            // a run's facts start at the top whatever is under them (a running job's box is shorter than the window);
            // only an empty state is centred, and it centres itself inside what is left
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .modifier(RunTabsModifier(row: row, tabs: tabs, sections: sections, selection: $tab))
        .toolbar { actions(row, live: live) }
        .task(id: loadKey(row, live: live)) { await loadOutcome(row, live: live) }
    }

    // MARK: - what happened

    /// The sentence in the toolbar's subtitle: what happened, in words.
    private func statusSentence(_ row: ActivityRow, live: Job?) -> String {
        if let live, live.isActive {
            return live.state.isQueuedOnly ? "Waiting for the running job to finish." : (live.step ?? "Working…")
        }
        return row.line
    }

    private func facts(_ row: ActivityRow) -> some View {
        HStack(spacing: Tokens.Space.xl) {
            if row.started != nil {
                Label {
                    if row.status == .running, let started = row.started {
                        Text(started, style: .timer).monospacedDigit()
                    } else {
                        Text(row.started?.formatted(date: .abbreviated, time: .shortened) ?? "")
                    }
                } icon: { Image(systemName: "clock") }
                    .help(row.exactTime)
            }
            if let took = row.durationText {
                Label("Took \(took)", systemImage: "timer")
            }
            if let startedBy = row.startedBy { Label(startedBy, systemImage: "person") }
            Label(row.status == .none ? "Hasn't run yet" : row.needsReview ? "Waiting for your review" : row.status.rawValue,
                  systemImage: row.glyph.symbol)
        }
        .font(Tokens.Typography.caption)
        .foregroundStyle(row.isFailed ? Tokens.Status.destructive.tint : .secondary)
        .labelStyle(.titleAndIcon)
    }

    // MARK: - banners: a waiting preview, results that were lost

    @ViewBuilder private func banners(_ row: ActivityRow, live: Job?) -> some View {
        if let live, live.isActive {
            EmptyView()
        } else if row.needsReview || (row.intent == .preview && row.findings > 0) {
            review(row).padding(.horizontal).padding(.bottom, Tokens.Space.m)
        } else if lostItsResults(live) {
            lostResults(row, reason: live?.note).padding(.horizontal).padding(.bottom, Tokens.Space.m)
        }
    }

    private func review(_ row: ActivityRow) -> some View {
        // waiting only while the app can apply it; an older preview is what it found
        GroupBox {
            HStack(spacing: Tokens.Space.xl) {
                Image(systemName: row.needsReview ? "eye.fill" : "arrow.clockwise")
                    .foregroundStyle(row.needsReview ? Tokens.Status.caution.tint : .secondary)
                Text(row.needsReview
                     ? "This preview found something and nothing has been changed yet. Review it, untick anything you want kept, then apply."
                     : "This preview found something, but it can't be applied as it stands: it is older than \(Int(JobStore.reviewWindow / 60)) minutes, or it was discarded, or it wasn't started from this app. Preview again to see what would be cleaned now.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tokens.Space.xl)
                if let target = row.reviewTarget {
                    Button(row.needsReview ? "Review and Apply" : Names.Review.previewAgain) { navigator.open(target: target) }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    /// A finished job whose own block the log did not hold: nothing here may be
    /// read as its result, and nothing built from it may be applied.
    private func lostItsResults(_ live: Job?) -> Bool {
        guard let live, case .succeeded(let finished) = live.state,
              case .newestFallback = finished.match else { return false }
        return true
    }

    private func lostResults(_ row: ActivityRow, reason: String?) -> some View {
        GroupBox {
            HStack(spacing: Tokens.Space.xl) {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                Text("This run finished, but \(Self.lostSentence(reason)) Nothing from it is shown or can be applied. Preview again to see what would be cleaned now.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tokens.Space.xl)
                if let target = row.reviewTarget {
                    Button(Names.Review.previewAgain) { navigator.open(target: target) }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    /// The kernel's reason a run's results are not shown, as the tail of a sentence.
    private static func lostSentence(_ reason: String?) -> String {
        switch reason {
        case RunMatcher.Reason.tooLarge: "its results are too large to review (more than 32 MB of log)."
        default: "its own results couldn't be found in the log."
        }
    }

    // MARK: - the results

    @ViewBuilder private func results(_ row: ActivityRow, live: Job?, sections: [ActivityOutcome.Section],
                                      current: RunTab) -> some View {
        if let live, live.isActive {
            running(live).padding([.horizontal, .bottom])
        } else if let slot = SectionRegistry.runResults(for: row) {
            slot(row)
        } else if let section = sections.first(where: { RunTab(section: $0) == current }) {
            RunResultsDefault(section: section, screen: "run.\(row.kind?.rawValue ?? row.log?.rawValue ?? "other")").id(section.id)
        } else if outcome == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Details Were Recorded", systemImage: "text.alignleft",
                                   description: Text("Show Raw Output has the text this run left."))
        }
    }

    /// The step line, Stop and the quit note sit on the screen; the output below them is the one boxed thing
    /// (`LiveOutputView`'s own `GroupBox`), not a card inside a card.
    private func running(_ job: Job) -> some View {
        VStack(alignment: .leading) {
            HStack {
                ProgressView().controlSize(.small)
                Text(job.step ?? "Working…").font(Tokens.Typography.rowTitleKey)
                Spacer()
                Button("Stop", role: .destructive) { job.cancel() }
            }
            Text("If you quit Mac Analyzers while this runs, you will be asked whether to stop it or let it finish in the background.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
            LiveOutputView(job: job)
        }
    }

    // MARK: - actions

    @ToolbarContentBuilder private func actions(_ row: ActivityRow, live: Job?) -> some ToolbarContent {
        ToolbarItemGroup {
            if let target = row.ownerTarget {
                Button("Open \(row.title)", systemImage: "arrow.up.forward.square") { navigator.open(target: target) }
            }
            Button("Copy Details", systemImage: "doc.on.doc") {
                ActivityDetails.copy(row, lines: live?.lines ?? model.lines(for: row))
            }
            if (live != nil || !model.lines(for: row).isEmpty), !(live?.isActive ?? false) {
                Button("Show Raw Output", systemImage: "text.alignleft") {
                    RunRowActions(store: store, navigator: navigator, model: model).showRaw(row)
                }
            }
        }
    }

    // MARK: - loading the outcome

    private func loadKey(_ row: ActivityRow, live: Job?) -> String {
        "\(row.id)|\(JobStamp(live).stage.map { String($0.rawValue) } ?? "-")|\(model.rows.count)"
    }

    /// Parses off the main thread: a janitor preview can hold thousands of rows.
    private func loadOutcome(_ row: ActivityRow, live: Job?) async {
        let log = row.log
        let known: JobOutcome.Parsed?
        let chosenRun: LogRun?
        if let live, case .succeeded(let finished) = live.state {
            // this job's own block was not in the log: nothing here is its result
            if case .newestFallback = finished.match { outcome = ActivityOutcome(sections: []); return }
            known = finished.parsed
            chosenRun = finished.run
        } else if let logged = model.logRun(for: row) {
            known = nil
            // the oldest block in the log's window may be cut off by it: read that one whole
            chosenRun = model.cutByWindow(logged, of: row) ? await Self.wholeRun(of: logged, in: log) : logged
        } else {
            outcome = ActivityOutcome(sections: [])
            return
        }
        outcome = await Task.detached(priority: .userInitiated) {
            // the task's own parser already read it, or the run came from a log and is read now
            if let known, !isNone(known) { return ActivityOutcome.make(known, run: chosenRun, log: log) }
            if let chosenRun, let log {
                return ActivityOutcome.make(ActivitySummary.parse(chosenRun, in: log), run: chosenRun, log: log)
            }
            return ActivityOutcome.make(JobOutcome.Parsed.none, run: chosenRun, log: log)
        }.value
    }

    /// The run read from its own banner back, when the window cut it off; the
    /// windowed run when that finds nothing better.
    private static func wholeRun(of run: LogRun, in log: EngineLog?) async -> LogRun {
        guard let url = log?.url, let banner = run.header.components(separatedBy: " · ").first else { return run }
        let found = await Task.detached(priority: .userInitiated) { WholeRun.find(banner: banner, in: url) }.value
        if case .block(let block) = found { return LogRun(id: run.id, header: run.header, lines: block.lines) }
        return run
    }
}

private func isNone(_ parsed: JobOutcome.Parsed?) -> Bool {
    if case .none? = parsed { return true }
    return false
}

private extension Job.State {
    var isQueuedOnly: Bool { if case .queued = self { true } else { false } }
}

/// A finished run's lines from its log, monospaced like live output.
struct RunLinesView: View {
    let lines: [String]
    /// Opens at the newest line (raw output); a run's own lines keep their top.
    var anchorBottom = false

    var body: some View {
        if lines.isEmpty {
            Text("No output was kept for this run.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            // Full-screen lines: a plain scroll view with the screen's own margin. A box that fills the whole
            // screen is not a box (`LiveOutputView` keeps its `GroupBox`: there the output sits under other
            // content and the box marks it).
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
                .padding()
            }
            .defaultScrollAnchor(anchorBottom ? .bottom : .top)
        }
    }
}

/// Copy Details: the run as text, for a message or a bug report.
enum ActivityDetails {
    @MainActor static func copy(_ row: ActivityRow, lines: [String]) {
        var text = "\(row.displayTitle)\n\(row.line)"
        if let startedBy = row.startedBy { text += "\n\(startedBy)" }
        if row.started != nil { text += " · \(row.exactTime)" }
        if let took = row.durationText { text += " · took \(took)" }
        if !lines.isEmpty { text += "\n\n" + lines.joined(separator: "\n") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
