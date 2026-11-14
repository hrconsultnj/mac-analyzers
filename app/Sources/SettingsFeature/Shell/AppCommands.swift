import SwiftUI
import AnalyzersKit

/// The menu bar for the main window: the standard sidebar and toolbar sets,
/// a Go menu over the navigator, and View items that a screen can drive.
/// Items are disabled, never hidden, when they do not apply.
public struct AppCommands: Commands {
    @FocusedValue(\.navigator) private var navigator
    @FocusedValue(\.screenActions) private var screen
    @FocusedValue(\.scopeTabs) private var tabs
    @FocusedValue(\.sidebarCommands) private var sidebar

    public init() {}

    public var body: some Commands {
        // The system's Show/Hide Sidebar acts through the responder chain on a split view controller; the window's own
        // visibility state is what the toolbar button and the hover overlay read, so the menu flips THAT, with the
        // platform's shortcut (Control-Command-S; Command-B is Bold). Enter/Exit Full Screen is not re-added: AppKit
        // supplies its own for a window that can go full screen, so a second one here would show twice.
        CommandGroup(replacing: .sidebar) {
            Button(sidebar?.shown == false ? Names.Sidebar.show : Names.Sidebar.hide) { sidebar?.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(sidebar == nil)
        }
        ToolbarCommands()

        // a plain Window scene does not get Cmd-, for free the way the
        // Settings scene does; it opens the same window it always has
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsOpener.open() }
                .keyboardShortcut(",", modifiers: .command)
        }

        // Help: the Welcome flow again, from the first step
        CommandGroup(after: .help) {
            Button(Names.Welcome.showWelcomeAgain) { WelcomeRequest.open(.again) }
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Refresh") { screen?.refresh?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(screen?.refresh == nil)
            Button("Find") { screen?.find?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(screen?.find == nil)
            // the focused screen's category tabs, Command-1 to Command-6; disabled,
            // never hidden, on a screen with no tabs
            Divider()
            ForEach(0..<6, id: \.self) { index in
                Button(tabs?.titles[safe: index] ?? "Category \(index + 1)") { tabs?.select(index) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(tabs?.titles.indices.contains(index) != true)
            }
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
            // Control-Command: Command-1 to Command-6 belong to the screen's tabs
            button.keyboardShortcut(key, modifiers: [.command, .control])
        } else {
            button
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
