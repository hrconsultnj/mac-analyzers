import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications
import AnalyzersKit
import NotifierKit
import UIComponents

/// The Setup checklist — the screen that answers "does this actually work on
/// my Mac?" with evidence rather than reassurance. Every row was detected,
/// and every row that is not green carries the button that fixes it.
///
/// This file is the screen's state and its composition. One job per file next to it:
///   SetupSettingsView+Probes.swift         Detecting each check: loading the report, notifications and the login item.
///   SetupSettingsView+Repairs.swift        The fix behind each red row: repairs, agent install and opening System Settings.
struct SetupSettingsView: View {

    @Environment(GuardLogStore.self) var store
    @Environment(Navigator.self) var navigator
    @Environment(JobStore.self) var jobs
    @State var report: SetupReport?
    @State var working: String?
    /// The install job this screen shows: the store's own, found again by kind
    /// when the window is reopened mid-run.
    @State var installJob: Job?
    @State var message: String?
    @State var messageIsError = false

    var body: some View {
        // title and the one-line state in the toolbar; the checklist at the window's full width
        DataScreen(title: Names.Screen.setup, subtitle: report.map { "\(headline($0)) · \($0.ready) of \($0.total)" }) {
        List {
            if let report {
                progress(report)
                if let installJob, installJob.isActive {
                    Section {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(installJob.step ?? "Installing the background jobs…")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Stop") { installJob.cancel() }
                        }
                    }
                }
                if let message {
                    Section {
                        Label(message, systemImage: messageIsError
                              ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(messageIsError ? Tokens.Status.destructive.tint
                                                            : Tokens.Status.safe.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // blocking first — a checklist that buries the thing stopping
                // the product behind six green ticks has failed at its job
                group("Needs Attention", report.checks.filter { $0.verdict == .blocking })
                group("Worth Doing", report.checks.filter { $0.verdict == .degraded })
                group("Your Choice", report.checks.filter { $0.verdict == .unset })
                group("Working", report.checks.filter { $0.verdict == .ready })
                Section {
                    Text("What this Mac can actually do right now: every line was checked, not assumed. This screen stays in the sidebar after everything is green. Permissions can be withdrawn and background jobs can be unloaded by macOS, so it is worth a look if something stops behaving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Section { Text("Checking this Mac…").foregroundStyle(.secondary) }
            }
        }
        .listStyle(.inset)
        // A list measures its rows when it first shows them; the checklist arrives a moment after the
        // screen, so the list that shows it is a new one (rows measured as the one-line placeholder
        // came out one line high)
        .id(report != nil)
        }
        .task {
            await adoptRunningInstall()
            await load()
        }
    }

    // MARK: - pieces

    @ViewBuilder private func progress(_ report: SetupReport) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                HStack {
                    Text(headline(report))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(report.ready) of \(report.total)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(report.ready), total: Double(report.total))
                    .tint(report.isUsable ? Tokens.Status.safe.tint : Tokens.Status.destructive.tint)
                Text(subhead(report))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func headline(_ report: SetupReport) -> String {
        if !report.isUsable { return "Not protected yet" }
        if report.isComplete { return "Everything is set up" }
        return "Protected"
    }

    private func subhead(_ report: SetupReport) -> String {
        if !report.isUsable {
            return "Something below stops Mac Analyzers doing its job. Each one has a button that fixes it."
        }
        if report.isComplete {
            return "Your Mac is watched, tidied on a schedule, and everything it needs has been granted."
        }
        return "The essentials are working. The rest are improvements you can make whenever you like."
    }

    @ViewBuilder private func group(_ title: String, _ checks: [SetupCheck]) -> some View {
        if !checks.isEmpty {
            Section(title) {
                ForEach(checks) { check in
                    row(check)
                }
            }
        }
    }

    @ViewBuilder private func row(_ check: SetupCheck) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Image(systemName: symbol(check.verdict))
                .foregroundStyle(tone(check.verdict).tint)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(check.title).font(.callout.weight(.medium))
                Text(check.why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // the evidence, visually separated from the sales pitch by weight and colour, not by a
                // typewriter face: it is a sentence ("macOS does not recognise this copy…"), not program output
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(check.verdict == .ready ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: Tokens.Space.m)
            if let title = check.repairTitle, check.repair != .none {
                Button(working == check.id ? "Working…" : title) {
                    Task { await repair(check) }
                }
                .disabled(working != nil)
                .buttonStyle(.glassProminent)
            }
        }
    }

    private func symbol(_ verdict: SetupCheck.Verdict) -> String {
        switch verdict {
        case .ready: "checkmark.circle.fill"
        case .blocking: "exclamationmark.octagon.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .unset: "circle.dashed"
        }
    }

    private func tone(_ verdict: SetupCheck.Verdict) -> Tokens.Tone {
        switch verdict {
        case .ready: Tokens.Status.safe
        case .blocking: Tokens.Status.destructive
        case .degraded: Tokens.Status.caution
        case .unset: Tokens.Status.inert
        }
    }
}
