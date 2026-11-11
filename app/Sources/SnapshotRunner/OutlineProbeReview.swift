@_spi(TestSupport) import AnalyzersKit
import AppKit
import Foundation
import SettingsFeature
import SwiftUI
import UIComponents

/// `review:<case>`: the REAL `ReviewTable` and `ReviewSession` on the probe's fixture rows, driven the way
/// a person drives them (a click on a box, Space on a selection, the bar's Select All, a screen's
/// `updateChoosable`) through public AppKit API, asserting after every step what the session would send
/// (`approved`) and what the boxes show. Zero reentrancy warnings is the driver's to count.
@MainActor
final class ReviewRig {
    let probe: ReviewFixtureProbe
    let harness: ProbeHarness
    let outline: NSOutlineView
    private(set) var failed = false

    static let web = ["/p/web-app/node_modules", "/p/web-app/.next", "/p/web-app/dist"]
    static let mobile = ["/p/mobile-app/DerivedData", "/p/mobile-app/Pods"]
    static let engine = ["/p/engine/.build", "/p/engine/target"]
    static let fold = "/p/engine/tmp"
    static let kept = ["/p/active/node_modules", "/p/active/.turbo"]
    static let opera = "app:Opera"
    static let operaWord = "Will Be Asked to Quit"

    init(acting: Bool = false, readOnly: Bool = false) {
        // what an earlier probe process left open or sized is not this one's start (OutlineProbe.run
        // also removes what a process saved when it ends)
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains("review.fixture") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        probe = ReviewFixtureProbe(acting: acting, readOnly: readOnly)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "ma-review-probe-\(getpid())", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let jobs = JobStore(ledger: JobLedger(url: scratch.appending(path: "jobs.jsonl")))
        harness = ProbeHarness(probe.view.environment(jobs), size: NSSize(width: 760, height: 640))
        outline = harness.outline
        _ = settle(); spin(0.3)
    }

    func verdict(_ ok: Bool, _ line: String) {
        say((ok ? "PASS " : "FAIL ") + line)
        if !ok { failed = true }
    }

    func settleAll() { _ = settle(); spin(0.3) }

    /// The tooltip of a row's first cell: the path of a row, the reason of a kept one.
    func tip(_ row: Int) -> String? {
        outline.view(atColumn: 0, row: row, makeIfNecessary: true)?.toolTip
    }

    func row(tip wanted: String) -> Int? {
        (0..<outline.numberOfRows).first { tip($0) == wanted }
    }

    /// The group row a row sits under: the nearest row above it one level out.
    func groupRow(above row: Int) -> Int? {
        let level = outline.level(forRow: row)
        guard level > 0 else { return nil }
        return stride(from: row - 1, through: 0, by: -1).first { outline.level(forRow: $0) == level - 1 }
    }

    func box(_ row: Int) -> NSButton? { ProbeChecks.tickButton(outline, row: row) }

    func boxWord(_ row: Int) -> String {
        guard let box = box(row) else { return "none" }
        let state = box.state == .on ? "on" : box.state == .mixed ? "mixed" : "off"
        return box.isEnabled ? state : state + "(disabled)"
    }

    func click(_ row: Int) {
        box(row)?.performClick(nil)
        settleAll()
    }

    func space(rows: [Int]) {
        outline.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
        harness.window.makeFirstResponder(outline)
        settleAll()
        if let event = ProbeChecks.key(49, " ", window: harness.window) { outline.keyDown(with: event) }
        settleAll()
    }

    func approved() -> Set<String> { Set(probe.report().approved) }

    func line(_ label: String) -> String {
        {
        let report = probe.report()
        return "\(label): approved=\(report.approved.count) narrowed=\(report.isNarrowed) summary=\"\(report.summary)\" confirm=\"\(report.confirmationTitle)\""
    }()
    }

    var exitCode: Int32 { failed ? 1 : 0 }
}

@MainActor
enum ProbeReview {
    static func run(_ name: String) -> Int32 {
        switch name {
        case "ticks": return ticks()
        case "updateChoosable": return updateChoosable()
        case "acting": return acting()
        case "only": return only()
        case "readonly": return readOnly()
        case "scale": return scale(ProbeOptions([]))
        default:
            FileHandle.standardError.write(Data("unknown review case \(name)\n".utf8))
            return 2
        }
    }

