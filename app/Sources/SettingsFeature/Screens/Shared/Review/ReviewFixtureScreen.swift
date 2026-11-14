import SwiftUI
import AnalyzersKit

/// The review table with example rows, for looking at it headless
/// (`SnapshotRunner review:fixture`; the link exists only after
/// `DeepLinkRouter.installFixtures()`, which only SnapshotRunner calls). Nothing here
/// can apply anything: no preview job is behind it, so Apply stays dimmed.
///
/// `long: true` (`review:fixture:long`) is 200 rows across five groups (the most the table opens by default), for looking at rows
/// passing under the Apply bar when the table is scrolled to its end (`--scroll-end`).
struct ReviewFixtureScreen: View {
    @State private var session: ReviewSession

    init(long: Bool = false) {
        _session = State(initialValue: ReviewSession(previewID: UUID(),
                                                     rows: long ? ReviewFixtureScreen.longExamples : ReviewFixtureScreen.examples,
                                                     ticks: ReviewTickStore()))
    }

    var body: some View {
        DataScreen(title: "Review Example", subtitle: session.summary) {
            ReviewTable(session: session, applyTitle: "Move to Trash",
                        confirmation: ReviewConfirmation(verb: "Move", destination: "to the Trash",
                                                         message: "You can put them back from Undo."),
                        screen: "fixture")
        }
    }

    static let longExamples: [ReviewRow] = (1...5).flatMap { project in
        (1...40).map { item in
            let path = "/Users/example/project-\(project)/cache-\(item)"
            return ReviewRow(id: path, name: "cache-\(item)", detail: path, group: "project-\(project)",
                             bytes: Int64(project * 40_000_000 + item * 1_500_000), iconPath: "/Applications", keptReason: nil)
        }
    }

    static let examples: [ReviewRow] = {
        let projects: [(String, [(String, Int64)])] = [
            ("web-app", [("node_modules", 1_840_000_000), (".next", 620_000_000), ("dist", 96_000_000)]),
            ("mobile-app", [("DerivedData", 3_100_000_000), ("Pods", 410_000_000)]),
            ("engine", [(".build", 2_250_000_000), ("target", 780_000_000), (".cache", 48_000_000), ("tmp", 0)]),
            ("active-project", [("node_modules", 900_000_000), (".turbo", 12_000_000)]),
        ]
        return projects.flatMap { project, items in
            items.map { name, bytes in
                ReviewRow(id: "/Users/example/\(project)/\(name)", name: name,
                          detail: "/Users/example/\(project)/\(name)", group: project, bytes: bytes,
                          iconPath: "/Applications",
                          keptReason: project == "active-project" ? "Kept: this project is open in an editor" : nil)
            }
        }
    }()
}
