import Foundation
import AnalyzersKit

/// Which tool-call dialect a model speaks. The manifest's `parser` field keys
/// the per-family tool-call parsers in `Engines/`; a model whose dialect the
/// engine cannot parse is warned about on the On-Device Models screen, never
/// silently installed.
public enum ModelParser: String, Codable, Sendable, CaseIterable {
    case qwen
    case gptOss = "gpt-oss"
    case glm

    /// A readable name for the warning lines and cards.
    public var title: String {
        switch self {
        case .qwen: "Qwen"
        case .gptOss: "GPT-OSS"
        case .glm: "GLM"
        }
    }

    /// The dialect a Hugging Face repo's name suggests, when it says one at
    /// all: community rows come from a search, and the only honest signal is
    /// the repo's own text. nil when the name names no known family — the
    /// screen then says so instead of guessing.
    public static func inferred(fromText text: String) -> ModelParser? {
        let lowered = text.lowercased()
        if lowered.contains("qwen") { return .qwen }
        if lowered.contains("gpt-oss") || lowered.contains("gptoss") { return .gptOss }
        if lowered.contains("glm") || lowered.contains("chatglm") { return .glm }
        return nil
    }
}

/// One model in the catalog: what it is, where it comes from, what it needs,
/// and how much of this Mac it takes. All figures are what the screen shows —
/// the manifest is data, correctable without a code change.
public struct ModelEntry: Codable, Identifiable, Equatable, Sendable {
    /// The catalog id (stable across manifest updates): `AGENT_MODEL` stores it.
    public let id: String
    /// The model family ("Qwen3.5", "GPT-OSS") — groups the cards' copy.
    public let family: String
    public let name: String
    /// Who trained it ("Qwen", "OpenAI", "Z.ai"), or "community" for a row
    /// built from a Hugging Face search.
    public let provider: String
    /// SPDX license of the upstream weights; empty for community rows whose
    /// license the search does not say.
    public let license: String
    /// The Hugging Face repo id (`mlx-community/Qwen3-8B-4bit`).
    public let repo: String
    /// The revision the download pins (`main` or a commit hash).
    public let revision: String
    /// How the weights are stored ("4-bit", "MXFP4").
    public let quantization: String
    /// Total parameter count, as shown ("30.5B MoE · 3.3B active").
    public let parameters: String
    /// The context window the engine opens, in tokens (the catalog caps a
    /// model's native window to what a Mac can actually hold).
    public let contextTokens: Int
    /// Download size, whole GB (rounded to display size — the Download
    /// button states it before the download starts).
    public let downloadGB: Double
    /// Estimated resident memory while running, whole GB — the fit verdict's
    /// input, never a promise.
    public let memoryGB: Double
    /// The smallest memory tier the model is offered on (16 / 24 / 32 GB).
    public let minRAMGB: Int
    public let parser: ModelParser
    /// Pinned checksum of the model's largest weights file (its primary
    /// safetensors shard), verified after download for curated rows. Empty
    /// when the catalog does not pin one — every file is still verified
    /// against Hugging Face's own per-file sha256 (LFS metadata) either way.
    public let sha256: String
    /// One sentence for the card, written for the person choosing.
    public let blurb: String

    /// The largest weights file this row's checksum pins, found at download
    /// time by size. nil while no pin is recorded (`sha256` empty).
    var hasPinnedChecksum: Bool { !sha256.isEmpty }

    /// Whether this row came from the curated manifest rather than a search.
    public var isCurated: Bool { provider != ModelEntry.communityProvider }

    /// The provider mark a community row carries.
    public static let communityProvider = "community"

    /// A row built from a Hugging Face search result: what the search can
    /// honestly say, nothing more — sizes unknown until its file tree is read
    /// at download time, license unknown unless the search said it.
    public init(fromSearch repoID: String, downloads: Int) {
        id = repoID
        family = repoID.split(separator: "/").last.map(String.init) ?? repoID
        name = family
        provider = ModelEntry.communityProvider
        license = ""
        repo = repoID
        revision = "main"
        quantization = ""
        parameters = ""
        contextTokens = 0
        downloadGB = 0
        memoryGB = 0
        minRAMGB = 0
        parser = ModelParser.inferred(fromText: repoID) ?? .qwen
        sha256 = ""
        blurb = "A community conversion from Hugging Face — not tested with Sparehold."
    }

    /// Coding keys with defaults, so a remote manifest may omit a field a
    /// curated row always has (the manifest is data served from a branch).
    enum CodingKeys: String, CodingKey {
        case id, family, name, provider, license, repo, revision
        case quantization, parameters, contextTokens, downloadGB, memoryGB, minRAMGB
        case parser, sha256, blurb
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        family = try c.decodeIfPresent(String.self, forKey: .family) ?? id
        name = try c.decode(String.self, forKey: .name)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        license = try c.decodeIfPresent(String.self, forKey: .license) ?? ""
        repo = try c.decode(String.self, forKey: .repo)
        revision = try c.decodeIfPresent(String.self, forKey: .revision) ?? "main"
        quantization = try c.decodeIfPresent(String.self, forKey: .quantization) ?? ""
        parameters = try c.decodeIfPresent(String.self, forKey: .parameters) ?? ""
        contextTokens = try c.decodeIfPresent(Int.self, forKey: .contextTokens) ?? 0
        downloadGB = try c.decodeIfPresent(Double.self, forKey: .downloadGB) ?? 0
        memoryGB = try c.decodeIfPresent(Double.self, forKey: .memoryGB) ?? 0
        minRAMGB = try c.decodeIfPresent(Int.self, forKey: .minRAMGB) ?? 0
        parser = try c.decodeIfPresent(ModelParser.self, forKey: .parser) ?? .qwen
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256) ?? ""
        blurb = try c.decodeIfPresent(String.self, forKey: .blurb) ?? ""
    }

    /// The memberwise init, used by the search constructor above.
    public init(id: String, family: String, name: String, provider: String, license: String,
                repo: String, revision: String, quantization: String, parameters: String,
                contextTokens: Int, downloadGB: Double, memoryGB: Double, minRAMGB: Int,
                parser: ModelParser, sha256: String, blurb: String) {
        self.id = id
        self.family = family
        self.name = name
        self.provider = provider
        self.license = license
        self.repo = repo
        self.revision = revision
        self.quantization = quantization
        self.parameters = parameters
        self.contextTokens = contextTokens
        self.downloadGB = downloadGB
        self.memoryGB = memoryGB
        self.minRAMGB = minRAMGB
        self.parser = parser
        self.sha256 = sha256
        self.blurb = blurb
    }

    /// How a model card reads this Mac: the same verdict the fit badge shows.
    public func fit(_ assessment: MachineAssessment) -> ModelFit {
        assessment.fit(modelMemoryGB: memoryGB, downloadGB: downloadGB)
    }
}

/// The manifest as a whole: the bundled copy is the floor; the refreshed one
/// replaces it when it decodes cleanly.
public struct ModelManifest: Codable, Equatable, Sendable {
    public var version: Int
    /// When the catalog last changed, ISO-8601 (`2026-11-19`).
    public var updated: String
    public var models: [ModelEntry]
}

extension ModelManifest {
    /// The manifest bundled with the app: always the floor, offline-safe.
    public static func bundled() -> ModelManifest? {
        guard let url = Bundle.module.url(forResource: "model-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(ModelManifest.self, from: data)
    }
}
