// snapshot-runner — render a real screen of the app to a PNG without ever
// putting a window in front of anyone.
//
//   snapshot-runner <target> <out.png> [--size 1100x720] [--wait 3]
//   snapshot-runner overview /tmp/overview.png
//
// <target> is any deep-link target the app understands (`monitor`, `caches`,
// `log:forensics`, …). The real main window is built with the real data
// stores, placed far outside every display, navigated to the target, given
// time to load, and captured — toolbar, sidebar and all.
//
// Why it exists: a screen can compile, pass every check and still be a list
// of file names nobody would use. The people and agents building screens
// need to LOOK at them, and looking must not mean taking over the owner's
// Mac. This process never activates, never appears in the Dock, and its
// window is never on a display.
import AppKit
import SwiftUI
import AnalyzersKit
import SettingsFeature

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: snapshot-runner <target> <out.png> [--size WxH] [--wait seconds]\n".utf8))
    exit(2)
}
let target = arguments[0]
let output = URL(fileURLWithPath: arguments[1])

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}
let sizeParts = (option("--size") ?? "1100x720").split(separator: "x").compactMap { Double($0) }
let size = NSSize(width: sizeParts.first ?? 1100, height: sizeParts.count > 1 ? sizeParts[1] : 720)
let wait = Double(option("--wait") ?? "3") ?? 3

@MainActor
final class Snapshot: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let store = GuardLogStore()
    let config = ConfigStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = MainWindowView()
            .environment(store)
            .environment(config)
        let controller = NSHostingController(rootView: root)
        controller.sceneBridgingOptions = [.toolbars, .title]   // SwiftUI toolbars become the window's

        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.contentViewController = controller
        window.toolbarStyle = .unified
        window.setContentSize(size)
        // far outside every display: drawn by the window server, seen by nobody
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFrontRegardless()      // shows the window WITHOUT activating the app

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NotificationCenter.default.post(name: NotifyChannel.openPaneInternal, object: nil,
                                            userInfo: ["target": target])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + wait) { self.capture() }
    }

    private func capture() {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.path]
        do {
            try capture.run()
            capture.waitUntilExit()
        } catch {
            FileHandle.standardError.write(Data("snapshot-runner: could not run screencapture: \(error)\n".utf8))
            exit(1)
        }
        let made = FileManager.default.fileExists(atPath: output.path)
        print(made ? "\(target) → \(output.path)  (window title: \(window.title))"
                   : "snapshot-runner: nothing was captured for \(target)")
        exit(made ? 0 : 1)
    }
}

let app = NSApplication.shared
let delegate = Snapshot()
app.delegate = delegate
app.setActivationPolicy(.accessory)        // no Dock icon, never frontmost
app.run()
