import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The Sparehold screen, opened by the item at the foot of the sidebar: the app's logo, its name and version,
/// one line about it, and the screens about the app itself (Updates, How It Works, Support) as rows that
/// open them. They have no sidebar rows of their own.
struct AppHomeView: View {
    @Environment(UpdateState.self) private var updates

    private static let areas: [HubArea] = [
        HubArea(title: Names.Screen.updates, caption: "Check for a newer version, choose which releases to follow, and read what each one brought.",
                symbol: "arrow.down.circle.fill", color: .blue, target: "update"),
        HubArea(title: Names.Screen.howItWorks, caption: "How the app decides, measures and writes everything down.",
                symbol: "questionmark.circle.fill", color: .teal, target: "howItWorks"),
        HubArea(title: Names.Screen.support, caption: "Ways to help, and where to tell us what broke.",
                symbol: "heart.fill", color: .pink, target: "support"),
    ]

    var body: some View {
        ScrollView {
            HubHeader(title: Names.app,
                      caption: "Watches your Mac's memory and disk, cleans up what is safe to, and writes down everything it does.",
                      areas: Self.areas,
                      logo: Image(nsImage: NSApp.applicationIconImage),
                      detail: updates.build.versionText)
                .scenePadding()
        }
        .navigationTitle(Names.app)
        .navigationSubtitle(updates.build.versionText)
    }
}
