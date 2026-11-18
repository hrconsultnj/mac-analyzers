import SwiftUI
import AnalyzersKit
import UIComponents

/// "Updates From": which channel this copy follows (Releases and Beta always, This Copy only for a copy built from a clone),
/// the one line that says what the channel is, and, for Beta and This Copy, what that channel found. What installing does
/// is the caption at the end, in plain words per channel.
struct UpdateChannelSection: View {
    @Bindable var updates: UpdateState
    let checking: Bool
    let installExplanation: String

    var body: some View {
        Section {
            FullWidthSegments(options: updates.channels.map { ($0, $0.title) }, selection: $updates.channel,
                              help: "Releases: the newest published release. Beta: the newest pre-release. This Copy: your own clone, uncommitted changes included.")
            Text(Names.ChannelText.describes(updates.channel))
                .font(.caption)
                .foregroundStyle(.secondary)
            UpdateChannelRows(updates: updates, checking: checking)
            if updates.isAvailable {
                Text(installExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(Names.Update.updatesFrom).font(.headline)
        }
    }
}

/// "Check Automatically": the one switch about notices, with what it does behind an info button. It is honest about what
/// exists today: the app looks every 6 hours and says so once per version; there is no automatic install.
struct AutomaticChecksRow: View {
    @Bindable var updates: UpdateState
    @State private var showingInfo = false

    var body: some View {
        Section {
            HStack {
                Toggle(Names.Update.checkAutomatically, isOn: $updates.automaticChecks)
                Button { showingInfo.toggle() } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Names.Update.neverByItself)
                .accessibilityLabel("About \(Names.Update.checkAutomatically)")
                .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                    Text(Names.Update.automaticallyInfo)
                        .padding()
                        .frame(width: 320)   // fixed: a popover has no width of its own to take from the list
                }
                Spacer()
            }
        }
    }
}

/// The rows a development channel adds under the picker.
struct UpdateChannelRows: View {
    let updates: UpdateState
    let checking: Bool

    var body: some View {
        switch updates.channel {
        case .releases:
            EmptyView()
        case .beta:
            LabeledContent(Names.Channel.newestBeta) {
                Text(updates.newestBeta ?? (checking ? "Checking…" : "None Yet"))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .help("The newest beta published on GitHub: a pre-release of the next version")
            stateLabel
            if updates.cloneDirty == true {
                Label("Your clone has changes that are not committed yet. Updating moves your clone to the newest beta and builds those changes in too.",
                      systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        case .thisCopy:
            if let facts = updates.cloneFacts {
                LabeledContent("Your Clone") {
                    Text(cloneLine(facts)).foregroundStyle(.secondary)
                }
                .help("The git clone this copy was built from, read with git on this Mac")
            }
            stateLabel
        }
    }

    private func cloneLine(_ facts: CloneFacts) -> String {
        var parts = [facts.branch ?? "no branch"]
        if case .cloneAhead(let count) = facts.relation { parts.append(count == 1 ? "1 newer commit" : "\(count) newer commits") }
        if facts.isDirty { parts.append("uncommitted changes") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var stateLabel: some View {
        if let state = updates.channelState {
            let text = state.sentence(for: updates.channel, facts: updates.cloneFacts)
            switch state {
            case .upToDate:
                Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .behind, .differs, .offered:
                Label(text, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .ahead:
                Label(text, systemImage: "hammer.fill").foregroundStyle(.blue)
            case .unknown, .unavailable:
                Label(text, systemImage: "info.circle").foregroundStyle(.secondary)
            }
        }
    }
}
