import SwiftUI
import AnalyzersKit

/// The menu bar for the main window: the standard sidebar and toolbar sets,
/// a Go menu over the navigator, and View items that a screen can drive.
/// Items are disabled, never hidden, when they do not apply.
public struct AppCommands: Commands {
    @FocusedValue(\.navigator) private var navigator
    @FocusedValue(\.screenActions) private var screen

    public init() {}

    public var body: some Commands {
        SidebarCommands()
        ToolbarCommands()

        // a plain Window scene does not get Cmd-, for free the way the
        // Settings scene does; it opens the same window it always has
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsOpener.open() }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Refresh") { screen?.refresh?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(screen?.refresh == nil)
            Button("Find") { screen?.find?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(screen?.find == nil)
        }

        CommandMenu("Go") {
            Button("Back") { navigator?.back() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(navigator?.canGoBack != true)
            Button("Forward") { navigator?.forward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(navigator?.canGoForward != true)
            Divider()
            goItem("Overview", OverviewGroup.overview, key: "1")
            goItem("Activity", OverviewGroup.activity, key: "2")
            goItem("Monitor", MemoryGroup.monitor, key: "3")
            goItem("Disk", StorageGroup.disk, key: "4")
            goItem("Setup", OverviewGroup.setup)
        }
    }

    @ViewBuilder
    private func goItem(_ title: String, _ section: SectionID, key: KeyEquivalent? = nil) -> some View {
        let button = Button(title) { navigator?.select(section) }
            .disabled(navigator == nil)
        if let key {
            button.keyboardShortcut(key, modifiers: .command)
        } else {
            button
        }
    }
}
