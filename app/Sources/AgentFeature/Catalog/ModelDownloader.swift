import Foundation
import CryptoKit
import AnalyzersKit

/// The state of one model download, shown by the card that started it: the
/// progress row replaces the Download button while the files come in, and
/// the failed or cancelled state stays so the person can retry — a retry
/// resumes from the `.part` files left on disk, it never starts the bytes over.
@MainActor
@Observable
public final class ModelDownload: Identifiable {

    public enum Phase: Equatable {
        case preparing      // reading the repo's file tree, preflighting disk
        case downloading
        case verifying      // checksums, then the install marker
        case finished
        case failed
        case cancelled
    }

    public let entry: ModelEntry
    public private(set) var phase: Phase = .preparing
    /// Bytes on disk so far, across the repo's files (resumed bytes included).
    public private(set) var bytesDone: Int64 = 0
    /// The repo's total bytes, from its file tree — the honest total for
    /// community rows whose catalog entry had no stated size.
    public private(set) var bytesTotal: Int64 = 0
    /// What went wrong, written for the person (the card shows it under the row).
    public private(set) var failureText: String?
    /// Bytes per second over the last few seconds, so the number settles
    /// instead of jumping with every chunk.
    public private(set) var bytesPerSecond: Double = 0

    /// 0…1 for the progress bar; nil while the tree has not answered yet.
    public var fraction: Double? {
        guard bytesTotal > 0 else { return nil }
        return min(1, Double(bytesDone) / Double(bytesTotal))
    }

    var task: Task<Void, Never>?

    init(entry: ModelEntry) {
        self.entry = entry
    }

    /// Progress arrives from the download engine on the main actor.
    fileprivate func apply(bytesDone: Int64, bytesTotal: Int64, bytesPerSecond: Double) {
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.bytesPerSecond = bytesPerSecond
    }

    fileprivate func setPhase(_ phase: Phase, failure: String? = nil) {
        self.phase = phase
        self.failureText = failure
    }
}

/// One download at a time per model id, into
/// `AnalyzersPaths.modelsDirectory/<id>/`, verified before activation: every
/// file against Hugging Face's own per-file sha256 (the repo's LFS metadata),
/// and curated rows additionally against the manifest's pinned checksum. A
/// complete install carries a marker file written after verification —
/// `InstalledModels` trusts only the marker, so a folder whose download never
/// finished is never shown as installed. A cancelled or failed attempt keeps
/// its `.part` files; the next attempt resumes them.
@MainActor
@Observable
public final class ModelDownloader {

    /// The active downloads, keyed by model id. A finished entry stays until
    /// its card shows the installed state, so the row never flashes off and on.
    public private(set) var downloads: [String: ModelDownload] = [:]

    public static let shared = ModelDownloader()

    public init() {}

    public func download(for id: String) -> ModelDownload? {
        downloads[id]
    }

    /// Start (or resume) a model's files. A second start for a model already
    /// coming in is ignored — the running download is the answer.
    public func start(_ entry: ModelEntry) {
        if let existing = downloads[entry.id],
           existing.phase == .preparing || existing.phase == .downloading || existing.phase == .verifying {
            return
        }
        let download = ModelDownload(entry: entry)
        downloads[entry.id] = download
        download.task = Task { [weak self] in
            await self?.run(download)
        }
    }

    /// Stop a download at the next chunk boundary. The `.part` files stay on
    /// disk; starting again resumes from them.
    public func cancel(_ id: String) {
        downloads[id]?.task?.cancel()
    }

    /// Forget a finished, failed or cancelled row.
    public func dismiss(_ id: String) {
        downloads[id]?.task = nil
        downloads[id] = nil
    }

