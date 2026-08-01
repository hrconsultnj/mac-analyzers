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
        .onAppear {
            detachedLoad({ AnalyzersPaths.allForensics() }) { files = $0 }
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
                        DataCard(symbol: "gauge.with.needle", color: level >= 4 ? .red : .orange,
                                 title: "Memory pressure level \(level)",
                                 subtitle: level >= 4 ? "CRITICAL — the system was drowning"
                                                      : level >= 2 ? "Warning — compressing/swapping"
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
                Section("Top Processes by Resident RAM") {
                    ForEach(snapshot.processes.prefix(25)) { proc in
                        DataCard(symbol: "hammer.fill", color: proc.rssMB > 4096 ? .orange : .gray,
                                 title: proc.friendlyName,
                                 subtitle: "pid \(proc.pid) · up \(proc.etime) · \(proc.shortName)",
                                 trailing: proc.rssText)
                    }
                }
            } else {
                Section {
                    Label("This forensics file is no longer on disk.",
                          systemImage: "questionmark.folder")
                        .foregroundStyle(.secondary)
                    Text(route.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onAppear {
            let path = route.path
            detachedLoad({ ForensicsParser.parse(fileAt: path) }) { snapshot = $0 }
        }
    }
}
