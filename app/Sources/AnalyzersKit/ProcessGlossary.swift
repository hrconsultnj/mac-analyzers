import Foundation

/// Translates raw process identities ("next-server (v16.2.6)") into words a
/// non-developer can act on ("Next.js dev server"). Ordered: specific tokens
/// before generic runtimes, so "next-server" never falls through to "node".
public enum ProcessGlossary {

    private static let entries: [(token: String, friendly: String)] = [
        ("next-server", "Next.js dev server"),
        ("next dev", "Next.js dev server"),
        ("vite", "Vite dev server"),
        ("webpack", "Webpack build"),
        ("turbo", "Turborepo task"),
        ("esbuild", "esbuild bundler"),
        ("tsup", "tsup bundler"),
        ("vitest", "Vitest test runner"),
        ("jest", "Jest test runner"),
        ("playwright", "Playwright headless browser"),
        ("ms-playwright", "Playwright headless browser"),
        ("headless_shell", "Headless Chrome (test browser)"),
        ("--headless", "Headless browser"),
        ("mcp", "AI tool server (MCP)"),
        ("nodemon", "Node.js watcher"),
        ("tsx", "TypeScript runner"),
        ("deno", "Deno runtime"),
        ("bun", "Bun runtime"),
        ("npx", "npm package runner"),
        ("npm", "npm task"),
        ("node", "Node.js process"),
    ]

    /// Human description for a raw ps-args identity, or nil if unknown.
    public static func friendlyName(for raw: String) -> String? {
        let lowered = raw.lowercased()
        return entries.first { lowered.contains($0.token) }?.friendly
    }

    // MARK: - what macOS's own processes are for

    /// One plain line per well-known system process. Only names whose job is
    /// certain are listed — an unknown daemon shows no description rather
    /// than a guessed one.
    private static let system: [String: String] = [
        "windowserver": "Draws every window and screen — grows with displays, windows and transparency",
        "launchd": "Starts and supervises every other process",
        "loginwindow": "Your login session",
        "finder": "Desktop, Finder windows and file operations",
        "dock": "The Dock, Mission Control and Launchpad",
        "controlcenter": "Menu bar and Control Center",
        "notificationcenter": "Notifications and widgets panel",
        "systemuiserver": "Menu bar status items",
        "windowmanager": "Stage Manager and window tiling",
        "spotlight": "Spotlight search window",
        "mds": "Spotlight indexing",
        "mds_stores": "Spotlight indexing — the search index itself",
        "corespotlightd": "Spotlight indexing for app content (mail, messages, notes)",
        "cfprefsd": "Reads and writes app preferences",
        "distnoted": "Passes notifications between processes",
        "trustd": "Verifies certificates and code signatures",
        "syspolicyd": "Gatekeeper — checks apps before they run",
        "tccd": "Privacy permission checks (camera, files, microphone…)",
        "securityd": "Keychain and encryption",
        "secd": "Keychain and iCloud Keychain sync",
        "authd": "Authorization prompts",
        "opendirectoryd": "User accounts and login lookups",
        "logd": "The system log",
        "lsd": "Launch Services — which app opens which file",
        "runningboardd": "Manages app lifecycles and background limits",
        "containermanagerd": "Manages app sandboxes",
        "fseventsd": "Tracks file changes for other apps",
        "iconservicesagent": "App and file icons",
        "usernoted": "Delivers notifications",
        "coreaudiod": "Audio input and output",
        "bluetoothd": "Bluetooth",
        "airportd": "Wi-Fi",
        "mdnsresponder": "Network name lookups (DNS and Bonjour)",
        "apsd": "Push notifications",
        "nsurlsessiond": "Background downloads and uploads",
        "sharingd": "AirDrop, Handoff and shared clipboards",
        "rapportd": "Talks to your nearby Apple devices (Continuity)",
        "cloudd": "iCloud sync",
        "bird": "iCloud Drive",
        "accountsd": "Internet accounts (mail, calendars, contacts)",
        "backupd": "Time Machine backups",
        "softwareupdated": "Checks for and downloads macOS updates",
        "photolibraryd": "Photos library",
        "photoanalysisd": "Photos — analyses faces and scenes",
        "mediaanalysisd": "Analyses photos and videos (Visual Look Up, Live Text)",
        "applespell": "Spell checking",
        "chronod": "Widgets",
        "siri ai": "Siri",
        "assistantd": "Siri",
        "assistant_service": "Siri",
        "duetexpertd": "Siri Suggestions",
        "suggestd": "Siri Suggestions in Mail, Messages and Contacts",
        "modelmanagerd": "Loads on-device AI models (Apple Intelligence)",
        "tgondeviceinferenceproviderservice": "An on-device AI model held in memory (Apple Intelligence)",
        "callservicesd": "Phone and FaceTime calls",
        "avconferenced": "FaceTime audio and video",
        "imagent": "Messages and FaceTime sign-in",
        "mediaremoted": "Now Playing controls",
        "universalaccessd": "Accessibility features",
        "mtlcompilerservice": "Compiles graphics shaders for an app",
        "vtdecoderxpcservice": "Video decoding for an app",
        "vtencoderxpcservice": "Video encoding for an app",
        "quicklookuiservice": "Quick Look previews",
        "com.apple.appkit.xpc.openandsavepanelservice": "An app's Open / Save dialog",
        "com.apple.webkit.webcontent": "A web page or web view — Safari tabs and apps with built-in browsers",
        "com.apple.webkit.networking": "Network requests for web views",
        "com.apple.webkit.gpu": "Graphics for web views",
    ]

    /// What a macOS process is for, or nil if it isn't one we can name.
    public static func systemRole(of name: String) -> String? {
        let lowered = name.lowercased()
        if let known = system[lowered] { return known }
        if lowered.hasPrefix("mdworker") { return "Spotlight indexing — reads file contents" }
        if lowered.hasPrefix("com.apple.webkit.webcontent") { return system["com.apple.webkit.webcontent"] }
        return nil
    }
}
