import AppKit
import AnalyzersKit
import SwiftUI
import UIComponents

/// One run's screen, pushed from Activity, the toolbar status item, a finish
/// notification or a link. It holds what the old inspector held and says it
/// the way a person reads it:
///
///  - a header: glyph, name, when, how long, who started it, how it ended;
///  - while it runs: what step it is on, Stop, and the live output;
///  - a waiting preview: "Review and apply", which opens that task's screen;
///  - the outcome as a list of things — what was freed, found or left alone;
///  - Open <Task>, Copy Details;
///  - the raw output, one level down, behind "Show raw output".
///
/// Nothing here opens another app: the raw output is shown in place.
struct ActivityInspector: View {
    let row: ActivityRow?
    let model: ActivityModel

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var outcome: ActivityOutcome?
    @State private var showRaw = false

    var body: some View {
        if let row {
            screen(for: row)
        } else {
            ContentUnavailableView("Select a run", systemImage: "list.bullet.rectangle",
                                   description: Text("Pick a run to see what it did."))
        }
    }

    private func job(for row: ActivityRow) -> Job? {
        row.jobID.flatMap { id in store.jobs.first { $0.id == id } }
    }

    @ViewBuilder private func screen(for row: ActivityRow) -> some View {
        let live = job(for: row)
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xxl) {
                header(row, live: live)
                if let live, live.isActive {
                    running(live)
                } else if row.needsReview || (row.intent == .preview && row.findings > 0) {
                    review(row)
                } else if lostItsResults(live) {
                    lostResults(row)
                }
                if let outcome, !outcome.isEmpty {
                    OutcomeList(outcome: outcome, waitingForReview: row.needsReview)
                }
                actions(row, live: live)
                rawOutput(row, live: live)
            }
            .padding(Tokens.Space.pane)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: loadKey(row, live: live)) { await loadOutcome(row, live: live) }
        .onAppear { showRaw = RawOutputRequest.claim(for: row.id) }
    }

    // MARK: - header

    private func header(_ row: ActivityRow, live: Job?) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.xxl) {
            GlyphTile(glyph: row.glyph, side: 52)
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text(row.displayTitle).font(Tokens.Typography.paneTitle)
                Text(statusSentence(row, live: live))
                    .font(.title3)
                    .foregroundStyle(row.isFailed ? Tokens.Status.destructive.tint : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                facts(row)
            }
            Spacer(minLength: 0)
        }
    }

    /// The sentence under the name: what happened, in words.
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
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    // MARK: - while it runs

    private func running(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
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
                .frame(height: 300)
        }
        .padding(Tokens.Space.xl)
        .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    // MARK: - a waiting preview

    private func review(_ row: ActivityRow) -> some View {
        // waiting only while the app can apply it; an older preview is what it found
        HStack(spacing: Tokens.Space.xl) {
            Image(systemName: row.needsReview ? "eye.fill" : "arrow.clockwise")
                .foregroundStyle(row.needsReview ? Tokens.Status.caution.tint : .secondary)
            Text(row.needsReview
                 ? "This preview found something and nothing has been changed yet. Review it, untick anything you want kept, then apply."
                 : "This preview found something, but it can't be applied as it stands: it is older than \(Int(JobStore.reviewWindow / 60)) minutes, or it was discarded, or it wasn't started from this app. Preview again to see what would be cleaned now.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tokens.Space.xl)
            if let target = row.reviewTarget {
                Button(row.needsReview ? "Review and apply" : "Preview again") { navigator.open(target: target) }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(Tokens.Space.xl)
        .background((row.needsReview ? Tokens.Status.caution.softFill : Color.primary.opacity(0.06)),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    /// A finished job whose own block the log did not hold: nothing here may be
    /// read as its result, and nothing built from it may be applied.
    private func lostItsResults(_ live: Job?) -> Bool {
        guard let live, case .succeeded(let finished) = live.state,
              case .newestFallback = finished.match else { return false }
        return true
    }

    private func lostResults(_ row: ActivityRow) -> some View {
        HStack(spacing: Tokens.Space.xl) {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            Text("This run finished, but its own results couldn't be found in the log, so there is nothing reliable to show or to apply. Preview again to see what would be cleaned now.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tokens.Space.xl)
            if let target = row.reviewTarget {
                Button("Preview again") { navigator.open(target: target) }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(Tokens.Space.xl)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    // MARK: - outcome

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
            if case .newestFallback = finished.match { outcome = nil; return }
            known = finished.parsed
            chosenRun = finished.run
        } else if let logged = model.logRun(for: row) {
            known = nil
            chosenRun = logged
        } else {
            outcome = nil
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

    // MARK: - actions

    private func actions(_ row: ActivityRow, live: Job?) -> some View {
        HStack {
            if let target = row.ownerTarget {
                Button("Open \(row.title)") { navigator.open(target: target) }
            }
            Button("Copy Details") { ActivityDetails.copy(row, lines: live?.lines ?? model.lines(for: row)) }
            Spacer(minLength: 0)
        }
    }

    // MARK: - raw output

    @ViewBuilder private func rawOutput(_ row: ActivityRow, live: Job?) -> some View {
        let lines = live?.lines ?? model.lines(for: row)
        if live != nil || !lines.isEmpty, !(live?.isActive ?? false) {
            DisclosureGroup("Show raw output", isExpanded: $showRaw) {
                Group {
                    if let live { LiveOutputView(job: live) } else { RunLinesView(lines: lines) }
                }
                .frame(height: 320)
                .padding(.top, Tokens.Space.s)
            }
            .font(Tokens.Typography.rowTitleKey)
        }
    }
}

private func isNone(_ parsed: JobOutcome.Parsed?) -> Bool {
    if case .none? = parsed { return true }
    return false
}

private extension Job.State {
    var isQueuedOnly: Bool { if case .queued = self { true } else { false } }
}

// MARK: - the outcome as a list

/// What a run freed, found or left alone: typed rows, never log lines.
struct OutcomeList: View {
    let outcome: ActivityOutcome
    /// Only a preview still waiting for review uses the orange review eye; an older
    /// one lists what it found under a plain magnifier.
    var waitingForReview = true

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxl) {
            ForEach(outcome.sections) { section in
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    HStack(spacing: Tokens.Space.s) {
                        Image(systemName: symbol(section.tone))
                            .foregroundStyle(tint(section.tone))
                        Text(section.title).font(Tokens.Typography.sectionTitle)
                        Text("\(section.items.count + section.hidden)")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(section.items) { item in
                            row(item)
                            if item.id != section.items.last?.id || section.hidden > 0 { Divider() }
                        }
                        if section.hidden > 0 {
                            Text("and \(section.hidden) more")
                                .font(Tokens.Typography.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, Tokens.Space.m)
                                .padding(.horizontal, Tokens.Space.xl)
                        }
                    }
                    .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
                }
            }
        }
    }

    private func row(_ item: ActivityOutcome.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xl) {
            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                Text(item.title).font(Tokens.Typography.rowTitle).lineLimit(1).truncationMode(.middle)
                if let detail = item.detail {
                    Text(detail).font(Tokens.Typography.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: Tokens.Space.xl)
            if let trailing = item.trailing {
                Text(trailing).font(Tokens.Typography.value).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Tokens.Space.m)
        .padding(.horizontal, Tokens.Space.xl)
        .help(item.detail ?? item.title)
    }

    private func symbol(_ tone: ActivityOutcome.Tone) -> String {
        switch tone {
        case .done: "checkmark.circle.fill"
        case .found: waitingForReview ? "eye.fill" : "magnifyingglass"
        case .alert: "exclamationmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func tint(_ tone: ActivityOutcome.Tone) -> Color {
        switch tone {
        case .done: Tokens.Status.safe.tint
        case .found: waitingForReview ? Tokens.Status.caution.tint : Tokens.Status.inert.tint
        case .alert: Tokens.Status.caution.tint
        case .skipped: Tokens.Status.inert.tint
        case .failed: Tokens.Status.destructive.tint
        case .info: Tokens.Status.preview.tint
        }
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
