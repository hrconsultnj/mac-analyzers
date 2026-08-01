// swift-tools-version: 6.2
// MacAnalyzers.app — menu-bar UI + notifier for the mac-analyzers suite.
// Decomposed catalog-style: features import kits, the app target stays thin.
// Built WITHOUT Xcode: `./build.sh` (swift build + hand-assembled bundle).
import Foundation
import PackageDescription

// Optional local overlay: when MA_PRO_PATH is set (see build.sh --pro), the
// package at that path joins the graph and SettingsFeature gains its module.
// Unset (the default, and the only mode CI/public builds use), the graph is
// exactly the public one below.
let proPath = ProcessInfo.processInfo.environment["MA_PRO_PATH"]
let proPackageDependencies: [Package.Dependency] =
    proPath.map { [.package(path: $0)] } ?? []
let proTargetDependencies: [Target.Dependency] =
    proPath != nil ? [.product(name: "ProKit", package: "mac-analyzers-pro")] : []

let package = Package(
    name: "MacAnalyzers",
    platforms: [.macOS(.v26)],
    dependencies: proPackageDependencies,
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
        .executableTarget(name: "AgentRunner", dependencies: ["AnalyzersKit"]),
        // features ("pages/components")
        .target(name: "MenuBarFeature", dependencies: ["AnalyzersKit", "UIComponents"]),
        .target(name: "SettingsFeature", dependencies: ["AnalyzersKit", "NotifierKit", "UIComponents"] + proTargetDependencies),
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
