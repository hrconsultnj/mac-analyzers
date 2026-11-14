import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Turning it off has to be as easy as turning it on — and it has to be
/// PROVEN, not announced. Each level re-reads the real engine state
/// afterwards and reports what actually happened.
struct UninstallView: View {

    @Environment(GuardLogStore.self) private var store
    @Environment(JobStore.self) private var jobs
    @State private var busy = false
    @State private var result: String?
    @State private var failed = false
    @State private var confirming: Level?
    /// The uninstall job this screen shows: the store's own, found again by
    /// kind when the window is reopened mid-run.
    @State private var job: Job?
    /// The Time Machine permission, as the disk says it is now: read when the screen opens and again after any change.
    @State private var permission = TurnOffPermission.rows()
    /// Example rows from `SnapshotRunner`'s `turnoff:` targets; nil in the app people use.
    var permissionFixture: TurnOffPermission.Rows?

    enum Level: String, Identifiable {
        case pause, background, everything
        var id: String { rawValue }

        var title: String {
            switch self {
            case .pause: "Pause everything"
            case .background: "Turn off background protection"
            case .everything: "Remove from this Mac"
            }
        }

        var detail: String {
            switch self {
            case .pause:
                "The guard keeps watching but takes no action, and stays paused until you resume. Nothing is uninstalled."
            case .background:
                "Unloads the scheduled jobs and the guard, and stops the app opening at login. The app and your logs stay put; you can set it up again any time."
            case .everything:
                "Everything above, plus Mac Analyzers forgets that it has welcomed you (so a reinstall starts fresh) and reveals the app and its folder in Finder so you can drag them to the Trash. Your reports and settings are left alone unless you delete that folder."
            }
        }

        var confirmMessage: String {
            switch self {
            case .pause: "The guard will stop acting until you resume it."
            case .background:
                "Your Mac will no longer be watched or cleaned automatically. Nothing you have is deleted."
            case .everything:
                "Background protection stops, Mac Analyzers forgets that it has welcomed you, and Finder opens at the app and its folder. Deleting those is your call: this app never deletes itself or your reports."
            }
        }
    }

    /// What the confirmation says: the password prompt is announced here when the "Remove from this Mac" level
    /// will show one.
    private func confirmMessage(for level: Level) -> String {
        level == .everything && permission.removable
            ? level.confirmMessage + " " + TurnOffPermission.confirmation
            : level.confirmMessage
    }

