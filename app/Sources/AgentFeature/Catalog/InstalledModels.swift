import Foundation
import AnalyzersKit

/// One complete install: a folder under `AnalyzersPaths.modelsDirectory`
/// carrying the marker written after every file verified its checksum. A
/// folder without the marker is a download that never finished, and is
/// invisible here.
public struct InstalledModel: Identifiable, Equatable, Sendable {
    /// The catalog id (or, for community rows, the repo id) the folder holds.
    public let id: String
    public let repo: String
    public let revision: String
    /// The tool-call dialect recorded at install time; nil when the marker
    /// names one the app does not know (an older catalog's id).
    public let parser: ModelParser?
    public let installedAt: Date
    /// Everything in the folder, in bytes — the screen's GB figures.
    public let sizeBytes: Int64
    public let url: URL
}

/// What the marker inside a model folder records — the downloader writes it,
/// the scanner reads it. One schema, both sides.
public struct InstallRecord: Codable, Sendable, Equatable {
    public let id: String
    public let repo: String
    public let revision: String
    public let parser: String
    public let installedAt: Date

    public init(id: String, repo: String, revision: String, parser: String, installedAt: Date) {
        self.id = id
        self.repo = repo
        self.revision = revision
        self.parser = parser
        self.installedAt = installedAt
    }
}

/// The installed-model store behind the On-Device Models screen's Installed
/// section: a scan of the models directory, delete-to-Trash (house rule:
/// everything reversible), and the totals for the screen's space line.
///
/// The ACTIVE model is not stored here — its single source of truth is
/// `ConfigStore.agent.modelID` (`AGENT_MODEL`), mirrored on screen through
/// the one `ConfigStore` the app owns; this store is the disk's view.
@MainActor
@Observable
public final class InstalledModels {

    /// The marker file that says a folder finished and verified. Nonisolated
    /// so the download engine (an actor) can name it without a main-actor hop.
    public nonisolated static let markerName = ".installed.json"

    public static let shared = InstalledModels()

    /// Complete installs, newest first.
    public private(set) var models: [InstalledModel] = []

    public init() {
        reload()
    }

    /// Everything installed, in bytes — the "installed models use X GB" line.
    public var totalBytes: Int64 {
        models.reduce(0) { $0 + $1.sizeBytes }
    }

    public func installed(_ id: String) -> InstalledModel? {
        models.first { $0.id == id }
    }

    /// Rescan the models directory. Cheap enough to run on every screen
    /// appear and after every download, delete or cancel.
    public func reload() {
        let root = AnalyzersPaths.modelsDirectory
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        models = folders.compactMap { folder in
            guard folder.hasDirectoryPath,
                  let data = try? Data(contentsOf: folder.appending(path: Self.markerName)),
                  let record = try? JSONDecoder.iso8601.decode(InstallRecord.self, from: data)
            else { return nil }
            return InstalledModel(
                id: record.id,
                repo: record.repo,
                revision: record.revision,
                parser: ModelParser(rawValue: record.parser),
                installedAt: record.installedAt,
                sizeBytes: Self.directorySize(folder),
                url: folder)
        }
        .sorted { $0.installedAt > $1.installedAt }
    }

    /// Move a model to the Trash — reversible, like every delete this app
    /// offers. Returns the human-readable failure when the Trash refuses.
    @discardableResult
    public func delete(_ model: InstalledModel) -> String? {
        do {
            try FileManager.default.trashItem(at: model.url, resultingItemURL: nil)
            reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Sizes

    /// Every regular file in the folder, summed — the number a Delete row
    /// quotes before the person confirms it.
    static func directorySize(_ folder: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}

private extension JSONDecoder {
    /// Markers are written by this app with ISO-8601 dates; read the same way.
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
