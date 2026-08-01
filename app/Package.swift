// swift-tools-version: 6.2
// MacAnalyzers.app — menu-bar UI + notifier for the mac-analyzers suite.
// Decomposed catalog-style: features import kits, the app target stays thin.
// Built WITHOUT Xcode: `./build.sh` (swift build + hand-assembled bundle).
import PackageDescription

let package = Package(
    name: "MacAnalyzers",
    platforms: [.macOS(.v26)],
    targets: [
        // app shell (thin @main: scenes + DI)
        .executableTarget(
            name: "MacAnalyzersApp",
            dependencies: ["AnalyzersKit", "NotifierKit", "MenuBarFeature", "SettingsFeature"]
        ),
        // CLI shim the bash scripts call (posts to the running app)
        .executableTarget(
            name: "NotifierCLI",
            dependencies: ["AnalyzersKit"]
        ),
        // compiled launchd entry point (BTM attribution) — execs the engine
        .executableTarget(name: "AgentRunner"),
        // features ("pages/components")
        .target(name: "MenuBarFeature", dependencies: ["AnalyzersKit", "UIComponents"]),
        .target(name: "SettingsFeature", dependencies: ["AnalyzersKit", "NotifierKit", "UIComponents"]),
        // shared visual language (System-Settings-style tiles, pane headers,
        // process rows) — may use the kernel's models
        .target(name: "UIComponents", dependencies: ["AnalyzersKit"]),
        // notifications (UN center, delegate, distributed bridge)
        .target(name: "NotifierKit", dependencies: ["AnalyzersKit"]),
        // shared kernel ("packages/shared"): models, parser, config bridge, launchd
        .target(name: "AnalyzersKit", dependencies: ["CLibProc"]),
        .target(name: "CLibProc"),
    ]
)
