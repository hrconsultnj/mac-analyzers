import SwiftUI
#if canImport(ProKit)
import ProKit
#endif

/// What can be pushed from the app's own screens.
enum AppRoute: Hashable, Codable, Sendable {
    /// Turn Off or Remove, pushed from Setup.
    case turnOff
}

/// Updates, How It Works and Support.
///
/// A supporter build has no Support row: its badge at the foot of the
/// sidebar is the way in, and the `support` target still lands on the
/// licence screen.
@MainActor
enum AppGroup {

    static let updates = SectionID("updates")
    static let howItWorks = SectionID("howItWorks")
    static let support = SectionID("support")

    static let group = SidebarGroup(
        title: "Mac Analyzers",
        rows: rows,
        hidden: [support],
        root: screen,
        resolve: resolve)

    private static var rows: [SidebarRow] {
        var rows = [
            SidebarRow(updates, "Updates", symbol: "arrow.down.circle", badge: .updateAvailable),
            SidebarRow(howItWorks, "How It Works", symbol: "questionmark.circle"),
        ]
        #if !canImport(ProKit)
        rows.append(SidebarRow(support, "Support", symbol: "heart"))
        #endif
        return rows
    }

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case updates: UpdateSettingsView()
        case howItWorks: AboutSettingsView()
        case support:
            #if canImport(ProKit)
            ProLicenseScreen()
            #else
            SupportSettingsView()
            #endif
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: AppRoute) -> some View {
        switch route {
        case .turnOff: UninstallView()
        }
    }

    private static func resolve(_ target: String) -> Location? {
        switch target {
        case "update": Location(updates)
        case "about": Location(howItWorks)
        case "support": Location(support)
        default: nil
        }
    }
}
