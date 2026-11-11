import Foundation

/// What a process inside an app's family is FOR — the difference between
/// "Opera has 30 processes" and "Opera has 8 pages open, 3 extensions and a
/// handful of helpers". Read from how browsers and Electron apps label their
/// own helpers, so it holds for every Chromium- and WebKit-based app without
/// a per-app list.
enum ProcessRole {

    struct Described {
        let kind: CensusPart.Kind
        let title: String
        /// For the one-line summary: "1 tab or page", "8 tabs and pages".
        let one: String
        let many: String
    }

    static let main = Described(kind: .main, title: "The App Itself", one: "main", many: "main")
    static let pages = Described(kind: .pages, title: "Tabs and Pages",
                                 one: "tab or page", many: "tabs and pages")
    static let extensions = Described(kind: .extensions, title: "Extensions and Plug-ins",
                                      one: "extension", many: "extensions")
    static let graphics = Described(kind: .graphics, title: "Graphics",
                                    one: "for graphics", many: "for graphics")
    static let network = Described(kind: .network, title: "Network and Storage",
                                   one: "for network and storage", many: "for network and storage")
    static let helper = Described(kind: .helper, title: "Other Helpers",
                                  one: "other helper", many: "other helpers")

    /// - Parameters:
    ///   - name: the process's own name ("Opera Helper (Renderer)")
    ///   - command: its full command line when readable — Chromium says
    ///     exactly what each helper is there (`--type=renderer`)
    ///   - isMain: it is the app's top-level process
    static func of(name: String, command: String?, isMain: Bool) -> Described {
        if isMain { return main }
        let lowered = name.lowercased()
        let args = command ?? ""

        // Chromium / Electron: the command line is authoritative
        if args.contains("--type=renderer") {
            return args.contains("--extension-process") ? extensions : pages
        }
        if args.contains("--type=gpu-process") { return graphics }
        if args.contains("--type=utility") {
            // Electron runs extension hosts as "utility" helpers named (Plugin)
            if lowered.contains("(plugin)") { return extensions }
            let networked = args.contains("network.mojom") || args.contains("storage.mojom")
            return networked ? network : helper
        }

        // WebKit (Safari, Mail, any app with a built-in web view) and the
        // services macOS runs on an app's behalf
        if lowered.contains("webcontent") { return pages }
        if lowered.contains("webkit.networking") { return network }
        if lowered.contains("webkit.gpu") || lowered.contains("mtlcompiler")
            || lowered.contains("vtdecoder") || lowered.contains("vtencoder") { return graphics }

        // by name, when the command line said nothing
        if lowered.contains("(renderer)") { return pages }
        if lowered.contains("(gpu)") { return graphics }
        if lowered.contains("(plugin)") || lowered.hasSuffix("extension")
            || lowered.contains("extensionhost") { return extensions }
        return helper
    }

    /// Inside a tool group there are no "tabs" — the useful split is by
    /// program: "AI tool server (MCP)", "Node.js process".
    static func named(_ friendlyName: String) -> Described {
        Described(kind: .named, title: friendlyName, one: friendlyName, many: friendlyName)
    }
}
