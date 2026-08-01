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

/// Full-width segmented tabs: equal-width filled pills spanning the whole
/// row (macOS's native segmented picker sizes to content and won't stretch).
public struct FullWidthSegments<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option

    public init(options: [(Option, String)], selection: Binding<Option>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { option, label in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(selected ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity)
    }
}

/// Single-select filter chips with live counts ("Killed (4)") — the same
/// visual language as BadgeCapsule: tinted when idle, filled when selected.
public struct FilterChipsBar<Option: Hashable>: View {
    public struct Chip {
        let option: Option
        let label: String
        let count: Int
        let color: Color

        public init(_ option: Option, _ label: String, count: Int, color: Color) {
            self.option = option
            self.label = label
            self.count = count
            self.color = color
        }
    }

    let chips: [Chip]
    @Binding var selection: Option

    public init(chips: [Chip], selection: Binding<Option>) {
        self.chips = chips
        self._selection = selection
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.option) { chip in
                    let selected = chip.option == selection
                    Button {
                        selection = chip.option
                    } label: {
                        Text(chip.count > 0 ? "\(chip.label) (\(chip.count))" : chip.label)
                            .font(.caption.weight(selected ? .bold : .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(selected ? chip.color : chip.color.opacity(0.15),
                                        in: Capsule())
                            .foregroundStyle(selected ? Color.white : chip.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Liveness chip: green dot + ACTIVE while the row's process is still the
/// same running program; dimmed ENDED once it's gone (killed, quit, or the
/// pid was recycled). One component for the menu and the settings panes.
public struct LiveStateChip: View {
    let active: Bool

    public init(active: Bool) { self.active = active }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 5, height: 5)
            Text(active ? "ACTIVE" : "ENDED")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(active ? Color.green : Color.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((active ? Color.green : Color.gray).opacity(0.16), in: Capsule())
    }
}

/// Settings-pane-weight data row: leading icon (tile or real app icon),
/// title/subtitle, trailing value + liveness chip + badge — the "card"
/// anatomy from the Apple Storage Management reference.
public struct DataCard: View {
    let icon: AnyView
    let title: String
    let subtitle: String?
    let trailing: String?
    let badge: (text: String, color: Color)?
    let live: Bool?

    public init(symbol: String, color: Color, title: String,
                subtitle: String? = nil, trailing: String? = nil,
                badge: (text: String, color: Color)? = nil,
                live: Bool? = nil) {
        self.icon = AnyView(IconTile(symbol: symbol, color: color, side: 20))
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.badge = badge
        self.live = live
    }

    public init(appIcon: NSImage, title: String,
                subtitle: String? = nil, trailing: String? = nil,
                badge: (text: String, color: Color)? = nil,
                live: Bool? = nil) {
        self.icon = AnyView(Image(nsImage: appIcon).resizable().frame(width: 20, height: 20))
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.badge = badge
        self.live = live
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let live {
                LiveStateChip(active: live)
            }
            if let badge {
                BadgeCapsule(text: badge.text, color: badge.color)
            }
        }
        .padding(.vertical, 3)
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
            IconTile(symbol: symbol, color: color, side: 44)
            Text(title).font(.title2.weight(.bold))
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
