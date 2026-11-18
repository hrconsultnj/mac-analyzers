import AppKit
import ServiceManagement
import SwiftUI
import AnalyzersKit
import UIComponents

/// Settings: the app's own configuration up top (how it looks, the sidebar's icons, open at login, the Updates state), then
/// one row for each preference screen, which opens over this one. The screens themselves (Memory, Storage, Notifications and
/// Schedule) are unchanged.
struct SettingsHubView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(UpdateState.self) private var updates
    @State private var appearance = AppearancePreference.stored
    @AppStorage(SidebarIconStyle.key) private var iconStyle = SidebarIconStyle.coloured
    /// Read from the system, the one place this is kept: Setup's "Open at Login" row reads and writes the same state.
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private static let screens: [(route: SettingsRoute, symbol: String, color: Color, summary: String)] = [
        (.memory, "memorychip", .blue, "The memory limit, the alerts, and the lists of what is never stopped or may be asked to quit."),
        (.storage, "internaldrive.fill", .indigo, "What the scheduled cleans may touch: caches, projects, worktrees, Downloads."),
        (.notifications, "bell.badge.fill", .red, "How alerts behave, and the buttons that fix them when they don't."),
        (.schedule, "calendar.badge.clock", .teal, "When each clean runs, and what always runs."),
    ]

    var body: some View {
        PaneScaffold(symbol: "gearshape.fill", color: .gray, title: Names.Screen.settings,
                     caption: "How Mac Analyzers looks and starts, and what each part of it may do.") {
            Section(Names.SettingsHub.appearance) {
                AppearancePicker(selection: $appearance)
                    .onChange(of: appearance) { _, choice in
                        UserDefaults.standard.set(choice.rawValue, forKey: AppearancePreference.key)
                        choice.apply()
                    }
            }
            Section {
                LabeledContent(Names.SettingsHub.sidebarIcons) {
                    Picker("", selection: $iconStyle) {
                        ForEach(SidebarIconStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Toggle(isOn: Binding(get: { opensAtLogin }, set: setLogin)) {
                    VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                        Text(Names.SettingsHub.openAtLogin)
                        Text(loginError ?? "Puts the menu-bar icon back after a restart. The background protection runs either way.")
                            .font(.caption).foregroundStyle(loginError == nil ? Color.secondary : Color.red)
                    }
                }
                Button { navigator.open(target: "update") } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                                Text(Names.Screen.updates)
                                Text(updateState).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "arrow.down.circle") }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text(Names.SettingsHub.general)
            }
            Section(Names.SettingsHub.configuration) {
                ForEach(Self.screens, id: \.route) { screen in
                    Button { navigator.push(.settings(screen.route)) } label: {
                        HStack(spacing: Tokens.Space.xl) {
                            IconTile(symbol: screen.symbol, color: screen.color, side: 28).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                                Text(screen.route.title)
                                Text(screen.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Tokens.Space.m)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// "Up to Date", "Update Available (2.73.1)", "Dev Build": the shared update state, the same words the sidebar's item uses.
    private var updateState: String {
        switch updates.summary {
        case .updateAvailable?: updates.latest.map { "\(Names.State.updateAvailable) (\($0))" } ?? Names.State.updateAvailable
        case .developmentBuild?: Names.State.developmentBuild
        case .upToDate?: Names.State.upToDate
        case nil: updates.build.versionText
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change it: \(error.localizedDescription)"
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
