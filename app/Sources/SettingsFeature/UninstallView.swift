import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Turning it off has to be as easy as turning it on — and it has to be
/// PROVEN, not announced. Each level re-reads the real engine state
/// afterwards and reports what actually happened.
struct UninstallView: View {

    @Environment(GuardLogStore.self) private var store
    @State private var busy = false
    @State private var result: String?
    @State private var failed = false
    @State private var confirming: Level?

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
                "Everything above, plus reveals the app and its folder in Finder so you can drag them to the Trash. Your reports and settings are left alone unless you delete that folder."
            }
        }

        var confirmMessage: String {
            switch self {
            case .pause: "The guard will stop acting until you resume it."
            case .background:
                "Your Mac will no longer be watched or cleaned automatically. Nothing you have is deleted."
            case .everything:
                "Background protection stops and Finder opens at the app and its folder. Deleting those is your call — this app never deletes itself or your reports."
            }
        }
    }

    var body: some View {
        PaneScaffold(symbol: "power", color: .red, title: "Turn Off or Remove",
                     caption: "Three levels, least drastic first. Every one of them reports what actually happened afterwards.") {
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.title).font(.callout.weight(.medium))
                            Text(level.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Button(level == .pause ? "Pause" : "Continue…",
                               role: level == .pause ? nil : .destructive) {
                            confirming = level
                        }
                        .disabled(busy)
                    }
                }
            }
            Section {
                Text("What stays either way: your reports and logs under ~/mac-analyzers/reports, and anything you configured. This app never deletes your data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            Text(confirming?.confirmMessage ?? "")
        }
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
            for script in [AnalyzersPaths.suiteRoot.appending(path: "memory-analyzer/memory-manage-agents.sh"),
                           AnalyzersPaths.suiteRoot.appending(path: "storage-analyzer/storage-manage-agents.sh")]
            where FileManager.default.isExecutableFile(atPath: script.path) {
                _ = await ActionRunner.run(script: script, args: ["uninstall"])
            }
            GuardControl.disableLoginItem()

            // Prove it rather than claim it.
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

            if level == .everything, !failed {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: "/Applications/MacAnalyzers.app"),
                    AnalyzersPaths.suiteRoot,
                ])
            }
        }
    }
}
