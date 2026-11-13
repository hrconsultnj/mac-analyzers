import SwiftUI
import AnalyzersKit

/// A finished run's kept lines in the shared lines box, for looking at it headless
/// (`SnapshotRunner job:fixture:finished`; the link exists only after
/// `DeepLinkRouter.installFixtures()`). It draws `RunLinesView` the way `RawOutputScreen` does, from
/// example lines instead of a log, so what the box looks like is judged without a real run.
struct RawOutputFixtureScreen: View {
    var body: some View {
        DataScreen(title: "Memory Cleanup", subtitle: "Preview · Finished") {
            VStack(spacing: 0) {
                RunLinesView(lines: Self.lines, anchorBottom: false)
            }
        }
    }

    static let lines: [String] = {
        var lines = ["memory auto-clean  |  DRY RUN  |  2026-11-13 15:09:51", "### Looking for helper processes whose app has closed"]
        lines += (1...60).map { "checked process \($0) of 60" }
        lines += ["### Helper processes whose app has closed",
                  "[DRY]   310 MB  pid=4242  orphan — next-server (no session or terminal in its project)",
                  "[DRY]   120 MB  pid=4243  orphan — chrome-headless-shell (parent gone)",
                  "[DRY]    64 MB  pid=4244  orphan — node (no parent)"]
        return lines
    }()
}
