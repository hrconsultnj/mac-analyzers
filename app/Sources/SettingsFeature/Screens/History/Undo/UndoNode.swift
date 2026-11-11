import SwiftUI
import AnalyzersKit
import UIComponents

/// One row of the Undo table: a day (drawn as a section header), a run (a group
/// with its count and total), or one item. Built from the history as data; nothing
/// is recovered by splitting a title.
struct UndoNode: Identifiable {
    enum Kind {
        case day(UndoDay)
        case run(UndoRun)
        case item(UndoRun.Child)
    }

    let id: String
    let kind: Kind
    let children: [UndoNode]?

    /// Days newest first, a day's runs with something to restore first, a run's items biggest first.
    static func tree(_ entries: [UndoEntry]) -> [UndoNode] {
        UndoHistory.days(entries).map { day in
            UndoNode(id: day.id, kind: .day(day), children: day.runs.map { run in
                // a run that crosses midnight is two groups: the id says which day's
                let runID = "run:\(day.id)|\(run.id)"
                return UndoNode(id: runID, kind: .run(run), children: run.children.map {
                    UndoNode(id: "item:\(runID)|\($0.id)", kind: .item($0), children: nil)
                })
            })
        }
    }

    /// The header a day is drawn as; nil for every other row.
    var header: OutlineSectionHeader? {
        guard case .day(let day) = kind else { return nil }
        return OutlineSectionHeader(title: day.title(now: Date()), summary: day.summary)
    }

    /// How many text lines the name cell needs: the title, what it is, and the note a run says once.
    var lineCount: Int {
        switch kind {
        case .day: return 1
        case .run(let run): return 2 + (run.restoreNote == nil ? 0 : 1)
        case .item(let child): return child.outcome.isEmpty ? 1 : 2
        }
    }

    /// Every node below this one and itself, to find a row by id.
    var flattened: [UndoNode] { [self] + (children ?? []).flatMap(\.flattened) }
}
