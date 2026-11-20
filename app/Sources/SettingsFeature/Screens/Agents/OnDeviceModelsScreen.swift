import SwiftUI
import AnalyzersKit
import AgentFeature
import UIComponents

/// Settings → Agents → On-Device Models: the curated model catalog with fit
/// badges, downloads, the installed list, and the opt-in Hugging Face search.
/// The curated list comes from `ModelCatalog` (bundled floor, refreshed copy
/// overlay); installs are `InstalledModels`' scan of the models directory;
/// downloads are the one shared `ModelDownloader`. The active model lives in
/// `ConfigStore.agent.modelID` — this screen mirrors it, the stores never do.
struct OnDeviceModelsScreen: View {
    @Environment(ConfigStore.self) private var config
    @State private var catalog = ModelCatalog.shared
    @State private var downloader = ModelDownloader.shared
    @State private var installed = InstalledModels.shared
    @State private var assessment = MachineAssessment.assess()

    // Hugging Face search: fetched only on submit (DEC-03), never while typing.
    @State private var query = ""
    @State private var searchResults: [HFSearchResult]?
    @State private var searchState = SearchState.idle

    enum SearchState: Equatable {
        case idle, searching, failed
    }

    var body: some View {
        PaneScaffold(symbol: "internaldrive.fill", color: .mint, title: Names.Screen.onDeviceModels,
                     caption: "Local models that run entirely on this Mac.") {
            assessmentSection
            recommendedSection
            installedSection
            huggingFaceSection
        }
        .task {
            await catalog.refreshIfDue()
            installed.reload()
            assessment = MachineAssessment.assess()
        }
    }

    // MARK: - Assessment

    private var assessmentSection: some View {
        Section {
            LabeledContent("This Mac",
                           value: "\(assessment.physicalMemoryGB) GB memory · \(assessment.freeDiskGB) GB free.")
        } footer: {
            Text("A model downloads once and then answers without sending anything anywhere. The catalog refreshes itself from Sparehold's repository; the models shipped with this copy always work offline.")
        }
    }

    // MARK: - Recommended models

    private var recommendedSection: some View {
        Section {
            ForEach(catalog.recommended(for: assessment.tier)) { entry in
                ModelCard(entry: entry, assessment: assessment,
                          installed: installed.installed(entry.id),
                          download: downloader.download(for: entry.id),
                          isActive: config.agent.modelID == entry.id,
                          use: { activate(entry.id) },
                          startDownload: { downloader.start(entry) },
                          cancelDownload: { downloader.cancel(entry.id) },
                          delete: { installed.delete($0) })
            }
        } header: {
            Text("Recommended models")
        } footer: {
            if catalog.lastRefresh == .unreachable {
                Text("The tested-model list could not be refreshed — showing the models this copy ships with. Downloads go to \(AnalyzersPaths.displayPath(AnalyzersPaths.modelsDirectory)).")
            } else {
                Text("Local MLX models tested with Sparehold. Downloads go to \(AnalyzersPaths.displayPath(AnalyzersPaths.modelsDirectory)).")
            }
        }
    }

    // MARK: - Installed

    private var installedSection: some View {
        Section {
            if installed.models.isEmpty {
                EmptyState(label: { Label("No models downloaded", systemImage: "internaldrive") },
                           description: { Text("Download a model to run the agent on this Mac.") })
            } else {
                ForEach(installed.models) { model in
                    installedRow(model)
                }
            }
        } header: {
            Text("Installed")
        } footer: {
            if !installed.models.isEmpty {
                Text("Installed models use \(ByteSize.text(installed.totalBytes, .cell)). Deleting moves a model to the Trash — it comes back if you empty the Trash by mistake.")
            }
        }
    }

    private func installedRow(_ model: InstalledModel) -> some View {
        HStack(spacing: Tokens.Space.m) {
            IconTile(symbol: "internaldrive.fill", color: .mint, side: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                Text(modelDisplayName(model))
                Text("\(ByteSize.text(model.sizeBytes, .cell)) · \(model.repo)")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.m)
            if config.agent.modelID == model.id {
                BadgeCapsule(text: "ACTIVE", color: Tokens.Status.safe.tint)
            } else {
                Button("Use This Model") { activate(model.id) }
                    .controlSize(.small)
            }
            Button(role: .destructive) {
                if config.agent.modelID == model.id {
                    config.agent.modelID = ""
                    try? config.save()
                }
                _ = installed.delete(model)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.small)
        }
        .padding(.vertical, Tokens.Space.xxs)
    }

