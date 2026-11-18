import AnalyzersKit
import AppKit
import SwiftUI

/// How the app looks, remembered between launches: Auto (the system's), Light or Dark. Applied to the whole app through
/// `NSApp.appearance`; Auto clears it so the system decides again.
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case auto, light, dark

    public static let key = "appearance.choice"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: Names.SettingsHub.appearanceAuto
        case .light: Names.SettingsHub.appearanceLight
        case .dark: Names.SettingsHub.appearanceDark
        }
    }

    public static var stored: AppearancePreference {
        UserDefaults.standard.string(forKey: key).flatMap(AppearancePreference.init(rawValue:)) ?? .auto
    }

    @MainActor
    public func apply() {
        switch self {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// At launch: only a choice the person made is applied (Auto is what the app starts with).
    @MainActor
    public static func applyStored() {
        let choice = stored
        if choice != .auto { choice.apply() }
    }
}

/// The sidebar's icons: the coloured tiles or the plain symbols the system draws.
enum SidebarIconStyle: String, CaseIterable {
    case coloured, plain
    static let key = "sidebar.iconStyle"
    var title: String { self == .coloured ? Names.SettingsHub.iconsColoured : Names.SettingsHub.iconsPlain }
}
