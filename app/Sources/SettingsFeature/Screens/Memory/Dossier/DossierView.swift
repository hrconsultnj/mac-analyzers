import SwiftUI
import AnalyzersKit
import UIComponents

/// Push target: everything the suite knows about one process/app.
struct DossierRoute: Hashable, Codable, Sendable {
    let name: String
    let pid: Int?
}

/// The per-app dossier — everything Mac Analyzers knows about one process:
/// live footprint, guard history, network traffic, and the protection verdict,
/// composed from data every other screen already parses. A plain form: the
/// title is in the toolbar and the facts fill the window.
struct DossierView: View {

    let route: DossierRoute

    @Environment(ConfigStore.self) private var config
    @State private var live: LiveProcess?
    @State private var energy: EnergyEntry?
    @State private var diskIO: DiskIOEntry?
    @State private var guardEntries: [GuardEntry] = []
    @State private var networkRows: [NetworkTalker] = []

    var body: some View {
        Form {
            liveSection
            protectionSection
            guardSection
            networkSection
        }
        .formStyle(.grouped)
        .navigationTitle(route.name)
        .navigationSubtitle("Everything Mac Analyzers knows about this process")
        .task { await load() }
    }

    // MARK: - live footprint

    @ViewBuilder private var liveSection: some View {
        Section("Right Now") {
            if let live {
                LabeledContent("Memory in use", value: live.memoryText)
                LabeledContent("Process ID", value: String(live.pid))
            } else {
                LabeledContent("Status", value: "Not running")
                if let pid = route.pid {
                    LabeledContent("Last seen as process ID", value: String(pid))
                }
            }
            if let energy { LabeledContent("Energy since launch", value: energy.energyText) }
            if let diskIO {
                LabeledContent("Read since launch", value: diskIO.readText)
                LabeledContent("Written since launch", value: diskIO.writtenText)
            }
        }
    }

    // MARK: - protection verdict

    @ViewBuilder private var protectionSection: some View {
        let name = route.name.lowercased()
        let protected = config.memory.protectExtra.contains {
            name.contains($0.lowercased()) || $0.lowercased().contains(name)
        }
        let killable = LiveStats.isDevTooling(route.name)

        Section("Protection") {
            if protected {
                Label("On your protected list", systemImage: "shield.fill").foregroundStyle(.green)
                Text("The guard and the cleanups will never touch it.").foregroundStyle(.secondary)
            } else if killable {
                Label("In the guard's auto-stop scope", systemImage: "scope").foregroundStyle(.orange)
                Text("It is a developer tool, so the guard can stop it over the memory limit or when memory is critically low.")
                    .foregroundStyle(.secondary)
            } else {
                Label("Regular app — never auto-stopped", systemImage: "shield.lefthalf.filled")
                Text("Only you can stop it, from Monitor.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - histories

    @ViewBuilder private var guardSection: some View {
        Section("Guard History (90 Days)") {
            if guardEntries.isEmpty {
                Text("No guard events for this process — quiet is good.")
                    .foregroundStyle(.secondary)
            }
            ForEach(guardEntries.prefix(20)) { entry in
                LabeledContent {
                    Text(entry.memoryText ?? "").monospacedDigit()
                } label: {
                    VStack(alignment: .leading) {
                        Text(entry.title)
                        Text(entry.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var networkSection: some View {
        Section("Network (Latest Snapshot)") {
            if networkRows.isEmpty {
                Text("No traffic recorded in the latest snapshot.")
                    .foregroundStyle(.secondary)
            }
            ForEach(networkRows) { talker in
                LabeledContent {
                    Text(ByteSize.format(talker.totalBytes)).monospacedDigit()
                } label: {
                    VStack(alignment: .leading) {
                        Text(talker.resolvedName)
                        Text("↓ \(ByteSize.format(talker.inBytes)) · ↑ \(ByteSize.format(talker.outBytes)) · process ID \(String(talker.pid))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - load

    private func load() async {
        let name = route.name
        let pid = route.pid
        await awaitLoad({ () -> (LiveProcess?, EnergyEntry?, DiskIOEntry?, [GuardEntry], [NetworkTalker]) in
            let needle = name.lowercased()
            let procs = LiveStats.snapshot(limit: 60, minimumMB: 16)
            // by pid first, at any size and whoever owns it — the ranked
            // list only carries the biggest rows, so a small or macOS-owned
            // process opened from the Monitor read as "not running"
            // (a pid can be recycled by an unrelated program, so the name
            // has to agree before the pid is believed)
            let liveMatch = pid.flatMap { LiveStats.process(pid: $0) }
                .flatMap { $0.friendlyName.lowercased() == needle
                    || $0.rawName.lowercased().contains(needle) ? $0 : nil }
                ?? procs.first { $0.friendlyName.lowercased() == needle
                    || $0.rawName.lowercased().contains(needle) }
            let livePid = liveMatch?.pid ?? pid
            let energyMatch = EnergyStats.snapshot(limit: 200)
                .first { $0.pid == livePid || $0.name.lowercased() == needle }
            let diskMatch = EnergyStats.diskSnapshot(limit: 200)
                .first { $0.pid == livePid || $0.name.lowercased() == needle }
            let events = GuardHistory.build(events: GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog)
                .filter {
                    $0.friendlyName.lowercased().contains(needle)
                        || $0.processName.lowercased().contains(needle)
                        || needle.contains($0.friendlyName.lowercased())
                }).entries.sorted { $0.date > $1.date }
            let network = NetworkParser.latest(fromLog: AnalyzersPaths.networkLog)?
                .talkers.filter {
                    $0.pid == livePid
                        || $0.resolvedName.lowercased().contains(needle)
                        || needle.contains($0.name.lowercased())
                } ?? []
            return (liveMatch, energyMatch, diskMatch, events, network)
        }) {
            live = $0.0
            energy = $0.1
            diskIO = $0.2
            guardEntries = $0.3
            networkRows = $0.4
        }
    }
}
