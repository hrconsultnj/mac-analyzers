import AppKit
import Foundation
import SwiftUI
import UIComponents

/// `--outline-probe render <fixture> <out.png> [--size WxH] [--dark]`: one fixture
/// table in a window outside every display, drawn into a bitmap by its own view. For looking at row height, alternating rows, the header,
/// the tick column and a section header row; it takes no focus and shows nothing.
@MainActor
enum ProbeRender {
    static func run(_ arguments: [String]) -> Int32 {
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("usage: --outline-probe render <plain|hosted|ticks|headers> <out.png> [--size WxH] [--dark]\n".utf8))
            return 2
        }
        let fixture = arguments[0]
        let output = URL(fileURLWithPath: arguments[1])
        var size = NSSize(width: 900, height: 600)
        if let index = arguments.firstIndex(of: "--size"), arguments.indices.contains(index + 1) {
            let parts = arguments[index + 1].split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { size = NSSize(width: parts[0], height: parts[1]) }
        }
        let dark = arguments.contains("--dark")
        NSApplication.shared.setActivationPolicy(.accessory)      // a window the server draws, never frontmost

        let content: AnyView
        switch fixture {
        case "plain", "hosted":
            let model = ProbeModel(rows: makeProbeRows(parents: 40, kids: 4))
            model.expanded = Set(model.parentIDs.prefix(6))
            model.selection = [model.rows[1].children?.first?.id ?? 0]
            content = AnyView(ProbeScreen(model: model, hosted: fixture == "hosted"))
        case "ticks":
            let model = TickModel()
            model.expanded = ["g1", "g2"]
            model.ticked = ["a", "d"]
            model.selection = ["b"]
            content = AnyView(TickScreen(model: model))
        case "headers":
            var next = 0
            func id() -> Int { next += 1; return next }
            let days = (1...5).map { day in
                ProbeRow(id: id(), name: "Day \(day)", cpu: 0, mem: 0, kind: "", children: (1...6).map { _ in
                    let rowID = id()
                    return ProbeRow(id: rowID, name: "run \(rowID)", cpu: 0, mem: rowID * 7, kind: "")
                }, headerTitle: ["Today", "Yesterday", "Monday", "Sunday", "Saturday"][day - 1])
            }
            let model = ProbeModel(rows: days)
            model.expanded = Set(days.prefix(3).map(\.id))
            content = AnyView(ProbeScreen(model: model, hosted: false, headers: true))
        default:
            FileHandle.standardError.write(Data("unknown fixture \(fixture)\n".utf8))
            return 2
        }

        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(size)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFrontRegardless()
        _ = settle(); spin(0.8)

        // Drawn by the view itself into a bitmap: needs no display and no screen-recording
        // permission, so it works when the screen is locked too.
        guard let view = window.contentView else { return 1 }
        view.layoutSubtreeIfNeeded()
        var made = false
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                made = (try? png.write(to: output)) != nil
            }
        }
        say(made ? "render \(fixture) \(Int(size.width))x\(Int(size.height)) \(dark ? "dark" : "light") -> \(output.path)" : "render \(fixture): nothing captured")
        return made ? 0 : 1
    }
}
