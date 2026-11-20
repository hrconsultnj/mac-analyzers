import Foundation
import AnalyzersKit

/// The model catalog the On-Device Models screen reads: the manifest bundled
/// with the app, overlaid — when it can be reached — by a refreshed copy from
/// the suite's repository. Network use follows the update checker's shape: one
/// unauthenticated GET, at most every 24 hours (or when forced), a conditional
/// request carrying the last ETag, the answer cached under the data root. The
/// bundled manifest is always the floor: offline, rate-limited, or a copy the
/// decoder refuses, the catalog still shows the curated models it shipped with.
@MainActor
@Observable
public final class ModelCatalog {

    /// The manifest the screens show: bundled at least, refreshed when a
    /// fetch succeeds.
    public private(set) var manifest: ModelManifest

    /// Whether a refresh is in flight (a small beside-the-header indicator,
    /// not a screen state — the list always shows something).
    public private(set) var isRefreshing = false

    /// How the last forced refresh ended, for a footer line: reached GitHub
    /// and the manifest changed / reached and nothing changed / could not.
    public private(set) var lastRefresh: RefreshOutcome = .notYet

    public enum RefreshOutcome: Equatable {
        case notYet
        case updated
        case unchanged
        case unreachable
    }

    private static let manifestURL = URL(string:
        "https://raw.githubusercontent.com/hrconsultnj/sparehold/main/"
            + "app/Sources/AgentFeature/Resources/model-manifest.json")!
    private static let cooldown: TimeInterval = 24 * 3600
    private static let etagKey = "modelManifestETag"
    private static let lastCheckKey = "modelManifestCheckAt"

    /// The cached copy lives with the app's other records, under the data root
    /// (`Application Support/Sparehold/cache`, or the checkout's root).
    private static var cacheURL: URL {
        AnalyzersPaths.userRoot.appending(path: "cache/model-manifest.json")
    }

    public init() {
        // The bundled copy is the floor — it always exists.
        manifest = ModelManifest.bundled() ?? ModelManifest(version: 1, updated: "", models: [])
        // A cached refresh replaces it when it still decodes; a corrupted or
        // half-written cache is discarded in favour of the bundle.
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cached = try? JSONDecoder().decode(ModelManifest.self, from: data) {
            manifest = cached
        }
    }

    /// The one shared catalog — SpareholdApp injects it; the screen never
    /// builds a second one.
    public static let shared = ModelCatalog()

    // MARK: - Reading

    /// Every model this Mac's tier may be offered, curated order: the list
    /// starts small and grows with memory (16 GB → Qwen3.5-9B; 24 GB →
    /// + GPT-OSS-20B and GLM-4.7-Flash; 32 GB → + Qwen3-Coder-30B).
    public func recommended(for tier: Int) -> [ModelEntry] {
        manifest.models.filter { $0.minRAMGB <= tier }
    }

    public func entry(id: String) -> ModelEntry? {
        manifest.models.first { $0.id == id }
    }

    // MARK: - Refresh

    /// Refresh at most every 24 hours; `force` bypasses the cooldown (the
    /// screen's "Refresh catalog" action). Never throws: any failure keeps
    /// the manifest as it was.
    public func refreshIfDue(force: Bool = false) async {
        let defaults = UserDefaults.standard
        if !force,
           Date().timeIntervalSince1970 - defaults.double(forKey: Self.lastCheckKey) < Self.cooldown {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

        var request = URLRequest(url: Self.manifestURL)
        if let etag = defaults.string(forKey: Self.etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else {
            lastRefresh = .unreachable
            return
        }
        switch http.statusCode {
        case 304:
            lastRefresh = .unchanged
        case 200:
            guard let fresh = try? JSONDecoder().decode(ModelManifest.self, from: data) else {
                lastRefresh = .unreachable   // a body we cannot trust is no answer
                return
            }
            if fresh == manifest {
                lastRefresh = .unchanged
            } else {
                manifest = fresh
                lastRefresh = .updated
            }
            writeCache(data)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                defaults.set(etag, forKey: Self.etagKey)
            }
        default:
            lastRefresh = .unreachable
        }
    }

    /// The cache write is best-effort: losing it costs one re-download, not
    /// correctness — the bundled floor remains.
    private func writeCache(_ data: Data) {
        let url = Self.cacheURL
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Hugging Face search

    /// One Hugging Face search: an unauthenticated GET of the public models
    /// API, fetched only on submit (DEC-03 — no typing-time requests), the
    /// MLX conversions first by downloads. nil when the network fails.
    public func searchHuggingFace(_ query: String) async -> [HFSearchResult]? {
        var parts = URLComponents(string: "https://huggingface.co/api/models")
        let items = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "library", value: "mlx"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "20"),
        ]
        parts?.queryItems = items
        guard let url = parts?.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let results = try? JSONDecoder().decode([HFSearchResult].self, from: data)
        else { return nil }
        return results
    }
}

/// One row of a Hugging Face search: the repo, its popularity, and the
/// license when the API says one. Nothing here is verified — the screen
/// badges every row "community — unvetted". Decoded only (never sent back).
public struct HFSearchResult: Decodable, Identifiable, Equatable, Sendable {
    /// The repo id (`mlx-community/Qwen3-8B-4bit`).
    public let id: String
    public let downloads: Int?
    public let likes: Int?

    public init(id: String, downloads: Int? = nil, likes: Int? = nil) {
        self.id = id
        self.downloads = downloads
        self.likes = likes
    }

    enum CodingKeys: String, CodingKey {
        case id, downloads, likes
        case modelID = "modelId"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The API names the repo `id` on list answers and `modelId` on some
        // detail answers; accept either.
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decode(String.self, forKey: .modelID)
        downloads = try c.decodeIfPresent(Int.self, forKey: .downloads)
        likes = try c.decodeIfPresent(Int.self, forKey: .likes)
    }
}
