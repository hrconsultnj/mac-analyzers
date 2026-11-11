import Foundation

/// What a file in Downloads or Screenshots is.
public enum DownloadKind: String, CaseIterable, Identifiable, Sendable {
    case documents, images, archives, installers, video, audio, folders, screenshots, other
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .documents: Names.Download.documents
        case .images: Names.Download.images
        case .archives: Names.Download.archives
        case .installers: Names.Download.installers
        case .video: Names.Download.video
        case .audio: Names.Download.audio
        case .folders: Names.Download.folders
        case .screenshots: Names.Download.screenshots
        case .other: Names.Download.other
        }
    }

    /// From the extension, or from the folder it came from.
    static func of(path: String, isFolder: Bool, source: DownloadSource) -> DownloadKind {
        if source == .screenshots { return .screenshots }
        if isFolder { return .folders }
        switch (path as NSString).pathExtension.lowercased() {
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "md", "csv", "xls", "xlsx", "numbers",
             "ppt", "pptx", "key", "eml", "epub", "odt", "ods": return .documents
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "tif", "tiff", "psd", "bmp", "avif": return .images
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "rar", "7z": return .archives
        case "dmg", "pkg", "iso", "mpkg": return .installers
        case "mp4", "mov", "mkv", "avi", "m4v", "webm": return .video
        case "mp3", "wav", "m4a", "aac", "flac", "aiff", "ogg": return .audio
        default: return .other
        }
    }
}

/// Where in the user's folders a candidate sits.
public enum DownloadSource: String, Sendable {
    case downloads, screenshots

    public var title: String { self == .downloads ? Names.Screen.downloads : Names.Download.screenshots }
}

/// How long a file has sat untouched, in bands people sort by.
public enum DownloadAge: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case underThreeMonths, threeToSixMonths, sixToTwelveMonths, overAYear, unknown
    public var id: Int { rawValue }

    public static func < (lhs: DownloadAge, rhs: DownloadAge) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(days: Int?) {
        guard let days else { self = .unknown; return }
        switch days {
        case ..<90: self = .underThreeMonths
        case ..<180: self = .threeToSixMonths
        case ..<365: self = .sixToTwelveMonths
        default: self = .overAYear
        }
    }

    public var title: String {
        switch self {
        case .underThreeMonths: Names.Download.underThreeMonths
        case .threeToSixMonths: Names.Download.threeToSixMonths
        case .sixToTwelveMonths: Names.Download.sixToTwelveMonths
        case .overAYear: Names.Download.overAYear
        case .unknown: Names.Download.dateUnknown
        }
    }
}

/// One file or folder the janitor would move to the Trash.
public struct DownloadCandidate: Identifiable, Hashable, Sendable {
    public let path: String
    public let source: DownloadSource
    public let kind: DownloadKind
    public let sizeBytes: Int64
    public let lastUsed: Date?
    /// The engine's limit in days for this folder, from its own heading.
    public let limitDays: Int?
    public let isFolder: Bool

    /// The engine's key for the item — what `--only-paths` is given.
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }

    public func daysUntouched(now: Date = Date()) -> Int? {
        lastUsed.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
    }

    public func age(now: Date = Date()) -> DownloadAge { DownloadAge(days: daysUntouched(now: now)) }

    /// Why it qualifies, as a sentence.
    public func why(now: Date = Date()) -> String {
        let unit = isFolder ? "Folder not changed" : "Not changed"
        guard let days = daysUntouched(now: now) else {
            return limitDays.map { "\(unit) in over \($0) days." } ?? "\(unit) for a long time."
        }
        let span = days >= 365 ? "\(days / 365) year\(days / 365 == 1 ? "" : "s")" : "\(days) days"
        let limit = limitDays.map { " Your limit is \($0) days." } ?? ""
        return "\(unit) for \(span).\(limit)"
    }
}

/// What a cleanup of Downloads and Screenshots would do.
public struct DownloadReview: Sendable {
    public let candidates: [DownloadCandidate]
    /// Items the engine kept because of a keep pattern.
    public let keptByPattern: Int

    public var totalBytes: Int64 { candidates.reduce(0) { $0 + $1.sizeBytes } }

    /// Builds the review from a whole run. `info` reads a path's date and
    /// whether it is a folder; injected so a probe needs no real files.
    public static func build(lines: [String],
                             info: (String) -> (modified: Date?, isFolder: Bool) = { StorageFileInfo.read($0) })
        -> DownloadReview {
        var source: DownloadSource = .downloads
        var limit: Int?
        var found: [DownloadCandidate] = []
        var kept = 0
        for line in lines {
            if line.hasPrefix("### ") {
                source = line.contains("Screenshots") ? .screenshots : .downloads
                limit = line.range(of: #"\d+\+ days"#, options: .regularExpression)
                    .flatMap { Int(line[$0].split(separator: "+")[0]) }
                continue
            }
            if line.hasPrefix("[SKIP] kept by pattern") { kept += 1; continue }
            guard line.hasPrefix("[DRY]") else { continue }
            let rest = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let range = rest.range(of: #"^~?[\d.]+ [KMGT]?B\s+"#, options: .regularExpression),
                  let bytes = ByteSize.parse(String(rest[range]).trimmingCharacters(in: .whitespaces))
            else { continue }
            let path = String(rest[range.upperBound...])
            let facts = info(path)
            found.append(DownloadCandidate(
                path: path, source: source,
                kind: DownloadKind.of(path: path, isFolder: facts.isFolder, source: source),
                sizeBytes: bytes, lastUsed: facts.modified, limitDays: limit, isFolder: facts.isFolder))
        }
        return DownloadReview(candidates: found, keptByPattern: kept)
    }
}

/// File facts, in one place so a probe can stand in for the disk.
public enum StorageFileInfo {
    public static func read(_ path: String) -> (modified: Date?, isFolder: Bool) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.modificationDate] as? Date,
                (attributes?[.type] as? FileAttributeType) == .typeDirectory)
    }
}
