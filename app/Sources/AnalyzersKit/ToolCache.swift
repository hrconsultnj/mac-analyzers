import Foundation

/// The expansion-pack cache ids — must match storage-auto-clean.sh's
/// tool_cache registrations.
public enum ToolCache: String, CaseIterable, Identifiable {
    case brew, pip, uv, cargo, gradle, deriveddata
    case appcaches, gomod, bun, cipd, simulators, avd, aerials
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .brew: "Homebrew downloads"
        case .pip: "pip cache"
        case .uv: "uv cache"
        case .cargo: "Cargo registry cache"
        case .gradle: "Gradle caches"
        case .deriveddata: "Xcode DerivedData"
        case .appcaches: "App caches (~/Library/Caches)"
        case .gomod: "Go module cache"
        case .bun: "Bun install cache"
        case .cipd: "CIPD cache"
        case .simulators: "Unused simulators"
        case .avd: "Android emulator snapshots"
        case .aerials: "Downloaded aerial wallpapers"
        }
    }

    public var detail: String {
        switch self {
        case .brew: "brew cleanup --prune=all -s — old versions, bottles and downloads."
        case .pip: "pip3 cache purge — wheel downloads."
        case .uv: "uv cache prune — unreferenced entries only."
        case .cargo: "Removes ~/.cargo/registry cache and sources — re-fetched on demand."
        case .gradle: "Removes ~/.gradle/caches — next build re-downloads."
        case .deriveddata: "Empties DerivedData — Xcode rebuilds indexes."
        case .appcaches: "Every app's cache folder except macOS system caches, your protect list, and anything written in the last hour. Apps rebuild them."
        case .gomod: "go clean -modcache — modules re-download on the next build."
        case .bun: "Removes ~/.bun/install/cache — re-downloaded on install."
        case .cipd: "Removes ~/.cipd-cache-dir — toolchain downloads, re-fetched on demand."
        case .simulators: "Simulator runtimes never booted (installed 7+ days ago) and devices whose runtime is gone. Xcode re-downloads on demand."
        case .avd: "Quick-boot snapshots, only while no emulator runs — the next boot is a cold boot."
        case .aerials: "Aerial videos not shown in 14 days — macOS re-downloads the one you use."
        }
    }
}
