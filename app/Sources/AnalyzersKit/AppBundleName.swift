import Foundation

/// The app a command line belongs to, read from its path:
/// "/Applications/Opera.app/Contents/…/Opera Helper" → "Opera".
///
/// One implementation, because three copies of the pattern all had the same
/// flaw: they looked for ".app" anywhere, so `com.apple.WebKit.WebContent`
/// matched at "com.app" and every WebKit process was listed as "com". A
/// bundle name only counts when ".app" ENDS a path component.
public enum AppBundleName {

    /// The first `.app` bundle named in `command`, without the extension, or
    /// nil when the command is not inside one.
    public static func first(in command: String) -> String? {
        guard let range = command.range(of: #"[^/]+\.app(?=/|\s|$)"#, options: .regularExpression)
        else { return nil }
        return String(command[range].dropLast(4))
    }
}
