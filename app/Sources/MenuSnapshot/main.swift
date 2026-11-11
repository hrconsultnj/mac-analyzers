// menu-snapshot — render the menu-bar panel's content to a PNG without ever
// putting a window in front of anyone.
//
//   menu-snapshot <memory|monitor|storage> <out.png> [--wait 4] [--width 420]
//
// A MenuBarExtra cannot be hosted outside the app, so this hosts the panel's
// view (`MenuContentView`) in a plain window with no visible title bar as wide as the panel
// and as tall as its content, far outside every display, with the real stores,
// and captures it. It never activates and never appears in the Dock. It starts
// no job and writes no real log: the job store keeps its index in a temporary
// folder and nothing here enqueues anything.
import AppKit
import SwiftUI
import AnalyzersKit
import MenuBarFeature

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: menu-snapshot <memory|monitor|storage> <out.png> [--wait seconds] [--width points]\n".utf8))
    exit(2)
}
let tab = arguments[0]
let output = URL(fileURLWithPath: arguments[1])
func option(_ name: String) -> Double? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return Double(arguments[index + 1])
}
let wait = option("--wait") ?? 4
let width = option("--width") ?? 420

@MainActor
final class Host: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let store = GuardLogStore()
    let scratch = FileManager.default.temporaryDirectory
        .appending(path: "ma-menu-snapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
    lazy var jobs = JobStore(ledger: JobLedger(url: scratch.appending(path: "app-jobs.jsonl")))
    let updates = UpdateState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let root = MenuContentView(tab: tab.capitalized)
            .environment(store)
            .environment(jobs)
            .environment(updates)
            .frame(width: width)
            .background(.regularMaterial)
        let hosting = NSHostingView(rootView: root)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
                          styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFrontRegardless()   // shows the window WITHOUT activating the app
        Task { await updates.check() }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { self.capture(hosting) }
    }

    private func capture(_ hosting: NSHostingView<some View>) {
        let height = hosting.fittingSize.height
        window.setContentSize(NSSize(width: width, height: height))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(self.window.windowNumber), output.path]
            try? capture.run()
            capture.waitUntilExit()
            print("\(tab) → \(output.path)  (\(Int(self.window.frame.width)) × \(Int(height)) pt)")
            try? FileManager.default.removeItem(at: self.scratch)
            exit(0)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let host = Host()
app.delegate = host
app.run()
