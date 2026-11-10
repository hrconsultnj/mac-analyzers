import SwiftUI
import AnalyzersKit
import UIComponents

/// Logs › Forensics: every crisis dump, newest first, each pushing the
/// structured detail screen (stat cards + top-25 table).
struct ForensicsBrowserView: View {

    @State private var files: [URL] = []

    var body: some View {
        PaneScaffold(symbol: "stethoscope", color: .purple, title: "Forensics",
                     caption: "Every moment the guard wrote a crisis report — newest first.") {
            Section {
                if files.isEmpty {
                    Text("No forensics reports — the guard never hit a crisis. Quiet is good.")
                        .foregroundStyle(.secondary)
                }
                ForEach(files, id: \.absoluteString) { file in
                    NavigationLink(value: LogRoute.forensics(ForensicsRoute(path: file.path))) {
                        DataCard(symbol: "stethoscope", color: .purple,
                                 title: file.lastPathComponent,
                                 subtitle: AnalyzersPaths.modificationDate(of: file)
                                     .map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) }
                                     ?? file.deletingLastPathComponent().lastPathComponent,
                                 badge: ("REPORT", .purple))
                    }
                }
            }
        }
        .task {
            await awaitLoad({ AnalyzersPaths.allForensics() }) { files = $0 }
        }
    }
}

/// Push target for a forensics snapshot from the guard pane.
struct ForensicsRoute: Hashable {
    let path: String
}

/// One forensics snapshot: Activity Monitor's memory view, frozen at the
/// moment of crisis — stat cards + the top-RSS process table.
struct ForensicsDetailView: View {

    let route: ForensicsRoute
    @State private var snapshot: ForensicsSnapshot?

    var body: some View {
        PaneScaffold(symbol: "stethoscope", color: .purple, title: "Forensics",
                     caption: snapshot?.header ?? (route.path as NSString).lastPathComponent) {
            Section {
                HStack {
                    Spacer()
                    Button("Open in TextEdit") {
                        GuardControl.openLog(URL(fileURLWithPath: route.path))
                    }
                    .disabled(snapshot == nil)
                }
            }

            if let snapshot {
                Section("At the Moment of Crisis") {
                    if let level = snapshot.pressureLevel {
                        // color now tracks all three tiers, not just critical-vs-not —
                        // a "Normal" reading was showing the same orange as a warning
                        DataCard(symbol: "gauge.with.needle",
                                 color: level >= 4 ? Tokens.Status.destructive.tint
                                     : level >= 2 ? Tokens.Status.caution.tint
                                     : Tokens.Status.safe.tint,
                                 title: "Memory pressure level \(level)",
                                 subtitle: level >= 4 ? "Critical — the system was drowning"
                                                      : level >= 2 ? "Warning — squeezing memory harder than usual (compressing, using swap)"
                                                      : "Normal")
                    }
                    if let physMem = snapshot.physMemLine {
                        DataCard(symbol: "memorychip", color: .blue,
                                 title: "Physical memory", subtitle: physMem)
                    }
                    if let swap = snapshot.swapLine {
                        DataCard(symbol: "arrow.left.arrow.right", color: .teal,
                                 title: "Swap", subtitle: swap)
                    }
                }
                Section("Top Processes by Memory in Use") {
                    ForEach(snapshot.processes.prefix(25)) { proc in
                        // color alone used to be the only signal a process was
                        // memory-heavy — add the word so it doesn't rely on color
                        let tone = Tokens.Ramp.residency(proc.rssMB)
                        DataCard(symbol: "hammer.fill", color: tone.tint,
                                 title: proc.friendlyName,
                                 subtitle: "process \(proc.pid) · up \(proc.etime) · \(proc.shortName)",
                                 trailing: proc.rssText,
                                 badge: proc.rssMB > 4096 ? ("HIGH", tone.tint) : nil)
                    }
                }
            } else {
                Section {
                    Label("This forensics report is no longer on disk.",
                          systemImage: "questionmark.folder")
                        .foregroundStyle(.secondary)
                    Text(route.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task {
            let path = route.path
            await awaitLoad({ ForensicsParser.parse(fileAt: path) }) { snapshot = $0 }
        }
    }
}
