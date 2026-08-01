import SwiftUI
import AnalyzersKit
import UIComponents

/// The settings window, System-Settings style: colored-tile sidebar on the
/// left, flat panes on the right. Logs is the one genuinely nested item —
/// a category of six sibling documents, expanded as sidebar children.
public struct SettingsTabsView: View {

    enum Pane: Hashable {
        case memory, storage, notifications, schedule, monitor,
             activity, logs, log(LogKind), about, update
    }

    @State private var pane: Pane = .memory
    /// State-backed path for the Logs stack (NavigationPath: it holds both
    /// LogKind pushes and RunRoute pushes for the nested run screens).
    @State private var logsPath = NavigationPath()

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
        }
        .frame(minWidth: 780, minHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: logsHomeSignal)) { _ in
            // explicit back intent from the "All Logs" button: land on the
            // landing screen AND move the sidebar highlight to Logs
            pane = .logs
            logsPath = NavigationPath()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotifyChannel.openPaneInternal)) { note in
            // deep links from the menu bar ("Guard log" → the guard-log pane)
            guard let target = note.userInfo?["target"] as? String else { return }
            if target.hasPrefix("log:"),
               let kind = LogKind(rawValue: String(target.dropFirst(4))) {
                pane = .log(kind)
            } else {
                switch target {
                case "logs": pane = .logs; logsPath = NavigationPath()
                case "activity": pane = .activity
                case "monitor": pane = .monitor
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
                sidebarRow("Update", "arrow.down.circle.fill", .green, .update)
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
        case .activity: ActivitySettingsView()
        case .logs:
            // landing screen at the root; a log and then a run push on top
            NavigationStack(path: $logsPath) {
                LogsHomeView()
                    .navigationDestination(for: LogKind.self) { k in
                        LogsSettingsView(kind: k)
                    }
                    .navigationDestination(for: RunRoute.self) { route in
                        RunDetailView(route: route)
                    }
            }
        case .log(let kind):
            // sidebar-child entry: its OWN stack ROOTED at the log pane — no
            // programmatic path surgery at all (replacing a path mid-animation
            // dropped pushes and landed users back on the landing screen).
            // Switching children just re-roots the stack with the new kind.
            NavigationStack {
                LogsSettingsView(kind: kind)
                    .navigationDestination(for: RunRoute.self) { route in
                        RunDetailView(route: route)
                    }
            }
            .id(kind)
        case .about: AboutSettingsView()
        case .update: UpdateSettingsView()
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