    private func run(_ download: ModelDownload) async {
        let entry = download.entry
        let engine = ModelDownloadEngine(
            entry: entry,
            destination: AnalyzersPaths.modelsDirectory.appending(path: entry.id),
            progress: { [weak download] done, total, rate in
                await download?.apply(bytesDone: done, bytesTotal: total, bytesPerSecond: rate)
            })
        do {
            // Early preflight for curated rows, before any network: the
            // stated download size plus the headroom the fit verdict wants.
            if entry.downloadGB > 0 {
                try await engine.preflightDisk(needingBytes: Int64(entry.downloadGB * 1_073_741_824))
            }
            let files = try await engine.fetchFileList()
            try Task.checkCancellation()
            try await engine.preflightDisk(needingBytes: files.totalBytes + ModelDownloadEngine.diskHeadroomBytes)

            download.setPhase(.downloading)
            let hashes = try await engine.downloadAll(files: files)

            download.setPhase(.verifying)
            try await engine.verify(hashes: hashes, files: files)
            try await engine.writeMarker()

            download.setPhase(.finished)
            InstalledModels.shared.reload()
        } catch is CancellationError {
            download.setPhase(.cancelled)
        } catch let error as ModelDownloadEngine.EngineError {
            download.setPhase(.failed, failure: error.message)
        } catch {
            download.setPhase(.failed, failure: error.localizedDescription)
        }
    }
}