    /// The name a row shows: the catalog's name when this id is one of its
    /// models, the repo name otherwise (community installs).
    private func modelDisplayName(_ model: InstalledModel) -> String {
        catalog.entry(id: model.id)?.name ?? model.repo.split(separator: "/").last.map(String.init) ?? model.repo
    }

    /// Make a model the agent's (`AGENT_MODEL` in the managed config block).
    private func activate(_ id: String) {
        config.agent.modelID = id
        try? config.save()
    }

    // MARK: - Hugging Face

    private var huggingFaceSection: some View {
        Section {
            TextField("Search Hugging Face for MLX models", text: $query)
                .onSubmit { Task { await search() } }
            switch searchState {
            case .idle:
                if searchResults == nil {
                    EmptyState("No Hugging Face models installed", systemImage: "magnifyingglass",
                               description: Text("Search to find installable MLX models."))
                }
            case .searching:
                LoadingState("Searching Hugging Face…")
            case .failed:
                EmptyState("Could Not Reach Hugging Face", systemImage: "wifi.exclamationmark",
                           description: Text("The search needs the network. Try again."))
            }
            if let results = searchResults, results.isEmpty, searchState == .idle {
                EmptyState.search(text: query)
            }
            ForEach(searchResults ?? []) { result in
                SearchResultRow(result: result,
                                download: downloader.download(for: result.id),
                                installedAlready: installed.installed(result.id) != nil,
                                warning: mismatchWarning(for: result),
                                startDownload: { downloader.start(entry(for: result)) },
                                cancelDownload: { downloader.cancel(result.id) })
            }
        } header: {
            Text("Hugging Face models")
        } footer: {
            Text("Community conversions, unvetted — searched only when you press return. Sparehold checks each file against Hugging Face's own checksums as it downloads.")
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchState = .searching
        let results = await catalog.searchHuggingFace(trimmed)
        searchResults = results
        searchState = results == nil ? .failed : .idle
    }

    /// A community row, as far as the search can describe it — sizes arrive
    /// from the repo's file tree when the download starts.
    private func entry(for result: HFSearchResult) -> ModelEntry {
        ModelEntry(fromSearch: result.id, downloads: result.downloads ?? 0)
    }

    /// The parser-mismatch warning a community row may need: when its name
    /// suggests a tool-call dialect different from the active model's, the
    /// row says so before the person spends the download.
    private func mismatchWarning(for result: HFSearchResult) -> String? {
        guard let active = catalog.entry(id: config.agent.modelID), !active.id.isEmpty else { return nil }
        guard let inferred = ModelParser.inferred(fromText: result.id), inferred != active.parser else { return nil }
        return "Looks like a \(inferred.title) model — different tool-call format from \(active.name). It may not run tools with Ask."
    }
}

// MARK: - Model card

/// One recommended model: name and blurb, the fit badge, the six facts, and
/// the one action the model's state calls for — Download (with its size
/// stated first), the progress row while the files come in, or the installed
/// row with Use This Model and Delete.
private struct ModelCard: View {
    let entry: ModelEntry
    let assessment: MachineAssessment
    let installed: InstalledModel?
    let download: ModelDownload?
    let isActive: Bool
    let use: () -> Void
    let startDownload: () -> Void
    let cancelDownload: () -> Void
    let delete: (InstalledModel) -> Void

    private var fit: ModelFit { entry.fit(assessment) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(alignment: .center, spacing: Tokens.Space.m) {
                IconTile(symbol: "cpu", color: .mint, side: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                    Text(entry.name)
                    Text(entry.blurb)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Tokens.Space.m)
                BadgeCapsule(text: fit.title.uppercased(), color: fitColor)
            }
            SixFactGrid(entry: entry)
            actionRow
        }
        .padding(.vertical, Tokens.Space.xxs)
    }

