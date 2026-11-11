import SwiftUI
import AnalyzersKit
import UIComponents

/// The shell's status item, present on every screen but Activity: while a job runs a
/// spinner, "<task>… 0:42" and a stop button; for 30 seconds after one ends
/// its outcome; nothing otherwise. Clicking it opens that job in Activity.
///
/// Attach it to the split view (`MainWindowView` does): a toolbar attached to
/// a `NavigationStack` itself is silently dropped.
struct JobStatusToolbarItem: ToolbarContent {
    let store: JobStore
    let navigator: Navigator

    /// Priority: the screen's own controls come first, and this item is secondary.
    /// On Activity's own list it is not shown at all (it is on a run screen pushed over
    /// it, which may show another job): that list shows the running job at its
    /// top and its scope buttons are what the person uses there, so the item would
    /// only compete with them for the toolbar's width (the system moved the whole
    /// group into the overflow menu at 900 points when both were present). It is
    /// on every other screen.
    var body: some ToolbarContent {
        if !(navigator.section == OverviewGroup.activity && navigator.path.isEmpty) {
            ToolbarItem(placement: .status) {
                JobStatusItemView(store: store, navigator: navigator)
            }
            .toolbarRank(.secondary)
        }
    }
}

private struct JobStatusItemView: View {
    let store: JobStore
    let navigator: Navigator

    /// How long a finished job's outcome stays up.
    private static let linger: TimeInterval = 30

    private var recentlyFinished: Job? {
        store.jobs
            .filter { job in
                guard let end = job.finishedAt else { return false }
                if case .cancelled = job.state { return false }     // you stopped it; you know
                return Date().timeIntervalSince(end) < Self.linger
            }
            .max { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
    }

    var body: some View {
        if let job = store.running {
            running(job)
        } else if let job = recentlyFinished, let end = job.finishedAt {
            // redrawn once, when the 30 seconds are up
            // never on the job's own screen: its title already says so and it takes the tabs' room
            TimelineView(.explicit([end.addingTimeInterval(Self.linger)])) { _ in
                if Date() < end.addingTimeInterval(Self.linger), !isOnOwnScreen(job) { finished(job) }
            }
        }
    }

    /// Standard buttons only: a toolbar item that sets its own size or style
    /// (`.plain`, `.controlSize`, a hand-drawn shape) leaves the toolbar's glass
    /// surface and its 36-point grid. A `ControlGroup` draws the two buttons as
    /// one grouped control, the way the system groups related toolbar buttons.
    private func running(_ job: Job) -> some View {
        ControlGroup {
            Button { open(job) } label: {
                HStack {
                    ProgressView().controlSize(.small)
                    elapsed(job)
                }
            }
            .help("Open \(job.kind.title) in Activity")
            Button { job.cancel() } label: {
                Label("Stop \(job.kind.title)", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .help("Stop \(job.kind.title) — quitting asks whether to stop it or let it finish")
        }
    }

    /// "Memory Clean… 0:42" — the task's name with a clock the system keeps
    /// redrawing. Short on purpose: a long step name pushes the screen's own
    /// toolbar controls into the overflow menu.
    @ViewBuilder private func elapsed(_ job: Job) -> some View {
        let label = job.kind.title + "… "
        if let started = job.startedAt {
            Text("\(label)\(started, style: .timer)")
                .monospacedDigit()
        } else {
            Text(label)
        }
    }

    /// The task's name beside a tick or a warning: short, so it fits whatever
    /// else the toolbar holds. What happened, in full ("Found 3 processes to
    /// close (~494 MB) — nothing was closed"), is the tooltip and the run's own
    /// screen, one click away.
    private func finished(_ job: Job) -> some View {
        let snapshot = job.activitySnapshot
        let ok = snapshot.status == .done
        let sentence = ok ? snapshot.summary.text
                          : "\(job.kind.title) \(snapshot.status == .failed ? "failed" : "stopped")"
        return Button { open(job) } label: {
            Label(job.kind.title, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(ok ? Tokens.Status.safe.tint : Tokens.Status.caution.tint)
        }
        .help("\(sentence). Open \(job.kind.title) in Activity.")
    }

    /// The screen a job belongs to is the one its task is named after: where its log, its review or
    /// its own link leads (the same places a run's "Open <Task>" and "Review" go).
    private func isOnOwnScreen(_ job: Job) -> Bool {
        let kind = job.kind
        var targets: [String] = []
        if let log = kind.log { targets.append("log:\(log.rawValue)") }
        switch kind {
        case .memoryClean, .reclaim, .storageClean, .janitor, .tempClean: targets.append("actions:\(kind.rawValue)")
        case .spotlight: targets.append("spotlight")
        case .loginItems: targets.append("log:loginItems")
        case .memoryReport, .storageReport: targets.append("reports")
        case .networkSnapshot: targets.append("network")
        case .installAgents, .sudoersInstall: targets.append("setup")
        case .uninstallAgents: targets.append("uninstall")
        default: break
        }
        return targets.contains { target in
            switch DeepLinkRouter.resolve(target) {
            case .main(let location), .mainWithIntent(let location, _): location.section == navigator.section
            default: false
            }
        }
    }

    private func open(_ job: Job) {
        navigator.open(target: "job:\(job.id.uuidString)")
    }
}
