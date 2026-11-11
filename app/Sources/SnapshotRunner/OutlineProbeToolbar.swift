@_spi(TestSupport) import AnalyzersKit
import AppKit
import Foundation
import SettingsFeature
import SwiftUI
import UIComponents

/// `toolbar:<bare|line|inset>`: the table as the screens embed it, under the main window's unified toolbar
/// (a split view, a toolbar item, a full-size content view). `bare` has the table as the first thing
/// under the toolbar; `line` has a line of text above it. After the window has settled the first row's
/// frame must lie below the header's, and the table must not be scrolled away from its first row.
/// `toolbar:render <bare|line|inset> <out.png>` draws the same window.
@MainActor
enum ProbeToolbar {
    private struct Screen: View {
        let model: ProbeModel
        let line: Bool
        /// The embedding the System screens used: safe-area insets around the table, the top one empty.
        var insets = false
        /// Rows with a `headerTitle` draw as day section headers (Trends).
        var headers = false
        /// The shared scope tabs' place: a bar under the toolbar the table sits below (`safeAreaBar`).
        var bar = false
        var body: some View {
            NavigationSplitView {
                List { Text("Overview"); Text("Login & Startup Items") }
            } detail: {
                VStack(spacing: 0) {
                    if line { Text("Audited 8 hours ago: 29 items").padding() }
                    if bar {
                        ProbeScreen(model: model, hosted: false, headers: headers)
                            .safeAreaBar(edge: .top, spacing: 0) {
                                Picker("Tabs", selection: .constant(1)) { Text("Apps").tag(1); Text("Tools").tag(2) }
                                    .pickerStyle(.segmented).labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading).scenePadding(.horizontal).padding(.vertical, 8)
                            }
                    } else if insets {
                        ProbeScreen(model: model, hosted: false, headers: headers)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                Text("Audited 8 hours ago: 29 items, 11 of them leftovers.").font(.caption).padding()
                            }
                            .safeAreaInset(edge: .top, spacing: 0) {
                                if model.rows.isEmpty { Text("note") }
                            }
                    } else {
                        ProbeScreen(model: model, hosted: false, headers: headers)
                    }
                }
                .navigationTitle("Login & Startup Items")
                .toolbar { ToolbarItem { Button("Audit") {} } }
            }
        }
    }

    private static func window(line: Bool, insets: Bool = false, headers: Bool = false, bar: Bool = false, size: NSSize = NSSize(width: 1100, height: 720)) -> (ProbeWindow, ProbeModel) {
        let model: ProbeModel
        if headers {
            var next = 0
            func id() -> Int { next += 1; return next }
            let days = (1...5).map { day in
                ProbeRow(id: id(), name: "Day \(day)", cpu: 0, mem: 0, kind: "", children: (1...6).map { _ in
                    let rowID = id()
                    return ProbeRow(id: rowID, name: "event \(rowID)", cpu: 0, mem: rowID * 7, kind: "")
                }, headerTitle: ["Today", "Yesterday", "Monday", "Sunday", "Saturday"][day - 1])
            }
            model = ProbeModel(rows: days)
            model.expanded = Set(days.map(\.id))
        } else {
            model = ProbeModel(rows: makeProbeRows(parents: 3, kids: 2))
        }
        let host = NSHostingController(rootView: Screen(model: model, line: line, insets: insets, headers: headers, bar: bar))
        let window = ProbeWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFrontRegardless()
        _ = settle(); spin(0.8)
        return (window, model)
    }

    /// The real review table (the fixture) under the same split view and toolbar.
    private static func reviewWindow(size: NSSize = NSSize(width: 1100, height: 720)) -> (ProbeWindow, ReviewFixtureProbe) {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "ma-toolbar-probe-\(getpid())", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let jobs = JobStore(ledger: JobLedger(url: scratch.appending(path: "jobs.jsonl")))
        let probe = ReviewFixtureProbe()
        let content = NavigationSplitView {
            List { Text("Overview") }
        } detail: {
            probe.view.environment(jobs)
                .navigationTitle("Review").toolbar { ToolbarItem { Button("Audit") {} } }
        }
        let window = ProbeWindow(contentViewController: NSHostingController(rootView: content))
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFrontRegardless()
        _ = settle(); spin(0.5)
        return (window, probe)
    }

    /// First appearance, many times over: the first row is below the header every time, for the plain table
    /// under the toolbar and for the real review table (the screens' timing is not deterministic, one pass
    /// proves nothing).
    private static func firstAppearance(_ arguments: [String]) -> Int32 {
        let runs = arguments.first.flatMap(Int.init) ?? 10
        var failures = 0
        for run in 1...runs {
            for kind in ["bare", "bar", "review"] {
                let window: ProbeWindow
                if kind == "bare" { window = Self.window(line: false).0 } else if kind == "bar" { window = Self.window(line: false, bar: true).0 } else { window = reviewWindow().0 }
                guard let outline = window.contentView.flatMap(findOutline(in:)), let header = outline.headerView else {
                    say("FAIL first appearance \(kind) #\(run): no table"); failures += 1; continue
                }
                let row = outline.convert(outline.rect(ofRow: 0), to: nil), head = header.convert(header.bounds, to: nil)
                let good = row.maxY <= head.minY + 0.5
                if !good { failures += 1 }
                say("\(good ? "PASS" : "FAIL") first appearance \(kind) #\(run): first row top \(Int(row.maxY)) header bottom \(Int(head.minY))")
                window.contentViewController = nil; window.close()
            }
        }
        return failures == 0 ? 0 : 1
    }

    static func run(_ name: String, _ arguments: [String]) -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        if name == "first" { return firstAppearance(arguments) }
        if name == "render" {
            guard arguments.count >= 2 else { return 2 }
            let (window, model) = window(line: arguments[0] == "line", insets: arguments[0] == "inset", headers: arguments[0] == "headers", bar: arguments[0] == "bar")
            // an update after the first draw, as a screen's refresh is
            if arguments[0] != "headers" { model.rows.append(ProbeRow(id: model.newID(), name: "Parent new", cpu: 1, mem: 5, kind: "App", children: nil)) }
            else { model.rows.append(ProbeRow(id: model.newID(), name: "More", cpu: 0, mem: 0, kind: "", children: [], headerTitle: "Friday")) }
            _ = settle(); spin(0.5)
            guard let view = window.contentView else { return 1 }
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 1 }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]),
                  (try? png.write(to: URL(fileURLWithPath: arguments[1]))) != nil else { return 1 }
            say("render toolbar:\(arguments[0]) -> \(arguments[1])")
            return 0
        }
        let (window, model) = window(line: name == "line", insets: name == "inset", bar: name == "bar")
        guard let outline = window.contentView.flatMap(findOutline(in:)),
              let header = outline.headerView, let scroll = outline.enclosingScrollView else {
            say("FAIL toolbar:\(name): no table or no header")
            return 1
        }
        var ok = true
        func check(_ good: Bool, _ text: String) { say((good ? "PASS " : "FAIL ") + text); if !good { ok = false } }
        func report() -> Bool {
            let row = outline.convert(outline.rect(ofRow: 0), to: nil)
            let head = header.convert(header.bounds, to: nil)
            say("  first row top \(Int(row.maxY)) header bottom \(Int(head.minY)) clip origin \(Int(scroll.contentView.bounds.origin.y)) scroll insets top \(Int(scroll.contentInsets.top)) clip insets top \(Int(scroll.contentView.contentInsets.top))")
            return row.maxY <= head.minY + 0.5
        }
        check(report(), "toolbar:\(name): the first row is below the header")
        // after the window is resized and after a scroll to the top, still so
        window.setContentSize(NSSize(width: 900, height: 600)); _ = settle(); spin(0.4)
        check(report(), "toolbar:\(name): still below the header after a resize")
        outline.scrollRowToVisible(0); spin(0.2)
        check(report(), "toolbar:\(name): still below the header after scrolling to the first row")
        // the screens' own updates: a row arrives, the rows are re-sorted
        model.rows.append(ProbeRow(id: model.newID(), name: "Parent new", cpu: 1, mem: 5, kind: "App", children: nil))
        _ = settle(); spin(0.3)
        check(report(), "toolbar:\(name): still below the header after a row arrived")
        model.sortOrder = [KeyPathComparator(\.mem, order: .reverse)]
        model.rows.sort { $0.mem > $1.mem }
        _ = settle(); spin(0.3)
        check(report(), "toolbar:\(name): still below the header after a re-sort")
        // a tab change: other rows altogether, many of them
        model.rows = makeProbeRows(parents: 60, kids: 2)
        _ = settle(); spin(0.3)
        check(report(), "toolbar:\(name): still below the header after a tab change (other rows)")
        // a person who scrolled keeps their place through an update
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: 240)); scroll.reflectScrolledClipView(clip); spin(0.2)
        let placed = clip.bounds.origin.y
        model.rows.append(ProbeRow(id: model.newID(), name: "Zed", cpu: 1, mem: 5, kind: "App", children: nil))
        _ = settle(); spin(0.3)
        check(abs(clip.bounds.origin.y - placed) < 1, "toolbar:\(name): a table the person scrolled keeps its position (\(Int(placed)) -> \(Int(clip.bounds.origin.y)))")
        // scrolled to the end and back to the top
        outline.scrollRowToVisible(outline.numberOfRows - 1); spin(0.3)
        check(clip.bounds.origin.y > placed, "toolbar:\(name): scrolled to the end (origin \(Int(clip.bounds.origin.y)))")
        clip.scroll(to: NSPoint(x: 0, y: -clip.contentInsets.top)); scroll.reflectScrolledClipView(clip); spin(0.3)
        check(report(), "toolbar:\(name): back at the top, the first row is below the header")
        model.rows.append(ProbeRow(id: model.newID(), name: "Late", cpu: 1, mem: 5, kind: "App", children: nil))
        _ = settle(); spin(0.3)
        check(report(), "toolbar:\(name): and still so after an update")
        return ok ? 0 : 1
    }
}