    private var fitColor: Color {
        switch fit {
        case .fitsWell: .green
        case .tight: .orange
        case .wontFit: .red
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if let installed {
            HStack {
                Label(isActive ? "Active" : "Installed", systemImage: isActive ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(isActive ? Color.green : Color.secondary)
                Spacer(minLength: Tokens.Space.m)
                if !isActive {
                    Button("Use This Model") { use() }.controlSize(.small)
                }
                Button(role: .destructive) {
                    delete(installed)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
        } else if let download, download.phase != .finished {
            DownloadProgressRow(download: download, cancel: cancelDownload)
        } else {
            HStack {
                Button {
                    startDownload()
                } label: {
                    Label("Download · \(downloadSize)", systemImage: "arrow.down.circle")
                }
                .disabled(fit == .wontFit)
                if fit == .wontFit {
                    Text("Won't fit on this Mac — needs \(estMemory) with room to spare.")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var downloadSize: String {
        ByteSize.text(Int64(entry.downloadGB * 1_073_741_824), .cell)
    }

    private var estMemory: String {
        ByteSize.text(Int64(entry.memoryGB * 1_073_741_824), .cell)
    }
}

/// The six facts a model card shows, as a compact grid: three label/value
/// pairs per row, the label small and secondary above the value.
private struct SixFactGrid: View {
    let entry: ModelEntry

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Tokens.Space.xl, verticalSpacing: Tokens.Space.s) {
            GridRow {
                fact("Provider", entry.provider)
                fact("Quantization", orDash(entry.quantization))
                fact("Context", context)
            }
            GridRow {
                fact("Parameters", orDash(entry.parameters))
                fact("Est. memory", memorySize)
                fact("Download size", downloadSize)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
            Text(label)
                .font(Tokens.Typography.micro)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Tokens.Typography.rowTitle)
        }
    }

    private func orDash(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }

    /// The window the engine opens, in the compact form a card carries
    /// (131072 → "128k tokens"); the catalog caps a model's native window.
    private var context: String {
        guard entry.contextTokens > 0 else { return "—" }
        if entry.contextTokens >= 1024 {
            let k = entry.contextTokens / 1024
            return "\(k)k tokens"
        }
        return "\(entry.contextTokens) tokens"
    }

    private var memorySize: String {
        ByteSize.text(Int64(entry.memoryGB * 1_073_741_824), .cell)
    }

    private var downloadSize: String {
        ByteSize.text(Int64(entry.downloadGB * 1_073_741_824), .cell)
    }
}

/// The row that replaces the Download button while a model's files come in:
/// a determinate bar, the bytes so far of the total the repo's tree
/// reported, the settled rate, and Cancel. Cancel keeps the `.part` files —
/// starting again resumes, it never restarts.
private struct DownloadProgressRow: View {
    let download: ModelDownload
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
            ProgressView(value: download.fraction ?? 0)
            HStack {
                Text(statusLine)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Tokens.Space.m)
                if download.phase == .downloading || download.phase == .preparing {
                    Button("Cancel") { cancel() }.controlSize(.small)
                }
            }
            if download.phase == .failed, let failure = download.failureText {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Status.caution.tint)
            }
        }
    }

    private var statusLine: String {
        switch download.phase {
        case .preparing:
            return "Reading the model's file list…"
        case .verifying:
            return "Checking checksums…"
        case .failed:
            return "Stopped — starting again resumes from where it left off."
        case .cancelled:
            return "Cancelled — starting again resumes from where it left off."
        case .finished:
            break
        case .downloading:
            break
        }
        let done = ByteSize.text(download.bytesDone, .cell)
        if download.bytesTotal > 0 {
            var line = "\(done) of \(ByteSize.text(download.bytesTotal, .cell))"
            if download.bytesPerSecond > 0 {
                line += " · \(ByteSize.rate(download.bytesPerSecond))"
            }
            return line
        }
        return "\(done) downloaded"
    }
}

// MARK: - Search result row

/// One Hugging Face search result: the repo, its popularity, the
/// "community — unvetted" badge, the parser-mismatch warning when there is
/// one, and Download — the same downloader, minus the pinned checksum.
private struct SearchResultRow: View {
    let result: HFSearchResult
    let download: ModelDownload?
    let installedAlready: Bool
    let warning: String?
    let startDownload: () -> Void
    let cancelDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
            HStack(spacing: Tokens.Space.m) {
                IconTile(symbol: "shippingbox", color: .mint, side: 20).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                    Text(result.id)
                    Text(popularity)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Tokens.Space.m)
                BadgeCapsule(text: "community — unvetted", color: Tokens.Status.caution.tint)
                if download == nil || download?.phase == .finished {
                    Button("Download") { startDownload() }
                        .controlSize(.small)
                        .disabled(installedAlready)
                }
            }
            .padding(.vertical, Tokens.Space.xxs)
            if let download, download.phase != .finished {
                DownloadProgressRow(download: download, cancel: cancelDownload)
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Status.caution.tint)
            }
        }
    }

    private var popularity: String {
        var parts: [String] = []
        if let downloads = result.downloads {
            parts.append("\(downloads.formatted()) downloads")
        }
        if let likes = result.likes, likes > 0 {
            parts.append("\(likes.formatted()) likes")
        }
        return parts.joined(separator: " · ")
    }
}
