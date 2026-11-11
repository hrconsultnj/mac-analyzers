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

// This package's own targets refuse warnings (SE-0480). Set here in the
// manifest, not as `-Xswiftc -warnings-as-errors`: a command-line flag also
// reaches the Pro overlay's path dependency, while a manifest setting does not.
//
// Strict is the default for every build: `swift build`, scripts/check.sh, the
// pre-push gate, the release script, the packaged download, GitHub's Mac run.
// The ONE exception is `app/build.sh` installing on a person's own Mac, which
// sets MA_RELAX_WARNINGS=1: people build with whatever Xcode they have, and a
// newer compiler that has learned a new warning must not stop their install
// or update. That build still prints its warnings, and upgrade.command says
// how many, as a defect to report. (A command-line `-no-warnings-as-errors`
// does not override the manifest setting — tried; hence the variable.)
let relaxed = ProcessInfo.processInfo.environment["MA_RELAX_WARNINGS"] == "1"
let strictSwift: [SwiftSetting] = relaxed ? [] : [.treatAllWarnings(as: .error)]
let strictC: [CSetting] = relaxed ? [] : [.treatAllWarnings(as: .error)]

let package = Package(
    name: "MacAnalyzers",
    platforms: [.macOS(.v26)],
    dependencies: proPackageDependencies,
    targets: [
        // app shell (thin @main: scenes + DI)
        .executableTarget(
            name: "MacAnalyzersApp",
            dependencies: ["AnalyzersKit", "NotifierKit", "MenuBarFeature", "SettingsFeature"],
            swiftSettings: strictSwift
        ),
        // CLI shim the bash scripts call (posts to the running app)
        .executableTarget(
            name: "NotifierCLI",
            dependencies: ["AnalyzersKit"],
            swiftSettings: strictSwift
        ),
        // compiled launchd entry point (BTM attribution) — execs the engine
        .executableTarget(name: "AgentRunner", dependencies: ["AnalyzersKit"], swiftSettings: strictSwift),
        // development tool, never bundled: renders a real screen to a PNG in a
        // window that is never on a display (see Sources/SnapshotRunner/main.swift)
        .executableTarget(name: "SnapshotRunner", dependencies: ["AnalyzersKit", "SettingsFeature"],
                          swiftSettings: strictSwift),
        // features ("pages/components")
        .target(name: "MenuBarFeature", dependencies: ["AnalyzersKit", "UIComponents"], swiftSettings: strictSwift),
        .target(name: "SettingsFeature", dependencies: ["AnalyzersKit", "NotifierKit", "UIComponents"] + proTargetDependencies,
                swiftSettings: strictSwift),
        // shared visual language (System-Settings-style tiles, pane headers,
        // process rows) — may use the kernel's models
        .target(name: "UIComponents", dependencies: ["AnalyzersKit"], swiftSettings: strictSwift),
        // notifications (UN center, delegate, distributed bridge)
        .target(name: "NotifierKit", dependencies: ["AnalyzersKit"], swiftSettings: strictSwift),
        // shared kernel ("packages/shared"): models, parser, config bridge, launchd
        .target(name: "AnalyzersKit", dependencies: ["CLibProc"], swiftSettings: strictSwift),
        .target(name: "CLibProc", cSettings: strictC),
    ]
)
