import AppKit
import AnalyzersKit
import SwiftUI

/// Live-process row: real app icon (or a dev-tool tile), size, friendly +
/// raw identity, and a user-initiated Stop/Quit — shared by the menu's
/// Memory/Monitor tabs and the Settings Monitor pane.
public struct ProcessRow: View {
    let proc: LiveProcess
    let afterStop: () -> Void
    @State private var stopping = false

    public init(proc: LiveProcess, afterStop: @escaping () -> Void) {
        self.proc = proc
        self.afterStop = afterStop
    }

    public var body: some View {
        HStack(spacing: 6) {
            processIcon
                .accessibilityHidden(true)  // decorative — friendlyName below already names it
            Text(proc.memoryText)
                // weight carries the "large" signal too — colour alone misses colourblind users
                .font(.callout.monospacedDigit().weight(proc.memoryMB > 4096 ? .semibold : .regular))
                .foregroundStyle(proc.memoryMB > 4096 ? .orange : .secondary)
                .frame(width: 62, alignment: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                Text(proc.friendlyName).font(.callout).lineLimit(1)
                if proc.friendlyName != proc.rawName {
                    Text("\(proc.rawName.prefix(56)) · pid \(proc.pid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if proc.canQuit {
                Button(stopping ? "…" : (proc.isDev ? "Stop" : "Quit")) {
                    stopping = true
                    GuardControl.stopProcess(proc)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        afterStop()
                        stopping = false
                    }
                }
                .controlSize(.small)
                .disabled(stopping)
                .help(proc.isDev
                      ? "Stops this dev process — it's asked to quit, so it can restart on its own next build or session. (Technically: SIGTERM, not a forced kill.)"
                      : "Ask this app to quit gracefully — same as ⌘Q, save dialogs still appear")
            } else {
                // part of macOS: either the request can't reach it, or it
                // would take the session down with it (see LiveProcess.canQuit)
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Part of macOS — not something to quit from here")
                    .accessibilityLabel("Part of macOS, not quittable here")
            }
        }
    }

    @ViewBuilder private var processIcon: some View {
        if !proc.isDev,
           let icon = NSRunningApplication(processIdentifier: pid_t(proc.pid))?.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            IconTile(symbol: proc.isDev ? "hammer.fill" : "gearshape.fill",
                     color: proc.isDev ? .blue : .gray)
        }
    }
}
