import Foundation

/// The installed app's identity. Loggers and the bundle id read it from here.
public enum AppIdentity {
    public static let bundleID = "com.sparehold.app"
    /// The bundle id of a Sparehold install. Observed, never written as this app's id.
    public static let legacyBundleID = "com.mac-analyzers.app"
    public static let productName = "Sparehold"
}
