import AnalyzersKit
import SwiftUI
import UniformTypeIdentifiers

/// What the Sources window is editing: the sources found on this Mac and the person's own folders, with their
/// switches, and how old a recording has to be. Nothing is written until Save.
///
/// Discovery runs when the window opens and never looks in Documents, Desktop or Downloads on its own: a source whose
/// folder is there shows **Needs Access**, and clicking Look in Documents (or Desktop) is what lets macOS ask.
@MainActor @Observable
final class RecordingSourcesDraft {
    private(set) var sources: [RecordingSource]
    var days: Int
    /// The guarded places the person has said to look in during this window.
    private(set) var allowed: Set<String> = []
    private(set) var refusal: String?
    private let readers: RecordingReaders

    init(config: ConfigStore, readers: RecordingReaders = .live()) {
        self.readers = readers
        sources = RecordingSourcesStore.startingSources(config: config, readers: readers)
        days = RecordingSourcesStore.dayChoices.contains(config.storage.recordingsDays) ? config.storage.recordingsDays : 90
    }

    /// A fixed list, for looking at the window headless.
    init(fixture: [RecordingSource], days: Int = 90, readers: RecordingReaders) {
        self.readers = readers
        sources = fixture
        self.days = days
    }

    var offered: [RecordingSource] { sources.filter { !$0.isCustom && $0.offer != .notOffered } }
    var custom: [RecordingSource] { sources.filter(\.isCustom) }
    var notOffered: [RecordingSource] { sources.filter { $0.offer == .notOffered } }

    func binding(for source: RecordingSource) -> Binding<Bool> {
        Binding(get: { [weak self] in self?.sources.first { $0.id == source.id }?.enabled ?? false },
                set: { [weak self] value in
                    guard let self, let at = sources.firstIndex(where: { $0.id == source.id }) else { return }
                    sources[at].enabled = value
                })
    }

    /// The person said to look in a guarded place: discover again, keeping every switch and folder as they are now.
    func look(in area: String) {
        allowed.insert(area)
        let kept = RecordingSourcesStore.entries(from: sources)
        let again = RecordingDiscovery.discover(readers: readers, saved: kept, allowed: allowed)
        // a source that was not there to look at stays as the person had it
        sources = again.isEmpty ? sources : again
    }

    func remove(_ source: RecordingSource) { sources.removeAll { $0.id == source.id } }

    func add(folder url: URL) {
        let path = url.path
        let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        // the open panel is the person's own click: the place it chose is theirs to look in
        if let area = RecordingDiscovery.protectedArea(path, home: readers.home) { allowed.insert(area) }
        switch RecordingSourcesStore.adding(folder: path, to: sources, readers: readers, isLink: isLink, allowed: allowed) {
        case .added(let list), .alreadyListed(let list, _):
            sources = list
            refusal = nil
        case .refused(let why):
            refusal = "\(url.lastPathComponent) can't be used: \(why)."
        }
    }

    func dismissRefusal() { refusal = nil }

    func save(in config: ConfigStore) throws {
        try RecordingSourcesStore.save(sources, days: days, in: config)
    }
}

/// The window's content: one form, four sections.
struct RecordingSourcesForm: View {
    let draft: RecordingSourcesDraft
    let found: [String: RecordingFound]
    let previewed: Bool
    @State private var choosing = false

