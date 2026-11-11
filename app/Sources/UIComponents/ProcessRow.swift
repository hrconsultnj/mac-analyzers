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
    @State private var confirming = false
    @State private var refusal: String?

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
                Button(stopping ? "…" : (proc.isDev ? "Stop" : "Quit")) { confirming = true }
                .controlSize(.small)
                .disabled(stopping)
                .confirmationDialog("\(proc.isDev ? "Stop" : "Quit") \(proc.friendlyName)?",
                                    isPresented: $confirming, titleVisibility: .visible) {
                    Button(proc.isDev ? "Stop" : "Quit", role: .destructive, action: stop)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(proc.isDev
                         ? "It will be asked to stop. Anything it is doing is interrupted."
                         : ["It will be asked to quit. It will still ask before discarding unsaved work.",
                            MemoryStop.hostedNote(CodingAgentHosts.sessionsBelow(pid: proc.pid))]
                            .compactMap { $0 }.joined(separator: " "))
                }
                .alert("Left Alone", isPresented: Binding(get: { refusal != nil },
                                                          set: { if !$0 { refusal = nil } })) {
                    Button("OK") { refusal = nil }
                } message: {
                    Text(refusal ?? "")
                }
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

    private func stop() {
        stopping = true
        if case .refused(let why) = GuardControl.stopProcess(proc, identity: proc.identity) {
            refusal = why
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            afterStop()
            stopping = false
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
