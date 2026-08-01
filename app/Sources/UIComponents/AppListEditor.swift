import AppKit
import AnalyzersKit
import SwiftUI

/// List editor backed by REALITY: rows show the app's actual icon, and the
/// Add sheet is a searchable picker over installed apps (or, for process-name
/// fragments, over what's running right now) — no more guessing names into a
/// blind text field. A custom-entry field stays for the edge cases.
public struct AppListEditor: View {

    public enum Mode {
        case installedApps      // reclaim list, stale apps
        case processFragments   // protected processes (ps-args fragments)
    }

    let title: String
    let mode: Mode
    let minHeight: CGFloat
    let maxHeight: CGFloat
    @Binding var items: [String]
    @State private var selection: String?
    @State private var showPicker = false

    public init(title: String, mode: Mode, items: Binding<[String]>,
                minHeight: CGFloat = 76, maxHeight: CGFloat = 120) {
        self.title = title
        self.mode = mode
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self._items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            List(selection: $selection) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 6) {
                        itemIcon(item)
                        Text(item)
                    }
                    .tag(item)
                }
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .border(.separator)
            HStack {
                Button {
                    showPicker = true
                } label: {
                    Label("Add…", systemImage: "plus")
                }
                Button("Remove") {
                    if let selection { items.removeAll { $0 == selection } }
                    selection = nil
                }
                .disabled(selection == nil)
                Spacer()
            }
        }
        .sheet(isPresented: $showPicker) {
            AppPickerSheet(mode: mode, existing: items) { picked in
                if !items.contains(picked) { items.append(picked) }
            }
        }
    }

    @ViewBuilder private func itemIcon(_ item: String) -> some View {
        if let app = Self.installedByName[item.lowercased()] {
            Image(nsImage: iconFor(path: app.path))
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            IconTile(symbol: mode == .installedApps ? "app.dashed" : "terminal.fill",
                     color: .gray)
        }
    }

    private static let installedByName: [String: InstalledApp] =
        Dictionary(AppCatalog.installedApps().map { ($0.name.lowercased(), $0) },
                   uniquingKeysWith: { first, _ in first })

    private func iconFor(path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

/// The searchable Add sheet.
private struct AppPickerSheet: View {
    let mode: AppListEditor.Mode
    let existing: [String]
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var custom = ""
    @State private var apps: [InstalledApp] = []
    @State private var running: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .installedApps ? "Pick an installed app" : "Pick a running process")
                .font(.headline)
            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder)

            List {
                if mode == .installedApps {
                    ForEach(filteredApps) { app in
                        Button {
                            onPick(app.name)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: icon(app.path))
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(app.name)
                                Spacer()
                                if existing.contains(app.name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(filteredRunning, id: \.self) { name in
                        Button {
                            onPick(name)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                IconTile(symbol: "terminal.fill", color: .blue)
                                Text(name)
                                Spacer()
                                if existing.contains(name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 260)

            HStack {
                TextField(mode == .installedApps ? "Or type a name…" : "Or type a fragment…",
                          text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCustom)
                Button("Add", action: addCustom)
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 420, height: 430)
        .onAppear {
            if mode == .installedApps {
                apps = AppCatalog.installedApps()
            } else {
                running = AppCatalog.runningNameSuggestions()
            }
        }
    }

    private var filteredApps: [InstalledApp] {
        search.isEmpty ? apps
            : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var filteredRunning: [String] {
        search.isEmpty ? running
            : running.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private func addCustom() {
        let trimmed = custom.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onPick(trimmed)
        dismiss()
    }

    private func icon(_ path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 20, height: 20)
        return icon
    }
}
