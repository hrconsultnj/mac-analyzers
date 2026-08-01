import SwiftUI
import AnalyzersKit
import UIComponents

/// The settings window, System-Settings style: colored-tile sidebar on the
/// left, flat panes on the right. Logs is the one genuinely nested item —
/// a category of six sibling documents, expanded as sidebar children.
public struct SettingsTabsView: View {

    enum Pane: Hashable {
        case memory, storage, notifications, schedule, monitor, trends,
             activity, logs, log(LogKind), about, update
    }

    @State private var pane: Pane = .memory
    /// Typed path for the Logs stack (landing → log → run/forensics).
    @State private var logsPath: [LogRoute] = []
    /// Typed path for the per-child stacks (.log(kind) sidebar entries).
    @State private var childPath: [LogRoute] = []
    @State private var updateAvailable = false

    // MARK: - browser-style history (the System Settings model)
    // The chevrons are ALWAYS in the toolbar and track EVERY navigation —
    // sidebar switches and drill-ins alike — as snapshots in a history
    // array with a cursor. Back/forward time-travel the whole nav state.

    private struct NavSnapshot: Equatable {
        let pane: Pane
        let logsPath: [LogRoute]
        let childPath: [LogRoute]
    }

    @State private var history: [NavSnapshot] = []
    @State private var historyIndex = -1
    /// True while a snapshot is being applied — suppresses recording and the
    /// pane-switch path reset so restoration isn't wiped by its own onChange.
    @State private var isTimeTraveling = false
    @State private var recordQueued = false

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < history.count - 1 }

    /// Coalesce per runloop tick: one user action can fire several onChange
    /// hooks (pane + path reset) — record the SETTLED state once.
    private func scheduleRecord() {
        guard !isTimeTraveling, !recordQueued else { return }
        recordQueued = true
        DispatchQueue.main.async {
            recordQueued = false
            guard !isTimeTraveling else { return }
            let snap = NavSnapshot(pane: pane, logsPath: logsPath, childPath: childPath)
            if history.indices.contains(historyIndex), history[historyIndex] == snap { return }
            history = Array(history.prefix(historyIndex + 1)) + [snap]
            historyIndex = history.count - 1
        }
    }

    private func travel(to index: Int) {
        guard history.indices.contains(index) else { return }
        isTimeTraveling = true
        historyIndex = index
        let snap = history[index]
        pane = snap.pane
        logsPath = snap.logsPath
        childPath = snap.childPath
        DispatchQueue.main.async { isTimeTraveling = false }
    }

    public init() {}

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // sticky brand card above the sections — the System-Settings
                // sidebar-header pattern (icon · name · version)
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mac Analyzers")
                            .font(.headline)
                        Text("v\(UpdateChecker.installedVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 10)

                sidebarList
            }
            .listStyle(.sidebar)
            // System Settings' sidebar is never collapsible — no toggle
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
        } detail: {
            detailView
                // SHELL-level navigation, the System Settings anatomy: a
                // permanent back/forward pair leading the toolbar strip,
                // walking the recorded history — never a per-pane bar.
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button {
                            travel(to: historyIndex - 1)
                        } label: {
                            Image(systemName: "chevron.left").fontWeight(.semibold)
                        }
                        .disabled(!canGoBack)
                        .help("Back")
                        Button {
                            travel(to: historyIndex + 1)
                        } label: {
                            Image(systemName: "chevron.right").fontWeight(.semibold)
                        }
                        .disabled(!canGoForward)
                        .help("Forward")
                    }
                }
        }
        .frame(minWidth: 780, minHeight: 620)
        .onChange(of: pane) {
            if !isTimeTraveling { childPath = [] }
            scheduleRecord()
        }
        .onChange(of: logsPath) { scheduleRecord() }
        .onChange(of: childPath) { scheduleRecord() }
        .onAppear(perform: scheduleRecord)
        .onReceive(NotificationCenter.default.publisher(for: NotifyChannel.openPaneInternal)) { note in
            // deep links from the menu bar ("Guard log" → the guard-log pane)
            guard let target = note.userInfo?["target"] as? String else { return }
            if target.hasPrefix("log:"),
               let kind = LogKind(rawValue: String(target.dropFirst(4))) {
                pane = .log(kind)
            } else {
                switch target {
                case "logs": pane = .logs; logsPath = []
                case "activity": pane = .activity
                case "monitor": pane = .monitor
                case "trends": pane = .trends
                case "schedule": pane = .schedule
                case "update": pane = .update
                default: break
                }
            }
        }
        .onDisappear {
            // drop the Dock icon again once Settings closes (the menu-bar
            // Settings button flips us to .regular so the window fronts)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var sidebarList: some View {
        List(selection: $pane) {
            Section {
                sidebarRow("Memory", "memorychip", .blue, .memory)
                sidebarRow("Storage", "internaldrive.fill", .indigo, .storage)
                sidebarRow("Notifications", "bell.badge.fill", .red, .notifications)
            } header: {
                sectionHeader("CONFIGURE")
            }
            Section {
                sidebarRow("Schedule", "calendar.badge.clock", .teal, .schedule)
            } header: {
                sectionHeader("SCHEDULE")
            }
            Section {
                sidebarRow("Monitor", "gauge.with.dots.needle.67percent", .orange, .monitor)
                sidebarRow("Trends", "chart.xyaxis.line", .mint, .trends)
                sidebarRow("Activity", "list.bullet.rectangle.fill", .orange, .activity)
                // both worlds: the Logs ROW opens the nested landing
                // screen; the disclosure children jump straight to a log
                DisclosureGroup {
                    ForEach(LogKind.allCases) { kind in
                        sidebarRow(kind.title, kind.symbol, kind.tileColor, .log(kind))
                    }
                } label: {
                    sidebarRow("Logs", "doc.text.magnifyingglass", .gray, .logs)
                }
            } header: {
                sectionHeader("OBSERVE")
            }
            Section {
                sidebarRow("About", "questionmark.circle.fill", .gray, .about)
                HStack {
                    sidebarRow("Update", "arrow.down.circle.fill", .green, .update)
                    if updateAvailable {
                        Spacer()
                        Text("1")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.red, in: Circle())
                    }
                }
                .tag(Pane.update)
            }
        }
        .task {
            if let latest = await UpdateChecker.latestVersion() {
                updateAvailable = UpdateChecker.isNewer(latest, than: UpdateChecker.installedVersion)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ color: Color, _ value: Pane) -> some View {
        Label {
            Text(title)
        } icon: {
            // explicit tile size — Tahoe's default sidebar icons undershoot
            // System Settings' scale (DTS-acknowledged bug)
            IconTile(symbol: symbol, color: color, side: 20)
        }
        .tag(value)
    }

    @ViewBuilder private var detailView: some View {
        switch pane {
        case .memory: MemorySettingsView()
        case .storage: StorageSettingsView()
        case .notifications: NotifySettingsView()
        case .schedule: ScheduleSettingsView()
        case .monitor: MonitorSettingsView()
        case .trends: TrendsSettingsView()
        case .activity: ActivitySettingsView()
        case .logs:
            // landing screen at the root; a log and then a run push on top
            NavigationStack(path: $logsPath) {
                LogsHomeView()
                    .navigationDestination(for: LogRoute.self) { route in
                        logDestination(route)
                            .navigationBarBackButtonHidden(true)
                    }
            }
        case .log(let kind):
            // sidebar-child entry: its OWN stack ROOTED at the log pane — no
            // programmatic path surgery at all (replacing a path mid-animation
            // dropped pushes and landed users back on the landing screen).
            // Switching children just re-roots the stack with the new kind.
            NavigationStack(path: $childPath) {
                LogsSettingsView(kind: kind)
                    .navigationDestination(for: LogRoute.self) { route in
                        logDestination(route)
                            .navigationBarBackButtonHidden(true)
                    }
            }
            .id(kind)
        case .about: AboutSettingsView()
        case .update: UpdateSettingsView()
        }
    }

    @ViewBuilder private func logDestination(_ route: LogRoute) -> some View {
        switch route {
        case .log(let kind): LogsSettingsView(kind: kind)
        case .run(let run): RunDetailView(route: run)
        case .forensics(let forensics): ForensicsDetailView(route: forensics)
        }
    }
}

