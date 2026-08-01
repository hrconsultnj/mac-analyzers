import SwiftUI
import AnalyzersKit
import UIComponents

/// Push target: everything the suite knows about one process/app.
struct DossierRoute: Hashable {
    let name: String
    let pid: Int?
}

/// The per-app dossier — the screen no competitor has: live footprint,
/// guard history, network traffic, and the protection verdict, composed
/// from data every other pane already parses.
struct DossierView: View {

    let route: DossierRoute

    @Environment(ConfigStore.self) private var config
    @State private var live: LiveProcess?
    @State private var energy: EnergyEntry?
    @State private var diskIO: DiskIOEntry?
    @State private var guardEvents: [GuardEvent] = []
    @State private var networkRows: [NetworkTalker] = []

    var body: some View {
        PaneScaffold(symbol: "doc.text.magnifyingglass", color: .cyan,
                     title: route.name,
                     caption: "Everything Mac Analyzers knows about this process.") {
            liveSection
            protectionSection
            guardSection
            networkSection
        }
        .task { await load() }
    }

    // MARK: - live footprint

    @ViewBuilder private var liveSection: some View {
        Section("Right now") {
            if let live {
                DataCard(symbol: "memorychip", color: .blue,
                         title: "Resident memory",
                         subtitle: "pid \(live.pid)",
                         trailing: live.residentText,
                         live: true)
            } else {
                DataCard(symbol: "moon.zzz", color: .gray,
                         title: "Not running",
                         subtitle: route.pid.map { "last seen as pid \($0)" } ?? "no live process matches")
            }
            if let energy {
                DataCard(symbol: "bolt.fill", color: .yellow,
                         title: "Energy since launch",
                         trailing: energy.energyText)
            }
            if let diskIO {
                DataCard(symbol: "internaldrive", color: .indigo,
                         title: "Disk I/O since launch",
                         subtitle: "↓ \(diskIO.readText) read",
                         trailing: "↑ \(diskIO.writtenText)")
            }
        }
    }

    // MARK: - protection verdict

    @ViewBuilder private var protectionSection: some View {
        let name = route.name.lowercased()
        let protected = config.memory.protectExtra.contains {
            name.contains($0.lowercased()) || $0.lowercased().contains(name)
        }
        let killable = LiveStats.isDevKillable(route.name)

        Section("Protection") {
            if protected {
                DataCard(symbol: "shield.fill", color: .green,
                         title: "On your protected list",
                         subtitle: "The guard and reapers will never touch it.",
                         badge: ("PROTECTED", .green))
            } else if killable {
                DataCard(symbol: "scope", color: .orange,
                         title: "In the guard's auto-stop scope",
                         subtitle: "Dev tooling — can be stopped over the cap or at critical pressure.",
                         badge: ("IN SCOPE", .orange))
            } else {
                DataCard(symbol: "shield.lefthalf.filled", color: .blue,
                         title: "Regular app — never auto-stopped",
                         subtitle: "Only you can stop it (Monitor's Stop/Quit).")
            }
        }
    }

    // MARK: - histories

    @ViewBuilder private var guardSection: some View {
        Section("Guard history (90 days)") {
            if guardEvents.isEmpty {
                Text("No guard events for this process — quiet is good.")
                    .foregroundStyle(.secondary)
            }
            ForEach(guardEvents.prefix(20)) { event in
                DataCard(symbol: event.isKill ? "xmark.octagon.fill" : "arrow.up.right",
                         color: event.isKill ? .red : .orange,
                         title: event.title,
                         subtitle: event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                         trailing: event.residentText,
                         badge: event.isKill ? ("KILLED", .red) : nil)
            }
        }
    }

    @ViewBuilder private var networkSection: some View {
        Section("Network (latest snapshot)") {
            if networkRows.isEmpty {
                Text("No traffic recorded in the latest snapshot.")
                    .foregroundStyle(.secondary)
            }
            ForEach(networkRows) { talker in
                DataCard(symbol: "network", color: .purple,
                         title: talker.resolvedName,
                         subtitle: "↓ \(ByteSize.format(talker.inBytes)) · ↑ \(ByteSize.format(talker.outBytes)) · pid \(talker.pid)",
                         trailing: ByteSize.format(talker.totalBytes))
            }
        }
    }

    // MARK: - load

    private func load() async {
        let name = route.name
        let pid = route.pid
        await awaitLoad({ () -> (LiveProcess?, EnergyEntry?, DiskIOEntry?, [GuardEvent], [NetworkTalker]) in
            let needle = name.lowercased()
            let procs = LiveStats.snapshot(limit: 60, minimumMB: 16)
            let liveMatch = procs.first { pid != nil && $0.pid == pid }
                ?? procs.first { $0.friendlyName.lowercased() == needle
                    || $0.rawName.lowercased().contains(needle) }
            let livePid = liveMatch?.pid ?? pid
            let energyMatch = EnergyStats.snapshot(limit: 200)
                .first { $0.pid == livePid || $0.name.lowercased() == needle }
            let diskMatch = EnergyStats.diskSnapshot(limit: 200)
                .first { $0.pid == livePid || $0.name.lowercased() == needle }
            let events = GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog)
                .filter {
                    $0.friendlyName.lowercased().contains(needle)
                        || $0.processName.lowercased().contains(needle)
                        || needle.contains($0.friendlyName.lowercased())
                }
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
            guardEvents = $0.3
            networkRows = $0.4
        }
    }
}