    /// A box, a group's box, Space, Select All and None, a kept row, the fold.
    static func ticks() -> Int32 {
        let rig = ReviewRig()
        let chosen = Set(ReviewRig.web + ReviewRig.mobile + ReviewRig.engine)
        mark("begin review:ticks")
        rig.verdict(rig.approved() == chosen && rig.probe.report().isNarrowed,
                    rig.line("initial (everything choosable ticked, the fold and the kept rows not)"))

        guard let next = rig.row(tip: "/p/web-app/.next"), let group = rig.groupRow(above: next) else {
            rig.verdict(false, "rows not found"); return 1
        }
        // a tick on one row: the row off, its group mixed
        rig.click(next)
        rig.verdict(rig.approved() == chosen.subtracting(["/p/web-app/.next"]) && rig.boxWord(next) == "off" && rig.boxWord(group) == "mixed",
                    rig.line("tick .next off; box \(rig.boxWord(next)), group box \(rig.boxWord(group))"))
        // a group's box from mixed: everything choosable in it on, then off
        rig.click(group)
        rig.verdict(rig.approved() == chosen && rig.boxWord(group) == "on", rig.line("group tick from mixed: all on, group box \(rig.boxWord(group))"))
        rig.click(group)
        rig.verdict(rig.approved() == chosen.subtracting(ReviewRig.web) && rig.boxWord(group) == "off",
                    rig.line("group tick from on: all off, group box \(rig.boxWord(group))"))
        rig.click(group)

        // a row the cleanup leaves alone: a disabled box that does nothing
        if let kept = rig.row(tip: "Kept: open in an editor") {
            let before = rig.approved()
            let word = rig.boxWord(kept)
            rig.click(kept)
            rig.verdict(word == "off(disabled)" && rig.approved() == before && rig.approved().isDisjoint(with: ReviewRig.kept),
                        rig.line("kept row: box \(word); a click changes nothing; no kept key is ever approved"))
        } else { rig.verdict(false, "kept row not found") }

        // Space on a selection holding a kept row and a choosable one: only the choosable one toggles
        if let kept = rig.row(tip: "Kept: open in an editor"), let pods = rig.row(tip: "/p/mobile-app/Pods") {
            rig.space(rows: [kept, pods])
            rig.verdict(!rig.approved().contains("/p/mobile-app/Pods") && rig.approved().isDisjoint(with: ReviewRig.kept),
                        rig.line("Space on [kept, Pods]: Pods off, the kept row untouched"))
            rig.space(rows: [pods])
            rig.verdict(rig.approved().contains("/p/mobile-app/Pods"), rig.line("Space on [Pods]: Pods on again"))
        } else { rig.verdict(false, "space rows not found") }

        // the bar's Select None and Select All: the fold's empty rows are never ticked by Select All
        rig.probe.barSelectNone(); rig.settleAll()
        rig.verdict(rig.approved().isEmpty, rig.line("Select None: nothing approved"))
        rig.probe.barSelectAll(); rig.settleAll()
        rig.verdict(rig.approved() == chosen, rig.line("Select All: every choosable row except the folded empty one"))
        if let first = rig.row(tip: "/p/web-app/node_modules") {
            rig.verdict(rig.boxWord(first) == "on", "Select All is drawn: node_modules box \(rig.boxWord(first))")
        }

        // the fold: last row, closed, its row starts unticked and stays so after Select All
        let foldRow = rig.outline.numberOfRows - 1
        let foldItem = rig.outline.item(atRow: foldRow)
        rig.verdict(rig.outline.isExpandable(foldItem) && !rig.outline.isItemExpanded(foldItem),
                    "the fold is the last row and closed (row \(foldRow))")
        rig.outline.expandItem(foldItem); rig.settleAll()
        if let tmp = rig.row(tip: ReviewRig.fold) {
            rig.verdict(rig.boxWord(tmp) == "off" && !rig.approved().contains(ReviewRig.fold), rig.line("the fold's row starts unticked: box \(rig.boxWord(tmp))"))
            rig.click(tmp)
            rig.verdict(rig.approved().contains(ReviewRig.fold), rig.line("a person can tick it: it joins the approved list"))
        } else { rig.verdict(false, "fold member not found") }
        mark("end review:ticks")
        say("report: ticked=\(rig.probe.report().ticked.count) choosable=\(rig.probe.report().choosable) kept=\(rig.probe.report().kept.count)")
        return rig.exitCode
    }

    /// A screen changes what can be chosen in place: ticks stay, a row that stops being choosable can
    /// never be approved, a row that becomes choosable arrives unticked.
    static func updateChoosable() -> Int32 {
        let rig = ReviewRig()
        let chosen = Set(ReviewRig.web + ReviewRig.mobile + ReviewRig.engine)
        guard let target = rig.row(tip: "/p/web-app/.next") else { rig.verdict(false, "row not found"); return 1 }
        mark("begin review:updateChoosable")
        rig.probe.ended("/p/web-app/.next")
        rig.settleAll()
        rig.verdict(rig.approved() == chosen.subtracting(["/p/web-app/.next"]) && rig.tip(target) == "In use" && rig.boxWord(target) == "off(disabled)",
                    rig.line("a row stops being choosable: unticked, disabled, reason shown (\(rig.tip(target) ?? "nil"))"))
        rig.probe.ended("/p/web-app/.next")        // again: nothing changes
        rig.settleAll()
        rig.verdict(rig.approved() == chosen.subtracting(["/p/web-app/.next"]), rig.line("the same update twice changes nothing"))
        rig.probe.choosableAgain("/p/web-app/.next")
        rig.settleAll()
        rig.verdict(rig.boxWord(target) == "off" && !rig.approved().contains("/p/web-app/.next"),
                    rig.line("it becomes choosable again: starts UNTICKED, box \(rig.boxWord(target))"))
        rig.click(target)
        rig.verdict(rig.approved().contains("/p/web-app/.next"), rig.line("the person ticks it: approved"))
        mark("end review:updateChoosable")
        return rig.exitCode
    }