    var body: some View {
        @Bindable var draft = draft
        Form {
            if !draft.offered.isEmpty {
                Section(Names.Recordings.foundOnThisMac) {
                    ForEach(draft.offered) { source in
                        RecordingSourceRow(source: source, found: found[source.id], previewed: previewed, days: draft.days,
                                           isOn: draft.binding(for: source), onLook: { draft.look(in: $0) })
                    }
                }
            }
            Section {
                ForEach(draft.custom) { source in
                    RecordingSourceRow(source: source, found: found[source.id], previewed: previewed, days: draft.days,
                                       isOn: draft.binding(for: source), onRemove: { draft.remove(source) },
                                       onLook: { draft.look(in: $0) })
                }
                Button(Names.Recordings.addFolder, systemImage: "plus") { choosing = true }
                if let refusal = draft.refusal {
                    Label(refusal, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(Names.Recordings.yourFolders)
            } footer: {
                Text("Using OBS, Audio Hijack or another recorder? Add the folder it saves to.")
            }
            if !draft.notOffered.isEmpty {
                Section(Names.Recordings.notOffered) {
                    ForEach(draft.notOffered) { RecordingNotOfferedRow(source: $0) }
                }
            }
            Section {
                Picker(Names.Recordings.keepRecordingsFor, selection: $draft.days) {
                    ForEach(RecordingSourcesStore.dayChoices, id: \.self) { Text("\($0) days").tag($0) }
                }
            } footer: {
                Text("Only recordings older than this are offered for a clean-up, and you review them first.")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { draft.add(folder: url) }
        }
    }
}

/// The Sources window: Cancel and Save over the form. Save writes through `ConfigStore`, the only writer of
/// config.local.sh, and tells the screen so its preview can say it is out of date.
struct RecordingSourcesSheet: View {
    @Environment(ConfigStore.self) private var config
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecordingSourcesDraft?
    @State private var failure: String?
    let found: [String: RecordingFound]
    let previewed: Bool
    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let draft { RecordingSourcesForm(draft: draft, found: found, previewed: previewed) } else { ProgressView() }
            }
            .navigationTitle(Names.Recordings.sources)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(Names.Recordings.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Names.Recordings.save) {
                        guard let draft else { return }
                        do {
                            try draft.save(in: config)
                            onSaved()
                            dismiss()
                        } catch { failure = error.localizedDescription }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .alert("Sources Weren't Saved", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") {}
            } message: { Text(failure ?? "") }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 620)
        .task { if draft == nil { draft = RecordingSourcesDraft(config: config) } }
    }
}

extension View {
    /// The one editor of where Old Recordings looks: the toolbar's Sources…, the empty state's Choose Folders… and
    /// (with Setup's rebuild) Setup's Recording Folders row all open it through this.
    func recordingSourcesSheet(isPresented: Binding<Bool>, found: [String: RecordingFound], previewed: Bool,
                               onSaved: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) { RecordingSourcesSheet(found: found, previewed: previewed, onSaved: onSaved) }
    }
}

/// The Sources window's content as a screen, for `SnapshotRunner` (a sheet is not a window the tool can see):
/// every kind of row the window has.
struct RecordingSourcesFixtureScreen: View {
    @State private var draft = RecordingSourcesDraft(fixture: Self.sources, readers: RecordingReaders(
        home: NSHomeDirectory(), defaultsString: { _, _ in nil }, folderExists: { _ in false },
        appInstalled: { _ in false }, cloudMountNames: { [] }))

    var body: some View {
        DataScreen(title: Names.Recordings.sources, subtitle: "Where Old Recordings looks") {
            RecordingSourcesForm(draft: draft, found: [
                "screenRecordings": RecordingFound(count: 14, bytes: 6_200_000_000),
                "superwhisper": RecordingFound(count: 214, bytes: 410_000_000),
                "custom:\(NSHomeDirectory())/Notes/audio": RecordingFound(count: 2, bytes: 380_000_000),
            ], previewed: true)
        }
    }

    private static var sources: [RecordingSource] {
        let home = NSHomeDirectory()
        func known(_ id: String, path: String?, access: RecordingSource.Access, on: Bool) -> RecordingSource {
            let definition = RecordingSourceCatalog.definition(id)
            return RecordingSource(id: id, kind: id, title: definition?.title ?? id, symbol: definition?.symbol ?? "folder", path: path,
                                   offer: definition?.offer ?? .on, access: access, warning: definition?.warning, enabled: on)
        }
        func own(_ path: String, access: RecordingSource.Access) -> RecordingSource {
            RecordingSource(id: "custom:\(path)", kind: "custom", title: (path as NSString).lastPathComponent, symbol: "folder",
                            path: path, offer: .on, access: access, warning: nil, enabled: true)
        }
        return [
            known("zoom", path: "\(home)/Documents/Zoom", access: .needsAccess("Documents"), on: true),
            known("screenRecordings", path: "\(home)/Desktop/Screenshots", access: .readable, on: true),
            known("superwhisper", path: "\(home)/superwhisper/recordings", access: .readable, on: true),
            known("loomTemporary", path: "\(home)/Movies/Loom/Temporary", access: .readable, on: false),
            own("\(home)/Notes/audio", access: .readable),
            own("\(home)/Documents/Interviews", access: .needsAccess("Documents")),
            known("voiceMemos", path: nil, access: .missing, on: false),
            known("cloudMeetings", path: nil, access: .missing, on: false),
            known("macwhisper", path: nil, access: .missing, on: false),
        ]
    }
}
