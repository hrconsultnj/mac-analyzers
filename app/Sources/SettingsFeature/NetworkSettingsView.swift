import SwiftUI
import AnalyzersKit
import UIComponents

/// OBSERVE › Network — who has moved the most data, per process. nettop's
/// counters are cumulative since each process launched, so this is the
/// "who's been phoning home" ledger, not a live speed meter. Read-only.
struct NetworkSettingsView: View {

    @State private var snapshot: NetworkSnapshot?
    @State private var refreshing = false

    var body: some View {
        PaneScaffold(symbol: "network", color: .purple, title: "Network",
                     caption: "Cumulative traffic per process since it launched — the phoning-home ledger. Observation only; nothing is blocked.") {
            Section {
                HStack {
                    if let snapshot {
                        Text(String(snapshot.header.prefix(16)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await refresh() }
                    } label: {
                        if refreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Snapshot now", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(refreshing)
                }
            }
            if let snapshot {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                              spacing: 10) {
                        totalTile(symbol: "arrow.down.circle.fill", color: .blue,
                                  value: ByteSize.format(snapshot.totalIn), label: "Downloaded (all processes)")
                        totalTile(symbol: "arrow.up.circle.fill", color: .orange,
                                  value: ByteSize.format(snapshot.totalOut), label: "Uploaded (all processes)")
                    }
                    .padding(.vertical, 2)
                }
                Section("Top talkers") {
                    ForEach(snapshot.talkers) { talker in
                        row(for: talker)
                    }
                }
            } else if !refreshing {
                Section {
                    Text("No snapshot yet — take one to see who's been talking.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await awaitLoad({ NetworkParser.latest(fromLog: AnalyzersPaths.networkLog) }) {
                snapshot = $0
                if $0 == nil { Task { await refresh() } }
            }
        }
    }

    private func row(for talker: NetworkTalker) -> some View {
        // existence check only: nettop names are truncated (no comm match)
        // and the snapshot is fresh, so pid-alive is the honest signal
        let alive = ProcessLiveness.isStillRunning(pid: talker.pid, name: "",
                                                   loggedAt: Date())
        return Group {
            if let app = NSRunningApplication(processIdentifier: pid_t(talker.pid)),
               let icon = app.icon {
                DataCard(appIcon: icon, title: talker.resolvedName,
                         subtitle: "↓ \(ByteSize.format(talker.inBytes)) · ↑ \(ByteSize.format(talker.outBytes)) · pid \(talker.pid)",
                         trailing: ByteSize.format(talker.totalBytes),
                         live: alive)
            } else {
                DataCard(symbol: "app.connected.to.app.below.fill", color: .purple,
                         title: talker.resolvedName,
                         subtitle: "↓ \(ByteSize.format(talker.inBytes)) · ↑ \(ByteSize.format(talker.outBytes)) · pid \(talker.pid)",
                         trailing: ByteSize.format(talker.totalBytes),
                         live: alive)
            }
        }
    }

    private func totalTile(symbol: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(color).font(.body)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
    }

    private func refresh() async {
        refreshing = true
        _ = await ActionRunner.run(script: AnalyzersPaths.networkScript, args: [])
        snapshot = await Task.detached(priority: .userInitiated) {
            NetworkParser.latest(fromLog: AnalyzersPaths.networkLog)
        }.value
        refreshing = false
    }
}