    var body: some View {
        DataScreen(title: Names.Screen.turnOff, subtitle: "Three levels, least drastic first") {
        List {
            if let result {
                Section {
                    Label(result, systemImage: failed ? "exclamationmark.triangle.fill"
                                                      : "checkmark.circle.fill")
                        .foregroundStyle(failed ? .red : .green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach([Level.pause, .background, .everything]) { level in
                Section {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                            Text(level.title).font(.callout.weight(.medium))
                            Text(level.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Tokens.Space.m)
                        Button(level == .pause ? "Pause" : "Continue…",
                               role: level == .pause ? nil : .destructive) {
                            confirming = level
                        }
                        .disabled(busy)
                    }
                }
            }
            permissionSection
            if let job, job.isActive {
                Section {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(job.step ?? "Turning off background protection…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { job.cancel() }
                    }
                }
            }
            Section {
                Text("Every level reports what actually happened afterwards. What stays either way: your reports and logs under ~/mac-analyzers/reports, and anything you configured. This app never deletes your data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        }
        .confirmationDialog(confirming?.title ?? "", isPresented: .init(
            get: { confirming != nil },
            set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            if let level = confirming {
                Button(level.title, role: level == .pause ? nil : .destructive) {
                    Task { await run(level) }
                }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text(confirming.map { confirmMessage(for: $0) } ?? "")
        }
        .task {
            permission = permissionFixture ?? TurnOffPermission.rows()
            await adoptRunning()
        }
    }

    /// What this app installed with a password and can remove again: the Time Machine permission. Shown only when
    /// the file is there. The button is the person's click and the prompt is macOS'; nothing here asks on its own.
    @ViewBuilder private var permissionSection: some View {
        if permission.removable {
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                        Text(Names.TimeMachine.permissionRowTitle).font(.callout.weight(.medium))
                        Text(TurnOffPermission.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Tokens.Space.m)
                    Button(Names.TimeMachine.removePermission) { Task { await removePermissionOnly() } }
                        .disabled(busy)
                }
            }
        }
        if let command = permission.earlierCommand {
            Section {
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    Text(Names.TimeMachine.earlierPermissionTitle).font(.callout.weight(.medium))
                    Text(Names.TimeMachine.earlierPermissionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(command).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
    }

    /// The row's own button: the permission and nothing else.
    private func removePermissionOnly() async {
        busy = true
        defer { busy = false }
        let outcome = await TimeMachinePermission.revoke()
        permission = TurnOffPermission.rows()
        let said = TurnOffPermission.sentence(after: outcome, stillThere: permission.removable)
        result = said.text
        failed = !said.complete
    }

    /// The window was closed while the agents were being turned off: show it
    /// still working, then say what is true once it ends.
    private func adoptRunning() async {
        guard let running = jobs.latest(.uninstallAgents, intents: [.run]), running.isActive else { return }
        job = running
        busy = true
        defer { busy = false }
        await running.waitUntilFinished()
        await reportAgentsOff()
    }

    private func run(_ level: Level) async {
        busy = true
        defer { busy = false }
        confirming = nil

        switch level {
        case .pause:
            do {
                try store.setGuardPaused(true)
                result = "Paused. The guard is watching but taking no action."
                failed = false
            } catch {
                result = error.localizedDescription
                failed = true
            }

        case .background, .everything:
            let uninstall = jobs.enqueue(JobRequest(kind: .uninstallAgents, intent: .run), trigger: .user)
            job = uninstall
            await uninstall.waitUntilFinished()
            if case .cancelled = uninstall.state {
                result = "Stopped. Some background jobs may already be off — check the Setup screen."
                failed = true
                store.reload()
                return
            }
            GuardControl.disableLoginItem()
            await reportAgentsOff()
            let agentsOff = !failed

            // The order: everything that asks nothing first, so a cancelled password prompt leaves no
            // half-done state behind and the sentence below can say exactly what is still there. The
            // prompt is the only step a person can refuse, so it comes last of the removals; the Finder
            // window opens after it whatever the answer was.
            if level == .everything, permission.removable, !agentsOff {
                // turning the agents off failed: no password prompt on top of a failure
                result = (result.map { $0 + " " } ?? "")
                    + "The Time Machine permission was left in place, and no password was asked. Remove it with Remove Permission… on this screen once the background jobs are off."
            } else if level == .everything, permission.removable {
                let outcome = await TimeMachinePermission.revoke()
                permission = TurnOffPermission.rows()
                let said = TurnOffPermission.sentence(after: outcome, stillThere: permission.removable)
                result = (result.map { $0 + " " } ?? "") + said.text
                failed = failed || !said.complete
            }

            // the app's note that it has shown the Welcome flow goes with it, so a reinstall starts fresh
            if level == .everything, agentsOff { SetupState.remove() }
            if level == .everything, agentsOff {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: "/Applications/MacAnalyzers.app"),
                    AnalyzersPaths.suiteRoot,
                ])
            }
        }
    }

    /// Prove it rather than claim it: re-read the real engine state.
    private func reportAgentsOff() async {
        let status = await Task.detached(priority: .userInitiated) {
            EngineStatus.probe()
        }.value
        let stillLoaded = (status.guardAgent == .loaded ? 1 : 0)
            + status.cleanerAgents.values.filter { $0 == .loaded }.count
        failed = stillLoaded > 0
        result = stillLoaded == 0
            ? "Background protection is off — no scheduled jobs remain loaded, and the app no longer opens at login."
            : "\(stillLoaded) background job(s) are still loaded. Try again, or remove them in System Settings › General › Login Items."
        store.reload()
    }
}
