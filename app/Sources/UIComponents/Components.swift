import AppKit
import AnalyzersKit
import SwiftUI

/// Small colored badge (KILLED/DRY/DONE…) shared by menu rows, log run rows
/// and detail rows.
public struct BadgeCapsule: View {
    let text: String
    let color: Color

    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

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
            Text(proc.residentText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(proc.residentMB > 4096 ? .orange : .secondary)
                .frame(width: 54, alignment: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                Text(proc.friendlyName).font(.callout).lineLimit(1)
                if proc.friendlyName != proc.rawName {
                    Text("\(proc.rawName.prefix(56)) · pid \(proc.pid)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
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
                  ? "Stop this dev process (SIGTERM — it can restart from your next build/session)"
                  : "Ask this app to quit gracefully — same as ⌘Q, save dialogs still appear")
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

/// System-Settings-style colored icon tile — the visual language of the
/// Settings sidebar, reused across the menu and the settings window.
public struct IconTile: View {
    let symbol: String
    let color: Color
    let side: CGFloat

    public init(symbol: String, color: Color, side: CGFloat = 16) {
        self.symbol = symbol
        self.color = color
        self.side = side
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: side * 0.24))
    }
}

/// General-pane-style header: large tile, title, one-line description —
/// opens every settings pane so they all share the same anatomy.
public struct PaneHeader: View {
    let symbol: String
    let color: Color
    let title: String
    let caption: String

    public init(symbol: String, color: Color, title: String, caption: String) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.caption = caption
    }

    public var body: some View {
        VStack(spacing: 6) {
            IconTile(symbol: symbol, color: color, side: 34)
            Text(title).font(.title3.weight(.semibold))
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.horizontal, 24)
    }
}
