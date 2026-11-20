import Foundation

/// One tool call the model emitted in its output text.
///
/// `argumentsJSON` is the arguments object serialized as a JSON object string
/// (never an array or scalar), ready for `AgentTools` to decode. A parser
/// that finds the family's shape but cannot decode the payload returns nil —
/// the caller then shows the raw text instead of guessing an action.
public struct ParsedToolCall: Equatable, Sendable {
    /// The tool's name, e.g. `scanStorage` or the model's spelling of it.
    public let name: String
    /// The arguments object as a JSON string.
    public let argumentsJSON: String

    public init(name: String, argumentsJSON: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// Which tool-call spelling a model family uses. The manifest carries this
/// per model (`parser` field); until the catalog lands, `forModelID` reads it
/// from the model id itself and defaults to the Qwen spelling, which is the
/// most common in the curated MLX list.
public enum ToolCallFamily: String, Sendable, CaseIterable {
    case qwen
    case gptOss = "gpt-oss"
    case glm

    /// The family for a model id such as `mlx-community/Qwen3-8B-4bit`
    /// or `gpt-oss-20b`. Unknown ids parse as `qwen` — the plain
    /// `<tool_call>` JSON block is the closest common denominator, and a miss
    /// degrades to raw text, never to a wrong action.
    public static func forModelID(_ modelID: String) -> ToolCallFamily {
        let lowered = modelID.lowercased()
        if lowered.contains("gpt-oss") { return .gptOss }
        if lowered.contains("glm") || lowered.contains("chatglm") { return .glm }
        return .qwen
    }

    /// The text where a tool call begins, as written in the model's output.
    /// The engine streams the reply but holds back from the first occurrence
    /// of this marker, so tool-call plumbing never reaches the chat as prose.
    var startMarker: String {
        switch self {
        case .qwen, .glm: "<tool_call>"
        case .gptOss: "<|channel|>"
        }
    }
}

/// Turns a model's raw output into a tool call, one parser per family.
///
/// The survey behind this feature named tool-call parsing as the most common
/// silent failure of on-device agents: a mismatched parser turns the model's
/// action into garbage text or, worse, invents one. So the contract here is
/// deliberately narrow — `parse(_:)` returns nil on anything that does not
/// exactly match the family's documented shape, and the caller passes the raw
/// text through instead of acting. A missed tool call costs one clarifying
/// reply; a hallucinated one could touch files.
public struct ToolCallParser: Sendable {

    public let family: ToolCallFamily

    public init(family: ToolCallFamily) {
        self.family = family
    }

    /// The first tool call in `text`, or nil. Nil is never an error worth
    /// surfacing: plain prose (no tool call) also parses to nil, and the raw
    /// text flows on to the user either way.
    public func parse(_ text: String) -> ParsedToolCall? {
        switch family {
        case .qwen: parseQwen(text)
        case .gptOss: parseGptOss(text)
        case .glm: parseGLM(text)
        }
    }

    // MARK: - Qwen

    /// Qwen2.5/Qwen3 chat-template tool calls. The template wraps every call
    /// in literal tags with the arguments as a JSON object (the template
    /// writes the JSON on its own lines, so whitespace around it is normal):
    ///
    ///     <tool_call>
    ///     {"name": "scanStorage", "arguments": {"depth": "brief"}}
    ///     </tool_call>
    ///
    /// Some releases spell the key `parameters` instead of `arguments`; both
    /// are accepted. A call whose payload is not a JSON object with a string
    /// `name` is a miss (nil), not a guess.
    func parseQwen(_ text: String) -> ParsedToolCall? {
        guard let open = text.range(of: "<tool_call>") else { return nil }
        guard let close = text.range(of: "</tool_call>", range: open.upperBound..<text.endIndex) else {
            return nil
        }
        let payload = String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return decodeNameAndArguments(payload)
    }

    // MARK: - gpt-oss (harmony format)

    /// gpt-oss speaks the harmony channel format. A tool call is a commentary
    /// channel message addressed to a function, its arguments after the
    /// `<|message|>` token:
    ///
    ///     <|channel|>commentary to=functions.scanStorage
    ///     <|constrain|>json<|message|>{"depth":"brief"}<|end|>
    ///
    /// (often preceded by `<|start|>assistant`, and closed by `<|return|>` on
    /// the final turn). The name arrives as `to=functions.<name>`; the
    /// `functions.` prefix is the recipient namespace, not part of the tool
    /// name. Special tokens reach us as text because the engine decodes them
    /// itself. Multiple calls may follow one another; the first is returned.
    func parseGptOss(_ text: String) -> ParsedToolCall? {
        // `to=` without the functions prefix is a channel address too (e.g.
        // `to=assistant`), so the name group is anchored to the namespace.
        let pattern = #"to=functions\.([A-Za-z0-9_.-]+)[^<]*<\|message\|>(.*?)(?:<\|end\|>|<\|return\|>|<\|call\|>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(match.range(at: 1), in: text),
              let argumentsRange = Range(match.range(at: 2), in: text)
        else { return nil }
        let name = String(text[nameRange])
        let payload = String(text[argumentsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        // harmony payloads are the arguments object itself — no name field.
        guard let object = jsonObject(payload) else { return nil }
        return ParsedToolCall(name: name, argumentsJSON: serialize(.object(object)))
    }

    // MARK: - GLM

    /// GLM-4.x tool calls are a tagged block: the tool name on the first line
    /// inside `<tool_call>`, then each argument as an arg_key/arg_value pair.
    /// A value that is itself JSON keeps its structure; anything else is a
    /// string:
    ///
    ///     <tool_call>readReport
    ///     <arg_key>which</arg_key>
    ///     <arg_value>latest</arg_value>
    ///     <arg_key>options</arg_key>
    ///     <arg_value>{"kind":"storage"}</arg_value>
    ///     </tool_call>
    func parseGLM(_ text: String) -> ParsedToolCall? {
        guard let open = text.range(of: "<tool_call>") else { return nil }
        guard let close = text.range(of: "</tool_call>", range: open.upperBound..<text.endIndex) else {
            return nil
        }
        let body = String(text[open.upperBound..<close.lowerBound])
        var lines = body.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let firstName = lines.first, !firstName.hasPrefix("<arg_key>") else { return nil }
        let name = firstName
        lines.removeFirst()

        var arguments: [String: JSON] = [:]
        var index = 0
        while index + 1 < lines.count {
            let key = unwrapped(lines[index], tag: "arg_key")
            let value = unwrapped(lines[index + 1], tag: "arg_value")
            if let key {
                arguments[key] = value.flatMap { jsonObject($0).map { .object($0) } } ?? .string(value ?? "")
            }
            index += 2
        }
        return ParsedToolCall(name: name, argumentsJSON: serialize(.object(arguments)))
    }

    // MARK: - shared decoding

    /// `{"name": …, "arguments"/"parameters": {…}}` — the Qwen payload shape.
    private func decodeNameAndArguments(_ payload: String) -> ParsedToolCall? {
        guard let object = jsonObject(payload),
              case .string(let name) = object["name"] ?? .null,
              !name.isEmpty
        else { return nil }
        let arguments = object["arguments"] ?? object["parameters"] ?? .object([:])
        guard case .object = arguments else { return nil }
        return ParsedToolCall(name: name, argumentsJSON: serialize(arguments))
    }

    /// A JSON object decoded from `text`, or nil. Arrays and scalars are
    /// rejected: arguments are always an object.
    private func jsonObject(_ text: String) -> [String: JSON]? {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSON.self, from: data),
              case .object(let object) = decoded
        else { return nil }
        return object
    }

    private func serialize(_ value: JSON) -> String {
        guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// `<arg_key>name</arg_key>` → `name`, when the line is exactly that tag.
    private func unwrapped(_ line: String, tag: String) -> String? {
        guard line.hasPrefix("<\(tag)>"), line.hasSuffix("</\(tag)>") else { return nil }
        let inner = line.dropFirst("<\(tag)>".count).dropLast("</\(tag)>".count)
        let value = inner.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

/// A minimal JSON tree for decoding tool-call arguments and ACP wire
/// messages. `JSONSerialization`'s `[String: Any]` is not Sendable and cannot
/// cross the actor boundaries these engines use, so the values travel as this
/// enum instead.
public indirect enum JSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    /// The string this value holds, when it is one.
    public var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// The object's string fields, flattened one level — the shape tool
    /// arguments are read with (a list of named strings).
    public var stringFields: [String: String] {
        guard case .object(let object) = self else { return [:] }
        var fields: [String: String] = [:]
        for (key, value) in object {
            switch value {
            case .string(let text): fields[key] = text
            case .int(let number): fields[key] = String(number)
            case .double(let number): fields[key] = String(number)
            case .bool(let flag): fields[key] = String(flag)
            default: break
            }
        }
        return fields
    }
}

extension JSON: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }
}

extension JSON: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
