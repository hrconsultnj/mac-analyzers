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

/// The tabs of Downloads: kinds of file, merged to at most six.
public enum DownloadCategory: String, StorageCategory {
    case documents, images, screenshots, archivesAndInstallers, media, foldersAndOther

    public var title: String {
        switch self {
        case .documents: Names.StorageTab.documents
        case .images: Names.StorageTab.images
        case .screenshots: Names.StorageTab.screenshots
        case .archivesAndInstallers: Names.StorageTab.archivesAndInstallers
        case .media: Names.StorageTab.media
        case .foldersAndOther: Names.StorageTab.foldersAndOther
        }
    }

    public var symbol: String {
        switch self {
        case .documents: "doc.text"
        case .images: "photo"
        case .screenshots: "camera.viewfinder"
        case .archivesAndInstallers: "archivebox"
        case .media: "play.rectangle"
        case .foldersAndOther: "folder"
        }
    }

    init(_ kind: DownloadKind) {
        switch kind {
        case .documents: self = .documents
        case .images: self = .images
        case .screenshots: self = .screenshots
        case .archives, .installers: self = .archivesAndInstallers
        case .video, .audio: self = .media
        case .folders, .other: self = .foldersAndOther
        }
    }
}

/// What a cleanup of Downloads and Screenshots would do (or did), as the rows Storage
/// screens share: one tab per kind of file, rows grouped by how long they have sat there.
public struct DownloadReview: Sendable {
    public let rows: StorageRows
    /// Items the engine kept because of a keep pattern.
    public var keptByPattern: Int { rows.rows.filter { $0.keptReason == Names.Kept.keepList }.count }

    /// Builds the rows from a whole run. `info` reads a path's date and whether it is a folder;
    /// injected so a probe needs no real files. With `results` the rows are what an apply did
    /// (moved, couldn't move), grouped by the folder they came from since the items are gone.
    public static func build(lines: [String], results: Bool = false, now: Date = Date(),
                             info: (String) -> (modified: Date?, isFolder: Bool) = { StorageFileInfo.read($0) })
        -> DownloadReview {
        var source: DownloadSource = .downloads
        var limit: Int?
        var found: [StorageRow] = []
        for line in lines {
            if line.hasPrefix("### ") {
                source = line.contains("Screenshots") ? .screenshots : .downloads
                limit = line.range(of: #"\d+\+ days"#, options: .regularExpression)
                    .flatMap { Int(line[$0].split(separator: "+")[0]) }
                continue
            }
            let isKept = line.hasPrefix("[SKIP] kept by pattern")
            let tag: String
            var rest: String
            if isKept {
                tag = "SKIP"
                rest = String(line.dropFirst("[SKIP] kept by pattern".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("[DRY]") {
                tag = "DRY"; rest = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("[CLOUD]") {
                tag = "CLOUD"; rest = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if results, line.hasPrefix("[TRASHED]") {
                tag = "TRASHED"; rest = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            } else if results, line.hasPrefix("[FAILED]") {
                tag = "FAILED"; rest = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else { continue }

            var bytes: Int64?
            if !isKept {
                guard let range = rest.range(of: #"^~?[\d.]+ [KMGT]?B\s+"#, options: .regularExpression),
                      let size = ByteSize.parse(String(rest[range]).trimmingCharacters(in: .whitespaces)) else { continue }
                bytes = size
                rest = String(rest[range.upperBound...])
            }
            // a receipt carries where the item went: "path  ->  Trash path"
            var path = rest
            if let arrow = rest.range(of: "  ->  ") { path = String(rest[..<arrow.lowerBound]) }
            let facts = results ? (modified: nil as Date?, isFolder: false) : info(path)
            let kind = DownloadKind.of(path: path, isFolder: facts.isFolder, source: source)
            let days = facts.modified.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
            if tag == "CLOUD" {
                // kept in iCloud only: `du` says 0, the real size is shown, it frees nothing here, and
                // ticking it would remove the iCloud copy, so it is shown and not offered
                found.append(StorageRow(id: path, category: DownloadCategory(kind).rawValue, group: Names.Download.onlyInICloud,
                                        title: (path as NSString).lastPathComponent,
                                        detail: [DownloadReview.whyText(days: days, limit: limit, folder: false), source.title].joined(separator: " · "),
                                        bytes: nil, valueText: bytes.map(ByteSize.format), iconPath: path,
                                        keptReason: Names.Kept.onlyInICloud))
                continue
            }
            let group = results || isKept ? source.title : DownloadAge(days: days).title
            let why = whyText(days: days, limit: limit, folder: facts.isFolder)
            let outcome: String? = switch tag {
            case "TRASHED": "Moved to Trash"
            case "FAILED": "Couldn't Move"
            default: nil
            }
            let detail = [outcome, isKept ? nil : (results ? nil : why), source.title].compactMap { $0 }.joined(separator: " · ")
            found.append(StorageRow(id: path, category: DownloadCategory(kind).rawValue, group: group,
                                    title: (path as NSString).lastPathComponent, detail: detail, bytes: bytes,
                                    iconPath: results ? nil : path,
                                    keptReason: isKept ? Names.Kept.keepList : nil))
        }
        return DownloadReview(rows: StorageRows(found))
    }

    /// Why it qualifies, as a sentence.
    static func whyText(days: Int?, limit: Int?, folder: Bool) -> String {
        let unit = folder ? "Folder not changed" : "Not changed"
        guard let days else { return limit.map { "\(unit) in over \($0) days" } ?? "\(unit) for a long time" }
        let span = days >= 365 ? "\(days / 365) year\(days / 365 == 1 ? "" : "s")" : "\(days) days"
        return "\(unit) for \(span)"
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
