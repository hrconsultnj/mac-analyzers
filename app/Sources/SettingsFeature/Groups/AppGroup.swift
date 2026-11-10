import SwiftUI
import Observation
import AnalyzersKit
#if canImport(ProKit)
import ProKit
#endif

/// What can be pushed from the app's own screens. None yet.
enum AppRoute: Hashable, Codable, Sendable {
    // An enum with no cases cannot synthesize Codable. Add a case and delete
    // both methods below.
    init(from decoder: Decoder) throws {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                debugDescription: "AppRoute has no cases"))
    }

    func encode(to encoder: Encoder) throws {}
}

/// Whether a newer release exists, for the Updates row's badge.
@MainActor @Observable
final class UpdateBadge {
    static let shared = UpdateBadge()
    private(set) var updateAvailable = false

    func refresh() async {
        if let latest = await UpdateChecker.latestVersion() {
            updateAvailable = UpdateChecker.isNewer(latest, than: UpdateChecker.installedVersion)
        }
    }
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
        aliases: [
            "update": .main(Location(updates)),
            "about": .main(Location(howItWorks)),
            "support": .main(Location(support)),
        ],
        load: { await UpdateBadge.shared.refresh() })

    private static var rows: [SidebarRow] {
        var rows = [
            SidebarRow(updates, "Updates", symbol: "arrow.down.circle",
                       badge: { UpdateBadge.shared.updateAvailable ? "1" : nil }),
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

    /// No pushed screens yet.
    @ViewBuilder static func destination(for route: AppRoute) -> some View {
        EmptyView()
    }
}
