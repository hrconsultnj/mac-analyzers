import SwiftUI
import AnalyzersKit
import UIComponents
#if canImport(ProKit)
import ProKit
#endif

/// About pane: the in-app documentation — how the guard decides, what is
/// (and deliberately isn't) measured. Same PaneScaffold as every pane.
struct AboutSettingsView: View {
    var body: some View {
        PaneScaffold(symbol: "questionmark.circle.fill", color: .gray, title: "About",
                     caption: "How Mac Analyzers decides, measures, and writes everything down.") {
            section("What the guard measures", [
                "Resident RAM (rss): the physical memory a process occupies right now. That is the number every size in this app shows, and the one the guard acts on.",
                "Activity Monitor's \"Memory\" column also counts compressed and swapped-out pages — so a process can show 7+ GB there while its resident size sits under your cap. That is why a big process can survive when memory pressure is low: macOS already compressed it.",
                "VRAM / GPU memory is deliberately NOT considered — macOS offers no public per-process GPU-memory accounting, and on Apple Silicon's unified memory the meaningful pressure signal is the one the guard already watches.",
            ])
            section("When something gets stopped", [
                "Scope: only dev tooling is ever stopped automatically — node, npm, bun, tsx, deno, Next.js/Vite/Webpack/Turbo dev servers, Vitest/Jest, Playwright and headless browsers. Real apps, and anything on your protected list, are NEVER stopped automatically.",
                "Hard cap: every 15 seconds the single biggest touchable process is checked; over the cap → stopped at any pressure level (60 s cooldown), with a forensics report written first. You can switch this to notify-only in Memory settings.",
                "Critical pressure: the system says it is drowning → the biggest touchable process over 500 MB is stopped (also switchable to notify-only).",
                "Spikes and CPU hogs only ever notify. The Stop/Quit buttons in the Monitor tab are different: those are YOUR actions, so they work on any process — same as Activity Monitor.",
            ])
            section("Where everything is written down", [
                "Every action lands in the guard log; every clean writes a full report under ~/mac-analyzers/reports/. Clicking any notification opens the app or the exact log behind it.",
                "The menu's Clear button only resets what's displayed — the logs are never trimmed by the app.",
            ])
            section("The engine", [
                "The watching and cleaning is done by plain shell scripts run by macOS's own scheduler (launchd) — this app is the control surface. Settings write a managed block in config.local.sh; anything you hand-edit outside that block is preserved.",
            ])
            #if canImport(ProKit)
            ProAboutSlot()
            #endif
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Turn off or remove")
                        Text("Pause it, switch off background protection, or remove it from this Mac — with proof that it worked.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open…") {
                        NotificationCenter.default.post(
                            name: NotifyChannel.openPaneInternal, object: nil,
                            userInfo: ["target": "uninstall"])
                    }
                }
            }
            Section("Share") {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mac Health Report")
                        Text("A one-page HTML summary of the last 30 days — for IT, family, or a buyer. Generated locally.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Export…") { HealthReport.save() }
                }
            }
            Section {
                HStack {
                    Link("README on GitHub",
                         destination: URL(string: "https://github.com/hrconsultnj/mac-analyzers")!)
                    Spacer()
                    Text("Mac Analyzers \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Collapsed by default (first section expanded) — the prose is worth
    /// having, but scannability beats a wall of text.
    private func section(_ title: String, _ points: [String]) -> some View {
        Section {
            DisclosureGroup(isExpanded: .constant(title.hasPrefix("What the guard")).animation()) {
                ForEach(points, id: \.self) { point in
                    Text(point)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } label: {
                Text(title).font(.callout.weight(.medium))
            }
        }
    }
}
