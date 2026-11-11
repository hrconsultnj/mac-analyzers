import Foundation

/// Turns the labels and paths a startup item is known by into names a person
/// recognises. The audit's findings are never touched here: this is only
/// "com.google.keystone.agent" becoming "Keystone Agent, from Google".
enum StartupNaming {

    /// First segments of a reverse-DNS label that are not the developer.
    private static let topLevel: Set<String> = [
        "com", "org", "net", "io", "dev", "us", "app", "co", "me", "ai", "de", "uk", "eu",
    ]

    /// Trailing words that say how a helper is wired, not what it is.
    private static let plumbing: Set<String> = ["xpc", "service", "xpcservice", "plist"]

    /// "GoogleUpdater" -> "Google Updater"; "mac-analyzers" -> "Mac Analyzers".
    /// `splitCamel: false` keeps a brand written as one word ("OrbStack").
    static func humanize(_ word: String, splitCamel: Bool = true) -> String {
        // A name already written with capitals ("iTerm", "macOS", "GoogleUpdater") or
        // with characters a label does not normally have is shown exactly as written:
        // forcing capitals mangles real names.
        if word.contains(where: \.isUppercase) || !word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
            return word
        }
        var spaced = ""
        var previous: Character?
        for ch in word {
            if ch == "-" || ch == "_" { spaced.append(" "); previous = ch; continue }
            if splitCamel, let p = previous, p.isLowercase, ch.isUppercase { spaced.append(" ") }
            spaced.append(ch)
            previous = ch
        }
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The developer part of a reverse-DNS label, exactly as the label spells it
    /// (`com.vmware.x` is "vmware"): a guessed capital reads as a typo, the
    /// label's own spelling reads as an identifier.
    static func vendor(ofLabel label: String) -> String {
        let parts = label.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return label }
        if parts.count >= 2, topLevel.contains(parts[0].lowercased()) { return parts[1] }
        return parts[0]
    }

    /// A vendor folder in a known install location
    /// (`/Library/Application Support/Google/…` is "Google"), as written on disk.
    static func vendor(inPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let at = parts.firstIndex(of: "Application Support"), parts.indices.contains(at + 1),
              parts.indices.contains(at - 1), parts[at - 1] == "Library" else { return nil }
        return parts[at + 1]
    }

    /// The item's own name: the label without the developer and without
    /// wiring words ("com.google.keystone.agent" -> "Keystone Agent").
    static func itemName(ofLabel label: String, owner: String) -> String {
        var parts = label.split(separator: ".").map(String.init)
        if parts.count >= 2, topLevel.contains(parts[0].lowercased()) { parts.removeFirst(2) }
        else if parts.count >= 2 { parts.removeFirst() }
        // "dev.orbstack.OrbStack.privhelper": the vendor again is not the name
        while parts.count > 1, parts[0].lowercased() == vendor(ofLabel: label).lowercased() {
            parts.removeFirst()
        }
        while let last = parts.last, plumbing.contains(last.lowercased()), parts.count > 1 {
            parts.removeLast()
        }
        // a label with characters a label should not have is shown whole, as written
        if parts.contains(where: { !$0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }) {
            return parts.joined(separator: ".")
        }
        let words = parts.map { humanize($0) }.joined(separator: " ")
        return words.isEmpty ? owner : words
    }

    /// The outermost `.app` in a path, if any: the app a helper belongs to.
    static func outermostApp(in path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        for (index, part) in parts.enumerated() where part.hasSuffix(".app") {
            return parts[0...index].joined(separator: "/")
        }
        return nil
    }

    /// An app's name as the Finder shows it: its file name without ".app".
    /// (A bundle's own name key is often an internal one: "Code" for Visual
    /// Studio Code, "remoting_me2me_host" for Chrome Remote Desktop.)
    static func appName(at path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// Everything a row needs to be named, and which source named its owner.
    /// Order: the app the program sits in, then the organisation in the
    /// program's code signature (what System Settings shows), then a vendor
    /// folder in a known install location, then the label's vendor part as written.
    static func identify(kind: StartupItem.Kind, label: String, target: String?)
        -> (name: String, owner: String, ownerSource: StartupItem.OwnerSource, ownerNote: String?,
            appPath: String?) {
        let app = target.flatMap(outermostApp(in:))
        let owner: String
        let source: StartupItem.OwnerSource
        var note: String?
        // the signature of the app the program sits in, else of the program itself
        let signature = (app ?? target).map(CodeSignature.check(ofProgram:)) ?? .none
        if case .unverified(let claimed) = signature {
            note = "its code signature names \"\(claimed)\" but does not validate"
        }
        if kind != .loginItem, case .verified(let signer) = signature {
            // one developer is one group: its helpers, daemons and agents all name it the same way
            (owner, source) = (signer, .signature)
        } else if let app {
            (owner, source) = (appName(at: app), .app)
        } else if let target, let folder = vendor(inPath: target) {
            (owner, source) = (folder, .installFolder)
        } else {
            (owner, source) = (kind == .loginItem ? label : vendor(ofLabel: label), .label)
        }
        // System Settings already names a login item by its app
        let name = kind == .loginItem ? label : itemName(ofLabel: label, owner: owner)
        return (name, owner, source, note, app)
    }

    /// One name per owner. A name that another name starts with (four letters
    /// or more, ignoring case and punctuation) is the same owner, under the
    /// shorter one: "Zoom" and "zoom.us", "Muse" and "Muse Networking".
    static func canonicalNames(_ names: some Collection<String>) -> [String: String] {
        func key(_ name: String) -> String { name.lowercased().filter { $0.isLetter || $0.isNumber } }
        let ordered = Set(names).sorted { (key($0).count, $0) < (key($1).count, $1) }
        var chosen: [String] = []
        var map: [String: String] = [:]
        for name in ordered {
            let k = key(name)
            if let parent = chosen.first(where: { let p = key($0); return p.count >= 4 && k.hasPrefix(p) }) {
                map[name] = parent
            } else {
                chosen.append(name)
                map[name] = name
            }
        }
        return map
    }
}