/// The downloader's internals: file-tree reads, ranged chunked I/O, hashing
/// and renames — every byte off the main actor, progress reported through a
/// main-actor hop.
private actor ModelDownloadEngine {

    /// One file in the repo's tree, from Hugging Face's public API.
    struct HubFile: Sendable {
        let path: String
        let size: Int64
        /// The file's sha256, from the LFS pointer — the repo's own promise
        /// of what the bytes are. nil for small non-LFS files (configs,
        /// tokenizers), which are verified by the download completing.
        let sha256: String?
    }

    /// The tree, filtered to what a model folder should carry.
    struct FileList: Sendable {
        let files: [HubFile]
        var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    }

    enum EngineError: Error {
        case hubUnreachable(String)
        case diskFull(needed: Int64, free: Int64)
        case checksumMismatch(String)

        var message: String {
            switch self {
            case .hubUnreachable(let repo):
                "Could not read \(repo)'s files from Hugging Face. Check the network and try again."
            case .diskFull(let needed, let free):
                "Not enough disk space: this needs \(ByteSize.text(needed, .cell)), only \(ByteSize.text(free, .cell)) is free."
            case .checksumMismatch(let what):
                "A file did not match its checksum after download (\(what)) — removed, not installed. Try again."
            }
        }
    }

    /// Free space to keep after the download — the same margin the fit
    /// verdict wants (a Mac left with no headroom is worse than a refused
    /// download).
    static let diskHeadroomBytes: Int64 = 5 * 1_073_741_824
    private static let chunkBytes = 512 * 1024
    /// Git housekeeping files no model folder needs.
    private static let skippedFiles: Set<String> = [".gitattributes", ".gitignore"]

    private let entry: ModelEntry
    private let destination: URL
    private let progress: @Sendable (Int64, Int64, Double) async -> Void
    private let fileManager = FileManager.default

    /// Bytes of files already complete, before the file in flight.
    private var doneSoFar: Int64 = 0
    /// The tree's true total, once known; the progress bar's denominator.
    private var treeTotal: Int64 = 0

    init(entry: ModelEntry, destination: URL,
         progress: @escaping @Sendable (Int64, Int64, Double) async -> Void) {
        self.entry = entry
        self.destination = destination
        self.progress = progress
    }

    /// The repo's files, from the public API: everything except the
    /// housekeeping files.
    func fetchFileList() async throws -> FileList {
        struct RawFile: Decodable {
            let path: String
            let size: Int64?
            let lfs: RawLFS?
        }
        struct RawLFS: Decodable {
            let oid: String?
            let size: Int64?
        }
        guard let url = Self.treeURL(repo: entry.repo, revision: entry.revision),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let raw = try? JSONDecoder().decode([RawFile].self, from: data)
        else { throw EngineError.hubUnreachable(entry.repo) }
        let files = raw
            .filter { file in
                let name = (file.path as NSString).lastPathComponent
                return !Self.skippedFiles.contains(name)
            }
            .map { HubFile(path: $0.path, size: $0.lfs?.size ?? $0.size ?? 0, sha256: $0.lfs?.oid) }
        guard !files.isEmpty else { throw EngineError.hubUnreachable(entry.repo) }
        return FileList(files: files)
    }

    /// Refuse to start when the volume cannot take it — the same headroom
    /// the fit verdict wants.
    func preflightDisk(needingBytes needed: Int64) throws {
        let volume = destination.deletingLastPathComponent()
        let values = try? volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        guard free > needed + Self.diskHeadroomBytes else {
            throw EngineError.diskFull(needed: needed, free: free)
        }
    }

    /// Download every file in turn. Returns each file's sha256, computed
    /// from the bytes as they were written — verification needs nothing
    /// re-read.
    func downloadAll(files: FileList) async throws -> [String: String] {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        treeTotal = files.totalBytes
        var hashes: [String: String] = [:]
        for file in files.files {
            hashes[file.path] = try await downloadOne(file: file)
        }
        return hashes
    }

    /// One file: reuse a finished file from an earlier attempt when its hash
    /// still matches, else resume a `.part` (hashing what is already there,
    /// then asking the server for the rest), stream the remainder in chunks
    /// into both the file and the hasher, and rename atomically when
    /// complete. Returns the file's sha256.
    private func downloadOne(file: HubFile) async throws -> String {
        let finalURL = destination.appending(path: file.path)
        let partURL = destination.appending(path: file.path + ".part")
        try fileManager.createDirectory(
            at: destination.appending(path: (file.path as NSString).deletingLastPathComponent),
            withIntermediateDirectories: true)

        var hasher = SHA256()
        var offset: Int64 = 0

        if fileManager.fileExists(atPath: finalURL.path) {
            // Finished by an earlier attempt: hash what is on disk and trust
            // it only while it still matches — no re-download.
            let hash = try hashFile(at: finalURL)
            if file.sha256 == nil || file.sha256?.lowercased() == hash.lowercased() {
                doneSoFar += file.size
                await reportProgress(done: doneSoFar, total: treeTotal, rate: 0)
                return hash
            }
            try fileManager.removeItem(at: finalURL)
        }
        if fileManager.fileExists(atPath: partURL.path) {
            let size = (try? fileManager.attributesOfItem(atPath: partURL.path)[.size] as? Int64) ?? 0
            if size > 0 {
                hasher = SHA256()
                _ = try hashExisting(part: partURL, into: &hasher)
                offset = size
            } else {
                try fileManager.removeItem(at: partURL)
            }
        }

        var request = URLRequest(url: Self.fileURL(repo: entry.repo, revision: entry.revision, path: file.path))
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
              let http = response as? HTTPURLResponse
        else { throw EngineError.hubUnreachable(entry.repo) }

        switch (offset > 0, http.statusCode) {
        case (true, 206):
            break                       // resuming, as asked
        case (true, 200):
            // The server ignored the range: nothing to resume from — start over.
            hasher = SHA256()
            offset = 0
        case (false, 200):
            break                       // a fresh download
        default:
            throw EngineError.hubUnreachable(entry.repo)
        }

        let handle = try openPartFile(at: partURL, offset: offset)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(Self.chunkBytes)
        var written: Int64 = offset
        var lastReport = ContinuousClock.now
        var rateCounter = RateCounter(startBytes: offset, startTime: .now)

        func flush() throws {
            guard !buffer.isEmpty else { return }
            hasher.update(data: buffer)
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            buffer.removeAll(keepingCapacity: true)
        }

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= Self.chunkBytes {
                try Task.checkCancellation()
                try flush()
                let now = ContinuousClock.now
                if now - lastReport >= .milliseconds(100) {
                    lastReport = now
                    await reportProgress(done: doneSoFar + written, total: treeTotal,
                                         rate: rateCounter.rate(now: now, bytes: written))
                }
            }
        }
        try flush()

        let hash = hasher.finalize().hex
        if let expected = file.sha256, expected.lowercased() != hash.lowercased() {
            try? fileManager.removeItem(at: partURL)
            throw EngineError.checksumMismatch((file.path as NSString).lastPathComponent)
        }
        // The rename is atomic on this volume: a file is either the `.part`
        // still coming in, or the complete final file — never half of one.
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: partURL, to: finalURL)
        doneSoFar += written
        await reportProgress(done: doneSoFar, total: treeTotal,
                             rate: rateCounter.rate(now: ContinuousClock.now, bytes: written))
        return hash
    }

    // MARK: - Files

    private func openPartFile(at url: URL, offset: Int64) throws -> FileHandle {
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: UInt64(offset))
        return handle
    }

    /// Hash a file already complete on disk, in chunks.
    private func hashFile(at url: URL) throws -> String {
        var hasher = SHA256()
        _ = try hashExisting(part: url, into: &hasher)
        return hasher.finalize().hex
    }

    /// Feed an existing file's bytes into the hasher; returns how many bytes.
    private func hashExisting(part url: URL, into hasher: inout SHA256) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var total: Int64 = 0
        while let chunk = try handle.read(upToCount: Self.chunkBytes), !chunk.isEmpty {
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        return total
    }

    /// One progress hop to the main actor; the total only ever grows.
    private func reportProgress(done: Int64, total: Int64, rate: Double) async {
        if total > treeTotal { treeTotal = total }
        await progress(done, total, rate)
    }

    // MARK: - Verify + marker

    /// The post-download check beyond the per-file comparisons that already
    /// ran as files landed: a curated row's pinned checksum (the catalog's
    /// record of its primary weights file) against that file's hash.
    func verify(hashes: [String: String], files: FileList) throws {
        guard entry.hasPinnedChecksum else { return }
        guard let largest = files.files.max(by: { $0.size < $1.size }),
              let hash = hashes[largest.path],
              hash.lowercased() == entry.sha256.lowercased()
        else { throw EngineError.checksumMismatch("the catalog's pinned checksum") }
    }

    /// The install marker: written only after every file verified. A folder
    /// without it is a download that never finished. One schema with the
    /// scanner (`InstalledModels` reads `InstallRecord`).
    func writeMarker() throws {
        let record = InstallRecord(id: entry.id, repo: entry.repo, revision: entry.revision,
                                   parser: entry.parser.rawValue, installedAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(
            to: destination.appending(path: InstalledModels.markerName), options: .atomic)
    }

    // MARK: - URLs

    static func treeURL(repo: String, revision: String) -> URL? {
        let repoPath = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let revisionPath = revision.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? revision
        return URL(string: "https://huggingface.co/api/models/\(repoPath)/tree/\(revisionPath)?recursive=true")
    }

    static func fileURL(repo: String, revision: String, path: String) -> URL {
        let repoPath = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let revisionPath = revision.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? revision
        let filePath = path.split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repoPath)/resolve/\(revisionPath)/\(filePath)")
            ?? URL(string: "https://huggingface.co/")!
    }
}

private extension SHA256.Digest {
    /// The digest as the lowercase hex string checksums are compared in.
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

/// A download rate over a rolling window, so the row's number settles
/// instead of jumping with every chunk.
private struct RateCounter {
    private var samples: [(at: ContinuousClock.Instant, bytes: Int64)] = []
    private let window = Duration.seconds(5)

    init(startBytes: Int64, startTime: ContinuousClock.Instant) {
        samples = [(startTime, startBytes)]
    }

    mutating func rate(now: ContinuousClock.Instant, bytes: Int64) -> Double {
        samples.append((now, bytes))
        while samples.count > 2, samples[0].at < now - window {
            samples.removeFirst()
        }
        guard let first = samples.first, now > first.at else { return 0 }
        let elapsed = now - first.at
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        return seconds > 0 ? Double(bytes - first.bytes) / seconds : 0
    }
}
