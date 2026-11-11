import Foundation

/// The setting a cleanup preview was made with — Daily or Deep for Caches & Builds, Trash or
/// Delete Permanently for Temp & Agents — belongs to the PREVIEW, not to the screen.
///
/// An apply runs with the preview's options (`JobStore.apply(from:)` copies them), so whatever a
/// screen shows, asks and words must come from the same place or a person approves one thing and
/// the engine does another. This is the one rule for which setting a Storage screen shows:
/// the preview's, when one is on screen; the newest logged preview's, when that is what the
/// screen shows read-only; and only with neither, the person's own pick for the next preview.
public enum StorageSetting {

    /// The setting the screen shows, words and acts under.
    public static func shown(kind: JobKind, preview: JobOptions?, lastKnownBanner: String?,
                             chosen: JobOptions) -> JobOptions {
        if let preview { return normalized(kind, preview) }
        if let lastKnownBanner { return options(kind: kind, banner: lastKnownBanner) }
        return normalized(kind, chosen)
    }

    /// What the screen asks and words its Apply with: the words of the setting `shown` decides, in one
    /// place so a screen cannot word one setting and send another.
    public static func words(kind: JobKind, preview: JobOptions?, lastKnownBanner: String?, chosen: JobOptions) -> CleanWords {
        CleanWords.words(kind: kind, setting: shown(kind: kind, preview: preview, lastKnownBanner: lastKnownBanner, chosen: chosen))
            ?? CleanWords.caches(deep: false)
    }

    /// Whether choosing `picked` in the menu changes what is on screen: only then is the preview
    /// (or the last-known list) put away, because it was made with the other setting.
    public static func isChange(kind: JobKind, shown: JobOptions, picked: JobOptions) -> Bool {
        normalized(kind, shown) != normalized(kind, picked)
    }

    /// The setting a logged run was made with, read from its banner.
    public static func options(kind: JobKind, banner: String) -> JobOptions {
        switch kind {
        case .storageClean: JobOptions(deep: banner.contains("mode=deep"))
        case .tempClean: JobOptions(permanent: banner.lowercased().contains("permanent"))
        default: JobOptions()
        }
    }

    /// Only the fields a kind's screen offers count as its setting.
    public static func normalized(_ kind: JobKind, _ options: JobOptions) -> JobOptions {
        switch kind {
        case .storageClean: JobOptions(deep: options.deep)
        case .tempClean: JobOptions(permanent: options.permanent)
        default: JobOptions()
        }
    }
}

/// The words an Apply and its confirmation use for a setting: one place, so the title, the
/// question and the second question can only follow the setting that was passed in.
public struct CleanWords: Equatable, Sendable {
    public let applyTitle: String
    public let verb: String
    public let destination: String
    public let message: String
    /// The second, plainer question for something that cannot be undone; nil when it can.
    public let permanentWarning: String?

    public static func caches(deep: Bool) -> CleanWords {
        CleanWords(applyTitle: "Remove", verb: "Remove", destination: "permanently",
                   message: deep
                       ? "These are caches and builds that are made again the next time they are needed. A Deep cleanup also thins Time Machine's local snapshots, if that row is ticked."
                       : "These are caches and builds that are made again the next time they are needed.",
                   permanentWarning: "They are deleted, not moved to the Trash, so this can't be undone.")
    }

    public static func temp(permanent: Bool) -> CleanWords {
        permanent
            ? CleanWords(applyTitle: "Delete", verb: "Delete", destination: "permanently",
                         message: "Nothing here is open, recent, live or someone else's.",
                         permanentWarning: "Deleted items can't be put back.")
            : CleanWords(applyTitle: "Move to Trash", verb: "Move", destination: "to the Trash",
                         message: "You can put them back from Undo. The space returns when the Trash is emptied.",
                         permanentWarning: nil)
    }

    public static func words(kind: JobKind, setting: JobOptions) -> CleanWords? {
        switch kind {
        case .storageClean: caches(deep: setting.deep)
        case .tempClean: temp(permanent: setting.permanent)
        default: nil
        }
    }
}
