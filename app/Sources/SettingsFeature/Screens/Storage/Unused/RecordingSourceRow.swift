import AnalyzersKit
import AppKit
import SwiftUI

/// One recording source in the Sources window: its icon and name, where it is, what the last preview found there, the
/// switch, and what a person needs to know first (the warning of a source that keeps a history, or the question of
/// looking in a folder macOS guards). Used for the sources found on this Mac and for the person's own folders.
struct RecordingSourceRow: View {
    let source: RecordingSource
    /// What the newest preview found in this source; nil when it has not been previewed.
    let found: RecordingFound?
    let previewed: Bool
    let days: Int
    @Binding var isOn: Bool
    /// The person's own folder: has a Remove button instead of a note about the app.
    var onRemove: (() -> Void)?
    /// The person clicked Look in <area>.
    var onLook: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 10) {
                    Image(systemName: source.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                        if let path = source.path {
                            Text(StorageLog.short(path))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if source.access == .readable, let text = foundText {
                            Text(text).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    trailing
                }
            }
            .toggleStyle(.switch)
            .disabled(source.access == .missing && !source.isCustom)
            if case .needsAccess(let area) = source.access { access(area) }
            if source.access == .missing, source.path != nil {
                Label("This folder isn't there now.", systemImage: "questionmark.folder")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // a source that keeps its own history says so, whether it is switched on or off
            if source.offer == .offWithWarning, let warning = source.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var trailing: some View {
        if let onRemove {
            Button(Names.Recordings.remove, role: .destructive, action: onRemove)
                .buttonStyle(.borderless)
        }
        if source.access == .readable, let path = source.path {
            Button(Names.Recordings.showInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            .buttonStyle(.borderless)
        }
    }

    private var foundText: String? {
        guard previewed else { return nil }
        guard let found, found.count > 0 else { return "Nothing older than \(days) days" }
        return "\(found.count) \(found.count == 1 ? "recording" : "recordings") · \(ByteSize.format(found.bytes)) older than \(days) days"
    }

    /// The question, said in the person's words, with the one button that lets macOS ask it.
    private func access(_ area: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label("\(source.title) saves to \(StorageLog.short(source.path ?? "").replacingOccurrences(of: "/", with: " › ").replacingOccurrences(of: "~ › ", with: "")). Mac Analyzers needs your permission to look in \(area).",
                  systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(lookTitle(area)) { onLook?(area) }
                .controlSize(.small)
        }
    }

    private func lookTitle(_ area: String) -> String {
        switch area {
        case "Documents": Names.Recordings.lookInDocuments
        case "Desktop": Names.Recordings.lookOnDesktop
        default: Names.Recordings.lookInDownloads
        }
    }
}

/// A source with nothing to switch: found, but never offered, with the reason in a sentence.
struct RecordingNotOfferedRow: View {
    let source: RecordingSource

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: source.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                if let reason = source.warning {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// What a preview found in one source.
struct RecordingFound: Equatable {
    var count: Int
    var bytes: Int64
}
