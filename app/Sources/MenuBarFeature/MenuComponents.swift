import SwiftUI
import AppKit
import AnalyzersKit
import UIComponents

/// Finder-style capacity bar: used fill over a track, color escalating with
/// fullness. (A per-category segmented bar like the system Storage pane
/// needs a full-disk scan — the storage analyzer's report has that detail;
/// this bar answers the at-a-glance question.)
struct CapacityBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 7)
    }

    private var color: Color {
        fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .blue
    }
}

/// Live-process row: real app icon (or a dev-tool tile), size, friendly +
/// raw identity, and a user-initiated Stop/Quit — the "don't make me open
/// Activity Monitor" button.
struct ProcessRow: View {
    let proc: LiveProcess
    let afterStop: () -> Void
    @State private var stopping = false

    var body: some View {
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
            .controlSize(.regular)
            .disabled(stopping)
            .help(proc.isDev
                  ? "Stop this dev process (SIGTERM — it can restart from your next build/session)"
                  : "Ask this app to quit gracefully — same as ⌘Q, save dialogs still appear")
        }
    }

    /// The app's REAL icon when macOS knows it (GUI apps/helpers); a colored
    /// tile for headless dev tooling.
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

/// Two-line event row: friendly what-happened on top, raw identity +
/// mechanics + time underneath. Click opens the guard log.
struct EventRow: View {
    let event: GuardEvent

    var body: some View {
        Button {
            GuardControl.openLog(AnalyzersPaths.guardLog)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.caption)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.callout)
                        .foregroundStyle(color)
                        .lineLimit(1)
                    Text(subtitleWithTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .help(event.raw)
    }

    private var subtitleWithTime: String {
        let time = event.date.formatted(.dateTime.hour().minute())
        return event.subtitle.isEmpty ? time : "\(event.subtitle) · \(time)"
    }

    private var symbol: String {
        switch event.kind {
        case .killed: "xmark.octagon.fill"
        case .spike: "arrow.up.right"
        case .warning: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch event.kind {
        case .killed: .red
        case .spike, .warning: .orange
        }
    }
}
