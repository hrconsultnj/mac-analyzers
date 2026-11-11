// notify CLI — bundled at MacAnalyzers.app/Contents/MacOS/notify.
// Called by lib/notify.sh: posts {title, message, sound, log} to the running
// menu-bar app over DistributedNotificationCenter; starts the app first if it
// isn't running. Exits immediately — never blocks a calling script.
import AppKit
import AnalyzersKit

var title = "Mac Analyzers"
var subtitle: String?
var message = ""
var sound: String? = "Glass"
var log: String?
var pid: String?

var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let flag = iterator.next() {
    switch flag {
    case "--title": title = iterator.next() ?? title
    case "--subtitle": subtitle = iterator.next()
    case "--message": message = iterator.next() ?? ""
    case "--sound": sound = iterator.next()
    case "--log": log = iterator.next()
    case "--pid": pid = iterator.next()
    default: break
    }
}

guard !message.isEmpty else {
    FileHandle.standardError.write(Data("usage: notify --title T --message M [--sound S] [--log PATH]\n".utf8))
    exit(2)
}

// app bundle root = ../../.. from this binary (Contents/MacOS/notify)
let bundleURL = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()   // MacOS
    .deletingLastPathComponent()   // Contents
    .deletingLastPathComponent()   // MacAnalyzers.app

let appRunning = NSWorkspace.shared.runningApplications
    .contains { $0.bundleIdentifier == NotifyChannel.appBundleID }

if !appRunning {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-g", bundleURL.path]
    try? open.run()
    open.waitUntilExit()
    Thread.sleep(forTimeInterval: 2.0)   // give the listener a beat to attach
}

var userInfo: [String: String] = ["title": title, "message": message]
if let subtitle { userInfo["subtitle"] = subtitle }
if let sound { userInfo["sound"] = sound }
if let log { userInfo["log"] = log }
if let pid { userInfo["pid"] = pid }

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(NotifyChannel.name),
    object: nil,
    userInfo: userInfo,
    deliverImmediately: true
)

// give the distributed post a moment to flush before the process dies
Thread.sleep(forTimeInterval: 0.2)
