import SwiftUI
import AnalyzersKit

/// The tabbed Settings window: Memory / Storage / Notifications.
/// Saving writes the managed block in config.local.sh; memory saves also
/// restart the guard agent (it reads tunables once at startup).
public struct SettingsTabsView: View {
    public init() {}

    public var body: some View {
        TabView {
            MemorySettingsView()
                .tabItem { Label("Memory", systemImage: "memorychip") }
            StorageSettingsView()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            NotifySettingsView()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            ActivitySettingsView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            LogsSettingsView()
                .tabItem { Label("Logs", systemImage: "doc.text.magnifyingglass") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "questionmark.circle") }
        }
        .frame(width: 640, height: 620)
        .onDisappear {
            // drop the Dock icon again once Settings closes (the menu-bar
            // Settings button flips us to .regular so the window fronts)
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Save-bar shared by the tabs: Save button, transient confirmation,
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
