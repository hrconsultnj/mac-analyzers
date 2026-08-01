import SwiftUI
import AnalyzersKit
import UIComponents

/// The settings window, System-Settings style: colored-tile sidebar on the
/// left, flat panes on the right. Logs is the one genuinely nested item —
/// a category of six sibling documents, expanded as sidebar children.
public struct SettingsTabsView: View {

    enum Pane: Hashable {
        case memory, storage, notifications, activity, log(LogKind), about
    }

    @State private var pane: Pane = .memory

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section("Configure") {
                    sidebarRow("Memory", "memorychip", .blue, .memory)
                    sidebarRow("Storage", "internaldrive.fill", .indigo, .storage)
                    sidebarRow("Notifications", "bell.badge.fill", .red, .notifications)
                }
                Section("Observe") {
                    sidebarRow("Activity", "list.bullet.rectangle.fill", .orange, .activity)
                    DisclosureGroup {
                        ForEach(LogKind.allCases) { kind in
                            sidebarRow(kind.title, kind.symbol, kind.tileColor, .log(kind))
                        }
                    } label: {
                        Label {
                            Text("Logs")
                        } icon: {
                            IconTile(symbol: "doc.text.magnifyingglass", color: .gray, side: 18)
                        }
                    }
                }
                Section {
                    sidebarRow("About", "questionmark.circle.fill", .gray, .about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            detailView
        }
        .frame(minWidth: 780, minHeight: 620)
        .onDisappear {
            // drop the Dock icon again once Settings closes (the menu-bar
            // Settings button flips us to .regular so the window fronts)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ color: Color, _ value: Pane) -> some View {
        Label {
            Text(title)
        } icon: {
            IconTile(symbol: symbol, color: color, side: 18)
        }
        .tag(value)
    }

    @ViewBuilder private var detailView: some View {
        switch pane {
        case .memory: MemorySettingsView()
        case .storage: StorageSettingsView()
        case .notifications: NotifySettingsView()
        case .activity: ActivitySettingsView()
        case .log(let kind): LogsSettingsView(kind: kind)
        case .about: AboutSettingsView()
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
            .buttonStyle(.borderedProminent)
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
