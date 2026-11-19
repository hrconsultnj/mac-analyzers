import SwiftUI
import AppKit
import AnalyzersKit
import UIComponents

/// The top of Updates, in the three states of System Settings → Software Update.
/// While a check runs, one line and a spinner. When nothing newer is available, a check mark, what you have,
/// and Check for Updates. When a version is available, the app icon and the install button of the channel in
/// use — Check for Updates is not shown, the same way Software Update hides it once Update Now is there.
struct UpdateStatusCard: View {
    let updates: UpdateState
    let installTitle: String

    var body: some View {
        if updates.phase == .checking {
            HStack(spacing: Tokens.Space.m) {
                Text("Checking for Updates…")
                Spacer(minLength: Tokens.Space.xl)
                ProgressView().controlSize(.small)
            }
            .padding(.vertical, Tokens.Space.s)
        } else if updates.isAvailable || updates.phase == .installing {
            headline {
                // fixed: the app's icon is the one thing here that has a size of its own
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: Tokens.Icon.hero + 20, height: Tokens.Icon.hero + 20)
                    .accessibilityHidden(true)
            } trailing: {
                Button(installTitle) { updates.requestInstall() }
                    .buttonStyle(.borderedProminent)
                    .disabled(updates.phase == .installing)
            }
        } else {
            headline {
                // fixed: the same slot as the app icon, so the row does not jump when a check finishes
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: Tokens.Icon.hero))
                    .foregroundStyle(.green)
                    .frame(width: Tokens.Icon.hero + 20, height: Tokens.Icon.hero + 20)
                    .accessibilityHidden(true)
            } trailing: {
                Button(Names.Update.checkForUpdates + "…") {
                    Task { await UpdateCoordinator.shared.checkForUpdates() }
                }
                .disabled(!UpdateCoordinator.shared.isReady)
            }
        }
    }

    private func headline<Icon: View, Trailing: View>(@ViewBuilder icon: () -> Icon, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Tokens.Space.xl) {
            icon()
            VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                Text(updates.statusTitle).font(.title3.weight(.semibold))
                Text(updates.statusDetail).font(.callout).foregroundStyle(.secondary)
                if let checked = updates.checkedAt {
                    // re-read every half minute, so "2 min ago" does not go stale on a screen left open
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Names.Update.checked(Self.ago(checked, now: context.date)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: Tokens.Space.xl)
            trailing()
        }
        .padding(.vertical, Tokens.Space.s)
    }

}

/// The lines of an update running in the background. Shown on the status card, in place of a Terminal window.
struct UpdateInstallLog: View {
    let updates: UpdateState

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            if updates.phase == .installing {
                HStack(spacing: Tokens.Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Updating… Mac Analyzers closes and opens again when this finishes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("The update stopped before it finished. You can try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !updates.installLines.isEmpty {
                Text(updates.installLines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}

private extension UpdateStatusCard {
    /// "just now", "2 minutes ago".
    static func ago(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 45 { return "just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}
