import SwiftUI
import AnalyzersKit

/// The five cleaners the screen can preview and apply: their names, blurbs,
/// scripts and the logs they write.
extension ActionsSettingsView {

    enum Cleaner: String, Hashable, CaseIterable {
        case memoryClean, reclaim, storageClean, janitor, tempClean

        /// The two storage-shaped cleaners share the review renderer.
        var isStorageShaped: Bool { self == .storageClean || self == .janitor }

        /// Can the user get it back? The janitor and temp clean use the Trash
        /// (temp clean unless permanent is chosen — see `recoverableNow`); the
        /// storage cleaner deletes, and stopping a process is not undoable
        /// (the command can be re-run, which is not the same thing).
        var isRecoverable: Bool { self == .janitor || self == .tempClean }

        var title: String {
            switch self {
            case .memoryClean: Names.Screen.memoryCleanup
            case .reclaim: Names.memoryReclaim
            case .storageClean: Names.Screen.cachesAndBuilds
            case .janitor: Names.Screen.downloads
            case .tempClean: Names.Screen.tempAndAgents
            }
        }

        var blurb: String {
            switch self {
            case .memoryClean:
                "Closes helper processes whose parent session already died, and dev servers idle more than 24 hours. Protected apps are never touched."
            case .reclaim:
                "Sweeps every reclaimable dev process at once — no age threshold, a wider net than the guard uses. Live AI sessions are exempt; protected apps are never touched."
            case .storageClean:
                "Removes stale build caches and trims oversized Turborepo caches; in deep mode also downloaded code for projects you haven't touched lately (node_modules), idle git worktrees (never main — uncommitted work is parked first), package-manager caches (npm's entire cache), the app and tool caches you enabled in Settings › Storage, and releases Time Machine snapshot space so the freed space shows up. Anything touched recently or in use is skipped."
            case .janitor:
                "Moves stale Downloads and old screenshots to the Trash — recoverable, keep-patterns honored, folders reviewed as units."
            case .tempClean:
                "Clears idle leftovers in /tmp, your temp folder and /var/tmp, plus AI-agent scratch (Claude Code, Codex, the Claude app, npx-run tools). Never anything open, recent, live, or someone else's; agent history and settings are never touched. A file behind a mounted disk image ejects it first."
            }
        }

        var symbol: String {
            switch self {
            case .memoryClean: "memorychip"
            case .reclaim: "arrow.3.trianglepath"
            case .storageClean: "internaldrive.fill"
            case .janitor: "trash"
            case .tempClean: "tray.full"
            }
        }

        var color: Color {
            switch self {
            case .memoryClean: .blue
            case .reclaim: .teal
            case .storageClean: .indigo
            case .janitor: .orange
            case .tempClean: .mint
            }
        }

        var script: URL {
            switch self {
            case .memoryClean: AnalyzersPaths.memoryCleanScript
            case .reclaim: AnalyzersPaths.reclaimScript
            case .storageClean: AnalyzersPaths.storageCleanScript
            case .janitor: AnalyzersPaths.janitorScript
            case .tempClean: AnalyzersPaths.tempCleanScript
            }
        }

        var logKind: LogKind {
            switch self {
            case .memoryClean: .memoryClean
            case .reclaim: .reclaim
            case .storageClean: .storageClean
            case .janitor: .janitor
            case .tempClean: .tempSpace
            }
        }
    }
}
