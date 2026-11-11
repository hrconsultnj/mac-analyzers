import Foundation

/// Why a Stop that was asked for did not happen, as a short CODE. A link that opens Monitor on a
/// process carries a code, never a sentence: a link can be made by any app or web page, and a
/// sentence chosen by whoever made it would be a message in the app's own voice. The app builds the
/// sentence; a code it does not know shows nothing.
public enum StopWhy: Hashable, Sendable, Codable {
    /// The process is not the one that was reported (its start time differs).
    case changed
    /// Nothing to check the process against, so it was not trusted.
    case unverifiable
    /// The list of coding agents is unavailable, so no tool is stopped.
    case unavailable
    /// The process is part of a live session of this agent.
    case session(String)
    /// The process hosts live sessions of this agent.
    case hosts(String)
    /// Refused for another reason.
    case refused

    /// "changed", "session.Claude%20Code", … The part after a dot is percent-encoded.
    public var code: String {
        switch self {
        case .changed: "changed"
        case .unverifiable: "unverifiable"
        case .unavailable: "unavailable"
        case .refused: "refused"
        case .session(let agent): "session." + Self.encode(agent)
        case .hosts(let agent): "hosts." + Self.encode(agent)
        }
    }

    /// nil for anything that is not exactly one of the codes, or that names an agent the list does not.
    public init?(code: String) {
        let parts = code.split(separator: ".", maxSplits: 1).map(String.init)
        switch parts.first {
        case "changed" where parts.count == 1: self = .changed
        case "unverifiable" where parts.count == 1: self = .unverifiable
        case "unavailable" where parts.count == 1: self = .unavailable
        case "refused" where parts.count == 1: self = .refused
        case "session" where parts.count == 2:
            guard let agent = Self.decode(parts[1]) else { return nil }
            self = .session(agent)
        case "hosts" where parts.count == 2:
            guard let agent = Self.decode(parts[1]) else { return nil }
            self = .hosts(agent)
        default: return nil
        }
    }

    // carried as its code, so a stored link can only ever hold a code the app understands
    public init(from decoder: Decoder) throws {
        let code = try decoder.singleValueContainer().decode(String.self)
        guard let known = StopWhy(code: code) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown reason \(code)"))
        }
        self = known
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }

    public var sentence: String {
        switch self {
        case .changed: "That process has changed since the notification: it is not the one that was reported, so it was not stopped."
        case .unverifiable: "Mac Analyzers cannot be sure this is still the process the notification was about, so it did not stop it."
        case .unavailable: CodingAgentHosts.unavailableSentence
        case .session(let agent): "This process is part of a live \(agent) session. Close the session there instead."
        case .hosts(let agent): "This process hosts live \(agent) sessions. Close them there instead."
        case .refused: "Mac Analyzers did not stop this process. Look at it here first."
        }
    }

    /// The deep link that opens Monitor on a process and explains why.
    public func target(pid: Int) -> String { "monitor:pid:\(pid):why:\(code)" }

    /// Why a process was refused, worked out from the process table now.
    public static func after(refusedPID pid: Int) -> StopWhy {
        if !CodingAgentHosts.isAvailable { return .unavailable }
        if let agent = CodingAgentHosts.liveSessionAgent(pid: pid) { return .session(agent) }
        if let agent = CodingAgentHosts.sessionsBelow(pid: pid).keys.sorted().first { return .hosts(agent) }
        return .refused
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }

    private static func decode(_ text: String) -> String? {
        guard let agent = text.removingPercentEncoding, CodingAgentHosts.agentNames.contains(agent) else { return nil }
        return agent
    }
}
