import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The free build's Support screen. Everything that explains or audits what
/// runs on your Mac is free and stays free — this screen exists because the
/// people who find that worth paying for should have somewhere to say so,
/// not because anything here is withheld.
struct SupportSettingsView: View {

    private let repo = "https://github.com/hrconsultnj/mac-analyzers"

    var body: some View {
        PaneScaffold(symbol: "heart.fill", color: .pink, title: "Support this project",
                     caption: "Mac Analyzers is free, and the parts that tell you what your Mac is doing always will be.") {
            Section {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("What you already have")
                        .font(.callout.weight(.semibold))
                    ForEach(freeThings, id: \.self) { line in
                        Label(line, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("None of this is a trial, and none of it expires.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Ways to help") {
                LabeledContent {
                    Button("Open on GitHub") { open(repo) }
                } label: {
                    Text("Star the project")
                    Text("The cheapest thing that actually helps other people find it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent {
                    Button("Report an issue") { open("\(repo)/issues/new") }
                } label: {
                    Text("Tell me what broke")
                    Text("A screenshot and what you expected is enough. Bug reports are how the awkward edges get found.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent {
                    Button("Read the code") { open(repo) }
                } label: {
                    Text("Check what it does")
                    Text("Every script that touches your Mac is readable. A tool with this much reach should be inspectable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Some builds of Mac Analyzers include extra conveniences on top of everything above. If you have one, the licence screen appears here instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private let freeThings = [
        "Continuous memory watching, with the reasons for every action written down",
        "Scheduled cleanups you can preview before anything is removed",
        "Full reports on what is using memory, disk and network",
        "An undo trail for everything that was moved to the Trash",
    ]

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
