import AppKit
import AnalyzersKit
import SwiftUI

/// What a raw-output screen shows: one run found in a log, one tracked job, or
/// a whole log. Codable so the screen survives a relaunch like any other route
/// (a job's output does not: restoring drops it, see `NavigationPersistence`).
enum RawOutputSubject: Hashable, Codable {
    case run(RunReference)
    case job(UUID)
    /// An `EngineLog` raw value; the screen shows the end of that log.
    case log(String)
}

/// The raw text of a run, a job or a log, inside the app: searchable, selectable,
/// opening at the newest line, with Copy in the toolbar. It is what every "Open in
/// TextEdit" becomes — nothing here opens another app. Push it from any screen:
///
///     navigator.push(.overview(.raw(.log(EngineLog.storageClean.rawValue))))
///
/// or open it by link: `raw:<log raw value>`, for example `raw:storageClean`.
/// A run or a job gets there from its row's menu ("Show Raw Output") or from its own
/// screen. A whole log shows its last `RawOutputScreen.tailLength` lines and says so.
struct RawOutputScreen: View {
    let subject: RawOutputSubject

    /// How much of a whole log is read: the end of it, where the latest run is.
    static let tailLength = 5000
    /// The bytes read from the end of a log to find those lines.
    private static let tailBytes = 1_048_576

    @Environment(JobStore.self) private var store
    @State private var query = ""
    @State private var log: LoadedLog?
    private var model: ActivityModel { .shared }

    private struct LoadedLog { var lines: [String]; var cut: Bool }

    /// The text, or nil while it is still being found.
    private var found: (lines: [String], cut: Bool)? {
        switch subject {
        case .run(let reference):
            guard model.hasLoaded else { return nil }
            return model.logRun(for: reference).map { ($0.lines, false) }
        case .job(let id):
            if let job = store.jobs.first(where: { $0.id == id }) { return (job.lines, false) }
            guard model.hasLoaded else { return nil }
            return model.rows.first { $0.jobID == id }.map { (model.lines(for: $0), false) }
        case .log:
            return log.map { ($0.lines, $0.cut) }
        }
    }

    private var isGone: Bool {
        switch subject {
        case .run, .job: model.hasLoaded && found == nil
        case .log: false
        }
    }

    private var subtitle: String {
        switch subject {
        case .run(let reference): model.row(for: reference)?.displayTitle ?? Names.log(reference.log)
        case .job(let id): model.rows.first { $0.jobID == id }?.displayTitle ?? "Job"
        case .log(let raw): EngineLog(rawValue: raw).map(Names.log) ?? raw
        }
    }

    private var matching: [String] {
        let all = found?.lines ?? []
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty ? all : all.filter { $0.localizedStandardContains(needle) }
    }

    var body: some View {
        DataScreen(title: Names.Raw.screen, subtitle: subtitle) {
            content
        }
        .searchable(text: $query, prompt: Names.Raw.searchPrompt)
        .toolbar {
            ToolbarItem {
                Button(query.isEmpty ? Names.Raw.copy : "Copy Matching Lines", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(matching.joined(separator: "\n"), forType: .string)
                }
                .disabled(matching.isEmpty)
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if isGone {
            ContentUnavailableView(gone.title, systemImage: "questionmark.folder", description: Text(gone.detail))
        } else if let found {
            if found.lines.isEmpty {
                ContentUnavailableView(Names.Raw.noOutput, systemImage: "text.alignleft",
                                       description: Text("This one has no text to show."))
            } else if matching.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                VStack(spacing: 0) {
                    RunLinesView(lines: matching, anchorBottom: true)
                    if found.cut {
                        Text("Last \(found.lines.count.formatted()) lines")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 4)
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var gone: (title: String, detail: String) {
        switch subject {
        case .job: ("This Run Is No Longer Recorded", "It is not in this session, and the list of past runs no longer has it.")
        default: ("This Run Is No Longer in the Log", "The log has moved on since this entry was listed.")
        }
    }

    private func load() async {
        switch subject {
        case .run, .job:
            await model.refreshIfNeeded(store: store)
        case .log(let raw):
            guard let url = EngineLog(rawValue: raw)?.url else { log = LoadedLog(lines: [], cut: false); return }
            let keep = Self.tailLength, bytes = Self.tailBytes
            log = await Task.detached(priority: .userInitiated) { Self.readTail(url, lines: keep, bytes: bytes) }.value
        }
    }

    /// The last `lines` lines, found by reading the last `bytes` bytes (not the whole
    /// file) and decoding leniently, so one bad byte costs a character, not the log.
    nonisolated private static func readTail(_ url: URL, lines keep: Int, bytes: Int) -> LoadedLog {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return LoadedLog(lines: [], cut: false) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var all = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // the window may start mid-line: that first piece is not a line
        if start > 0, !all.isEmpty { all.removeFirst() }
        let cut = start > 0 || all.count > keep
        return LoadedLog(lines: Array(all.suffix(keep)), cut: cut)
    }
}
