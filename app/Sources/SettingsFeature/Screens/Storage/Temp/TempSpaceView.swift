import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Temp & Agents pane: what is really in /tmp, /var and the AI agents'
/// folders. The insight surface — mounted disk images told apart from real
/// disk use (with Eject), every row's verdict and why, agent history and
/// macOS-managed areas sized but never touched. Clearing goes through
/// Actions (`actions:tempClean`), the one reviewed apply flow, so untick and
/// the approved-set contract work exactly as they do for every cleaner.
///
/// This file is the screen's state and its composition. One job per file next to it:
///   TempSpaceView+Overview.swift           Where the space is: free space, temp on disk, disk images, agent folders.
///   TempSpaceView+Mounts.swift             Mounted disk images, told apart from real disk use, with Eject.
///   TempSpaceView+Items.swift              The audited rows, grouped by where they live, with filter chips and Finder reveal.
///   TempSpaceView+Actions.swift            Run audit and eject as jobs, open Actions, and loading the latest audit.
struct TempSpaceView: View {

    @Environment(Navigator.self) var navigator
    @Environment(JobStore.self) var jobs

    enum Filter: String, CaseIterable {
        case ready = "Ready"
        case leftAlone = "Left Alone"
        case sized = "Sized Only"
        case all = "All"
    }

    /// Drives the small status line under the action row only — the lists
    /// stay visible while a script runs (same as SpotlightAuditView).
    enum RunPhase: Equatable {
        case idle
        case running(String)
        case done(String)
        case failed(String)
    }

    @State var run: TempCleanRun?
    @State var filter: Filter = .ready
    /// The audit or eject this screen shows: the store's own job, found again
    /// by kind when the window is reopened mid-run. `runPhase` is read off it.
    @State var job: Job?
    /// Set when an eject "succeeded" but the image is still mounted.
    @State var ejectProblem: String?
    /// Sections showing every row rather than the biggest few.
    @State var expanded: Set<String> = []
    @State var ejecting: TempMount?

    static let collapsedRows = 12

    var body: some View {
        PaneScaffold(symbol: "tray.full", color: .mint, title: Names.Screen.tempAndAgents,
                     caption: "What /tmp, /var and your AI agents' folders really hold — disk images told apart from real use, every verdict explained. Clearing is reviewed in Actions; nothing open, recent, live or someone else's is ever touched.") {
            Section {
                HStack {
                    Spacer(minLength: 8)
                    Button("Run Audit") { runAudit() }
                        .disabled(isBusy)
                        .help("Check what is in temp folders; changes nothing")
                    Button("Review and Clean…") { openActions() }
                        .buttonStyle(.glassProminent)
                        .disabled(isBusy || (run?.readyItems.isEmpty ?? true))
                        .help("Preview, untick what to keep, then move to the Trash or delete")
                    Button("Open in TextEdit") { GuardControl.openLog(AnalyzersPaths.tempCleanLog) }
                    Button {
                        Task { await load(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                        .accessibilityLabel("Refresh")
                }
                statusLine
                if let run {
                    HStack(spacing: 6) {
                        BadgeCapsule(text: run.dryRun ? "Audit" : (run.permanent ? "Deleted" : "Trashed"),
                                     color: run.dryRun ? .blue : (run.permanent ? .red : .orange))
                        Text(run.summary ?? run.header)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let run {
                overviewSection(run)
                if !run.mounts.isEmpty { mountsSection(run) }
                itemSections(run)
            } else {
                Section {
                    Text("No audit yet — Run audit to see what /tmp, /var and your AI agents' folders hold. Nothing is changed.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            adoptCurrentJob()
            await load()
        }
        .onChange(of: job?.stamp) { _, stamp in
            guard let stamp, stamp.stage == .succeeded else { return }
            Task { await jobSucceeded() }
        }
        .confirmationDialog(ejectPrompt, isPresented: Binding(
            get: { ejecting != nil }, set: { if !$0 { ejecting = nil } }),
                            titleVisibility: .visible) {
            Button("Eject") {
                if let mount = ejecting { eject(mount) }
            }
            Button("Cancel", role: .cancel) { ejecting = nil }
        } message: {
            Text("Closes the disk image — nothing is deleted, and you can open the image file again any time. If something is still reading from it, macOS refuses and nothing changes.")
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch runPhase {
        case .idle:
            EmptyView()
        case .running(let label):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Stop") { job?.cancel() }
                    .controlSize(.small)
            }
        case .done(let summary):
            Label(summary, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var isBusy: Bool {
        if case .running = runPhase { return true }
        return false
    }

    private var ejectPrompt: String {
        guard let mount = ejecting else { return "Eject disk image?" }
        let name = (mount.mountPoint as NSString).lastPathComponent
        return mount.alsoEjects.isEmpty
            ? "Eject \(name)?"
            : "Eject \(name) and \(mount.alsoEjects.count) image\(mount.alsoEjects.count == 1 ? "" : "s") opened from inside it?"
    }
}
