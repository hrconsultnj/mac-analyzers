import Foundation
import Observation
import AnalyzersKit

/// One finished turn of a conversation, exactly as the session screen showed
/// it: the question, the steps with the scripts they named, the answer, and
/// how it ended. Codable so a conversation survives a relaunch.
public struct AskTurn: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var prompt: String
    public var steps: [AskStepRecord]
    public var reply: String
    public var thinking: String
    public var failure: String?
    public var stopped: Bool
    /// Set when the turn ended in an approval (the receipt's own words).
    public var receiptHeadline: String?
    /// The engine (and model, when loaded) that answered this turn — the reply
    /// is labelled with it, never a bare product name.
    public var engine: String?

    public init(id: UUID = UUID(), prompt: String, steps: [AskStepRecord] = [],
                reply: String = "", thinking: String = "",
                failure: String? = nil, stopped: Bool = false, receiptHeadline: String? = nil,
                engine: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.steps = steps
        self.reply = reply
        self.thinking = thinking
        self.failure = failure
        self.stopped = stopped
        self.receiptHeadline = receiptHeadline
        self.engine = engine
    }
}

/// One step of a turn, persisted with the turn.
public struct AskStepRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var detail: String
    public var finished: Bool

    public init(id: UUID = UUID(), name: String, detail: String, finished: Bool) {
        self.id = id
        self.name = name
        self.detail = detail
        self.finished = finished
    }
}

/// One saved conversation: every turn, oldest first, plus when it started and
/// the title the list shows (the first question's first line).
public struct AskConversation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var started: Date
    public var turns: [AskTurn]

    public var title: String {
        let first = turns.first?.prompt ?? ""
        let line = first.split(separator: "\n").first.map(String.init) ?? first
        return line.isEmpty ? "Conversation" : String(line.prefix(80))
    }

    public init(id: UUID = UUID(), started: Date = Date(), turns: [AskTurn] = []) {
        self.id = id
        self.started = started
        self.turns = turns
    }
}

/// The conversations this Mac has had, one JSON file each under the data
/// root's `ask/history`. Loaded once, kept newest first; a session saves on
/// every turn's end, so a quit mid-chat costs at most the open turn.
@MainActor @Observable
public final class AskHistoryStore {

    public static let shared = AskHistoryStore()

    public private(set) var conversations: [AskConversation] = []
    private var loaded = false

    static var directory: URL { AnalyzersPaths.userRoot.appending(path: "ask/history") }

    private init() {}

    public func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let fm = FileManager.default
        let dir = Self.directory
        guard let files = try? fm.contentsOfDirectory(
            at: Self.makeDirectory(dir), includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        conversations = files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? decoder.decode(AskConversation.self, from: data)
        }
        conversations.sort { $0.started > $1.started }
    }

    /// Saves (or replaces) one conversation and keeps the list ordered.
    public func save(_ conversation: AskConversation) {
        let dir = Self.makeDirectory(Self.directory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(conversation) {
            try? data.write(to: dir.appending(path: conversation.id.uuidString + ".json"),
                            options: .atomic)
        }
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        conversations.sort { $0.started > $1.started }
    }

    /// Deletes one conversation — to the Trash, like everything else here.
    public func delete(_ conversation: AskConversation) {
        let file = Self.directory.appending(path: conversation.id.uuidString + ".json")
        _ = try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
        conversations.removeAll { $0.id == conversation.id }
    }

    /// The folder, created on demand (a first conversation creates it).
    static func makeDirectory(_ dir: URL) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
