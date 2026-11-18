import SwiftUI
import AppKit
import AnalyzersKit
import UIComponents

/// The top of Updates, in the shape of the system's Software Update: the app's icon, what the state is ("Mac Analyzers is
/// up to date", "Mac Analyzers 2.73.1 Beta is available", "Dev · 8e2c9b0"), the installed version under it and when it was
/// last checked, and the buttons on the right: Check for Updates (a spinner while it runs) and, when something is
/// available, the install button of the channel in use.
struct UpdateStatusCard: View {
    let updates: UpdateState
    let installTitle: String

    private var checking: Bool { updates.phase == .checking }

    var body: some View {
        HStack(spacing: Tokens.Space.xl) {
            // fixed: the app's icon is the one thing here that has a size of its own
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: Tokens.Icon.hero + 20, height: Tokens.Icon.hero + 20)
                .accessibilityHidden(true)
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
            VStack(alignment: .trailing, spacing: Tokens.Space.m) {
                if updates.isAvailable {
                    Button(installTitle) { updates.requestInstall() }
                        .buttonStyle(.glassProminent)
                }
                HStack(spacing: Tokens.Space.m) {
                    if checking { ProgressView().controlSize(.small) }
                    Button(Names.Update.checkForUpdates) { Task { await updates.check(force: true) } }
                        .disabled(checking)
                }
            }
        }
        .padding(.vertical, Tokens.Space.s)
    }

    /// "just now", "2 minutes ago".
    static func ago(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 45 { return "just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}
