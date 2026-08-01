import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The read-only analyzers, in the app. These are the two things the project
/// leads with — "explain where my memory went", "explain what is eating my
/// disk" — and until now the only way to run them was from a terminal.
/// Nothing here changes anything: both scripts only write a report.
struct ReportsSettingsView: View {

    enum Kind: String, CaseIterable, Identifiable {
        case memory, storage
        var id: String { rawValue }

        var title: String { self == .memory ? "Memory" : "Storage" }
        var symbol: String { self == .memory ? "memorychip" : "internaldrive.fill" }
        var color: Color { self == .memory ? .blue : .indigo }

        var summary: String {
            self == .memory
                ? "Where your memory is actually going: a breakdown by app with helper processes rolled up, how much is compressed or swapped, and a plain reading of whether anything is wrong."
                : "What is using your disk: the biggest folders, caches worth clearing, large and duplicate files, and how much is genuinely reclaimable."
        }

        var script: URL {
            self == .memory ? AnalyzersPaths.memoryAnalyzeScript
                            : AnalyzersPaths.storageAnalyzeScript
        }

        var latest: URL {
            self == .memory ? AnalyzersPaths.memoryLatestReport
                            : AnalyzersPaths.storageLatestReport
        }

        /// The storage sweep walks the whole home folder.
        var duration: String {
            self == .memory ? "Takes a few seconds." : "Takes a minute or two on a full disk."
        }
    }

    @State private var running: Kind?
    @State private var error: String?
    @State private var body_: [Kind: String] = [:]
    @State private var stamps: [Kind: Date] = [:]
    @State private var showing: Kind?

    var body: some View {
        PaneScaffold(symbol: "doc.text.magnifyingglass", color: .purple, title: "Reports",
                     caption: "Two read-only reports that explain what your Mac is doing. Running one changes nothing — it only writes a document you can read here or keep.") {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Tokens.Status.destructive.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(Kind.allCases) { kind in
                Section {
                    VStack(alignment: .leading, spacing: Tokens.Space.s) {
                        HStack(alignment: .top) {
                            IconTile(symbol: kind.symbol, color: kind.color, side: Tokens.Icon.card)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(kind.title) report").font(.callout.weight(.medium))
                                Text(kind.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(stamps[kind].map { "Last run \($0.formatted(.relative(presentation: .named)))." }
                                     ?? "Not run yet. \(kind.duration)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Tokens.Space.m)
                            Button(running == kind ? "Working…" : "Run") {
                                Task { await run(kind) }
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(running != nil)
                        }
                        if body_[kind] != nil {
                            HStack {
                                Button(showing == kind ? "Hide report" : "Read report") {
                                    showing = showing == kind ? nil : kind
                                }
                                Button("Open in TextEdit") { GuardControl.openLog(kind.latest) }
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([kind.latest])
                                }
                                Spacer()
                            }
                        }
                    }
                    if showing == kind, let text = body_[kind] {
                        // monospaced because the reports are column-aligned
                        // tables — proportional text scrambles them
                        ScrollView(.horizontal) {
                            Text(text)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxHeight: 420)
                    }
                }
            }
            Section {
                Text("Neither report moves, deletes or stops anything. They are the same scripts you can run yourself from the analyzers folder, and each run is saved under your reports folder with the date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await loadExisting() }
    }

    private func loadExisting() async {
        for kind in Kind.allCases {
            let url = kind.latest
            await awaitLoad({
                (try? String(contentsOf: url, encoding: .utf8),
                 (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate)
            }, key: "reports:\(kind.rawValue)") { found in
                if let text = found.0 { body_[kind] = text }
                if let stamp = found.1 { stamps[kind] = stamp }
            }
        }
    }

    private func run(_ kind: Kind) async {
        running = kind
        error = nil
        defer { running = nil }
        let result = await ActionRunner.run(script: kind.script, args: [])
        guard result.exitCode == 0 else {
            error = ActionsSettingsView.explain(exitCode: result.exitCode, verb: "write the report")
            return
        }
        await LoadCoordinator.shared.invalidateAll()
        await loadExisting()
        showing = kind
    }
}
