import SwiftUI
import AnalyzersKit
import UIComponents

/// Overview: where this Mac stands, answered without a click. Is anything wrong
/// (Needs Attention, only when true), what is running now, how memory and the
/// disk are, what the guard did, what the schedules do next, what the app did
/// this week. Each box is a summary; every number in it is a button that opens
/// the screen that explains it. The boxes sit in columns (`OverviewColumns`): three across
/// at 1400, two at 1100, one at 900, each row as tall as its tallest box.
///
/// This file is the screen's state and its composition. One job per file:
///   OverviewView+Alerts.swift      Needs Attention, Running Now and Scan Everything, across the full width
///   OverviewView+Memory.swift      pressure, memory in use and the three apps using the most
///   OverviewView+Storage.swift     free space, what can be reclaimed, what was freed
///   OverviewView+Guard.swift       the guard's state and its last event
///   OverviewView+Schedules.swift   the scheduled cleans and when they run
///   OverviewView+Events.swift      recent events, and this week's totals
///   OverviewBox.swift              the box, and the row that is one button with a chevron
struct OverviewView: View {

    @Environment(GuardLogStore.self) var store
    @Environment(JobStore.self) var jobs
    @Environment(UpdateState.self) var updates
    @Environment(Navigator.self) var navigator
    @Environment(ConfigStore.self) var config
    @State var week: TrendsSnapshot?
    @State var runway: ForecastModel.Runway?
    /// Why the last Resume did not work, in the store's own words.
    @State var resumeError: String?
    /// The census behind the memory box, read once off the main actor.
    @State var panel: MenuPanelModel?
    /// Why Scan Everything did not start, in words.
    @State var scanNotice: String?

    /// Everything the screen says, rebuilt from the stores each time they change.
    var model: OverviewModel {
        OverviewModel(.init(
            pressure: store.pressure, engine: store.engine, killsToday: store.killsToday,
            disk: store.disk, runwayText: runway?.text, runwayUrgent: runway?.urgent ?? false,
            reclaimableBytes: week?.latestReclaimableBytes ?? 0,
            thermalElevated: ThermalWatcher.shared.isElevated,
            update: (updates.channel == .releases && updates.isAvailable, updates.latest, updates.installed),
            events: store.events, guardPaused: store.guardPaused))
    }

    /// The screens Overview's boxes summarize, one row each.
    private static let areas: [HubArea] = [
        HubArea(title: Names.Screen.monitor, caption: "What is using your memory, and what you can stop.",
                symbol: "gauge.with.dots.needle.67percent", color: .blue, target: "monitor"),
        HubArea(title: Names.Screen.memoryGuard, caption: "What the guard has stopped, and the rules it follows.",
                symbol: "shield.lefthalf.filled", color: .green, target: "guard"),
        HubArea(title: Names.Screen.disk, caption: "Where the space is, and what each cleanup could give back.",
                symbol: "internaldrive.fill", color: .indigo, target: "disk"),
        HubArea(title: Names.Screen.activity, caption: "Every run, whoever started it.",
                symbol: "list.bullet.rectangle.fill", color: .orange, target: "activity"),
        HubArea(title: Names.Screen.trends, caption: "How memory and disk space have changed over time.",
                symbol: "chart.xyaxis.line", color: .teal, target: "trends"),
    ]

    var body: some View {
        let model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HubHeader(symbol: "gauge.with.dots.needle.33percent", color: .blue, title: Names.Screen.overview,
                          caption: "Where your Mac stands right now, and the places that explain it.", areas: Self.areas)
                alerts(model)
                scanMessage
                running
                OverviewColumns {
                    memoryBox
                    storageBox(model)
                    guardBox(model)
                    schedulesBox
                    eventsBox(model)
                    weekBox
                }
            }
            .scenePadding()
        }
        .navigationTitle(Names.Screen.overview)
        .navigationSubtitle("Your Mac at a glance")
        .toolbar {
            ToolbarItem {
                Button { scanEverything() } label: { Label(Names.Overview.scanEverything, systemImage: "sparkle.magnifyingglass") }
                    .labelStyle(.titleAndIcon)
                    .help("Preview every cleanup and write every report, one after another; nothing is changed")
                    .disabled(jobs.batchIsActive)
            }
            .toolbarRank(.primary)
        }
        .task {
            store.reload()
            await awaitLoad({ TrendsModel.snapshot(period: .week) }, key: "overview.week") { week = $0 }
            await awaitLoad({ ForecastModel.diskRunway() }, key: "overview.runway") { runway = $0 }
        }
        .task {
            panel = await Task.detached(priority: .utility) {
                MenuPanelModel(census: MemoryCensus.take(), limit: 3)
            }.value
        }
    }
}
