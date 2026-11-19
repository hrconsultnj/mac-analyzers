import Foundation

/// What the Welcome flow shows of THIS Mac: its own numbers on the first step, and what Memory Guard would do now.
public struct WelcomeNumbers: Sendable, Equatable {
    public var memoryTotal: Int64
    public var memoryUsed: Int64
    public var diskTotal: Int64
    public var diskUsed: Int64
    public var diskFree: Int64
    /// Items that start by themselves, from the last Login & Startup Items audit; nil when it has not run.
    public var startupItems: Int?

    @MainActor public static func read() -> WelcomeNumbers {
        let memory = MemoryBreakdown.current()
        let disk = LiveStats.diskUsage()
        return WelcomeNumbers(memoryTotal: memory?.totalBytes ?? Int64(ProcessInfo.processInfo.physicalMemory),
                              memoryUsed: memory?.usedBytes ?? 0, diskTotal: disk?.totalBytes ?? 0,
                              diskUsed: disk?.usedBytes ?? 0, diskFree: disk?.freeBytes ?? 0,
                              startupItems: StartupInventory.latest()?.items.count)
    }

    public static let fixture = WelcomeNumbers(memoryTotal: 32 << 30, memoryUsed: Int64(23.3 * Double(1 << 30)),
                                               diskTotal: 460 << 30, diskUsed: 322 << 30, diskFree: 114 << 30, startupItems: 29)
}

/// The Memory Guard step's example for a render: the plan as the Plan tab shows it (`GuardPlanPreview`). Real windows read the
/// real plan and evaluator; this is only words for a headless picture.
public enum WelcomeGuardFixture {
    public static let plan = GuardPlanPreview.Plan(
        ladder: "When memory runs out, Memory Guard first stops a developer tool over its limit, then asks apps you listed to quit, then closes the largest idle app.",
        steps: [
            GuardPlanPreview.Step(id: "devTooling", summary: "Stop a developer tool that holds more than 6 GB for 5 minutes", state: .acting,
                                  wouldPick: "Would pick now: next-server, 7.2 GB (Dev Servers)."),
            GuardPlanPreview.Step(id: "mayQuit", summary: "Ask an app on your list to quit", state: .watching, wouldPick: "Would pick now: nothing."),
            GuardPlanPreview.Step(id: "idle", summary: "Quit the largest idle app", state: .watching,
                                  wouldPick: "Needs to know what is idle, which arrives when rules start to act."),
            GuardPlanPreview.Step(id: "browser", summary: "Close a browser's heaviest tab process", state: .watching, wouldPick: "Would pick now: Browsers, 4.5 GB.")],
        protected: [
            GuardPlanPreview.Protected(name: "Claude", why: "a live coding session", symbol: "lock.fill"),
            GuardPlanPreview.Protected(name: "Tailscale", why: "Connection Tools", symbol: "lock.fill"),
            GuardPlanPreview.Protected(name: "Sparehold", why: "the app in front", symbol: "macwindow"),
            GuardPlanPreview.Protected(name: "superwhisper", why: "on your Never Close list", symbol: "hand.raised.fill")])
}