/// Save-bar shared by the panes: prominent Save, transient confirmation,
/// and a visible error instead of a silent failure.
struct SaveBar: View {
    let onSave: () throws -> Void
    @State private var savedAt: Date?
    @State private var errorText: String?

    var body: some View {
        HStack {
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(2)
            } else if let savedAt {
                Label("Saved \(savedAt.formatted(.dateTime.hour().minute().second()))",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
            Spacer()
            Button("Save") {
                do {
                    try onSave()
                    savedAt = .now
                    errorText = nil
                } catch {
                    errorText = "Could not save: \(error.localizedDescription)"
                }
            }
            .buttonStyle(.glassProminent)      // the one standout action per pane
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: .command)
        }
    }
}

/// Reusable editor for a list of strings (protected apps, globs, …).
struct StringListEditor: View {
    let title: String
    let prompt: String
    @Binding var items: [String]
    @State private var newItem = ""
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            List(selection: $selection) {
                ForEach(items, id: \.self) { item in
                    Text(item).tag(item)
                }
            }
            .frame(minHeight: 72, maxHeight: 110)
            .border(.separator)
            HStack {
                TextField(prompt, text: $newItem)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addItem)
                Button("Add", action: addItem)
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Remove") {
                    if let selection { items.removeAll { $0 == selection } }
                    selection = nil
                }
                .disabled(selection == nil)
            }
        }
    }

    private func addItem() {
        let trimmed = newItem.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !items.contains(trimmed) else { return }
        items.append(trimmed)
        newItem = ""
    }
}