    /// An app the apply quits without a tick: a dimmed box that is on, never approved, never "kept".
    static func acting() -> Int32 {
        let rig = ReviewRig(acting: true)
        mark("begin review:acting")
        guard let opera = rig.row(tip: ReviewRig.operaWord) else { rig.verdict(false, "acting row not found"); return 1 }
        rig.verdict(rig.boxWord(opera) == "on(disabled)", "acting row: box \(rig.boxWord(opera))")
        // told apart from a kept row without the box alone: the words under the name, and what VoiceOver reads
        if let kept = rig.row(tip: "Kept: open in an editor") {
            let keptHelp = rig.box(kept)?.accessibilityHelp() ?? "nil", actingHelp = rig.box(opera)?.accessibilityHelp() ?? "nil"
            rig.verdict(rig.boxWord(kept) == "off(disabled)" && rig.boxWord(opera) == "on(disabled)"
                            && keptHelp == "Kept: open in an editor" && actingHelp == ReviewRig.operaWord,
                        "acting vs kept: kept \(rig.boxWord(kept)) reads \"\(keptHelp)\" | acting \(rig.boxWord(opera)) reads \"\(actingHelp)\"")
        }
        rig.click(opera)
        rig.verdict(!rig.approved().contains(ReviewRig.opera) && rig.probe.report().acting == [ReviewRig.opera],
                    rig.line("a click on it changes nothing; it is never approved"))
        rig.probe.barSelectAll(); rig.settleAll()
        rig.verdict(!rig.approved().contains(ReviewRig.opera), rig.line("Select All leaves it out"))
        rig.probe.barSelectNone(); rig.settleAll()
        rig.verdict(!rig.probe.report().kept.contains(ReviewRig.opera) && rig.probe.report().kept.count == ReviewRig.kept.count,
                    rig.line("it is not counted as kept (kept=\(rig.probe.report().kept.count))"))
        rig.space(rows: [opera])
        rig.verdict(!rig.approved().contains(ReviewRig.opera), rig.line("Space on it changes nothing"))
        mark("end review:acting")
        return rig.exitCode
    }

    /// One tab's rows of a review that spans several: the table shows them, the review still covers all.
    static func only() -> Int32 {
        let rig = ReviewRig()
        let chosen = Set(ReviewRig.web + ReviewRig.mobile + ReviewRig.engine)
        mark("begin review:only")
        let full = rig.outline.numberOfRows
        rig.probe.showOnly(group: "web-app")
        rig.settleAll()
        rig.verdict(rig.outline.numberOfRows == 4 && rig.approved() == chosen,
                    rig.line("only the web-app rows: \(rig.outline.numberOfRows) rows shown (of \(full)); the review still covers everything"))
        rig.probe.barSelectNone(); rig.settleAll()
        if let any = rig.row(tip: "/p/web-app/dist"), let group = rig.groupRow(above: any) {
            rig.click(group)
            rig.verdict(rig.approved() == Set(ReviewRig.web), rig.line("a group tick in the tab sets only that tab's rows"))
        } else { rig.verdict(false, "tab rows not found") }
        rig.probe.showAll()
        rig.settleAll()
        rig.verdict(rig.outline.numberOfRows == full && rig.approved() == Set(ReviewRig.web), rig.line("back to every row: \(rig.outline.numberOfRows) rows"))
        mark("end review:only")
        return rig.exitCode
    }

    /// A review that is only read: no boxes anywhere, nothing to tick.
    static func readOnly() -> Int32 {
        let rig = ReviewRig(readOnly: true)
        mark("begin review:readonly")
        let boxes = (0..<rig.outline.numberOfRows).filter { rig.box($0) != nil }
        rig.verdict(boxes.isEmpty && rig.outline.numberOfRows > 0, "read-only: \(rig.outline.numberOfRows) rows, \(boxes.count) boxes")
        let before = rig.probe.report().ticked
        if let first = rig.row(tip: "/p/web-app/node_modules") { rig.space(rows: [first]) }
        rig.verdict(rig.probe.report().ticked == before, "Space changes nothing in a read-only review")
        mark("end review:readonly")
        return rig.exitCode
    }
}
