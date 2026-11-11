import Foundation

/// The Markdown the analyzers write, split into the blocks a reader draws:
/// headings, paragraphs, lists, tables, code and quotes. The reports use a
/// small, regular subset (no nesting), so a line-by-line reader is enough;
/// inline emphasis inside a block is left to `AttributedString(markdown:)`.
/// Consecutive lines of one paragraph keep their line breaks: the reports use
/// them for "Generated: … / Host: …" style facts, not for wrapping.
public enum MarkdownBlock: Identifiable, Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case table(header: [String], rows: [[String]])
    case code(String)
    case quote(String)
    case rule

    public var id: String {
        switch self {
        case .heading(let level, let text): "h\(level):\(text)"
        case .paragraph(let text): "p:\(text)"
        case .bullets(let items): "ul:\(items.joined(separator: "|"))"
        case .numbered(let items): "ol:\(items.joined(separator: "|"))"
        case .table(let header, let rows): "t:\(header.joined(separator: "|"))#\(rows.count)"
        case .code(let text): "c:\(text)"
        case .quote(let text): "q:\(text)"
        case .rule: "rule"
        }
    }
}

public enum ReportMarkdown {

    public static func blocks(from text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        func isBullet(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- ") || t.hasPrefix("* ")
        }
        func numberedText(_ line: String) -> String? {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let dot = t.firstIndex(of: "."), dot != t.startIndex,
                  t[..<dot].allSatisfy(\.isNumber),
                  t[t.index(after: dot)...].hasPrefix(" ") else { return nil }
            return String(t[t.index(dot, offsetBy: 2)...])
        }
        func isTableRow(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("|") && t.hasSuffix("|") && t.count > 1
        }
        func cells(_ line: String) -> [String] {
            var t = line.trimmingCharacters(in: .whitespaces)
            t.removeFirst()
            t.removeLast()
            return t.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func isDivider(_ line: String) -> Bool {
            isTableRow(line) && cells(line).allSatisfy { $0.allSatisfy { "-: ".contains($0) } && $0.contains("-") }
        }
        func startsBlock(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.isEmpty || t.hasPrefix("#") || t.hasPrefix("```") || t.hasPrefix(">")
                || isBullet(line) || numberedText(line) != nil || isTableRow(line) || t == "---"
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { index += 1; continue }

            if trimmed.hasPrefix("```") {
                index += 1
                var body: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[index])
                    index += 1
                }
                index += 1
                blocks.append(.code(body.joined(separator: "\n")))
            } else if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: min(level, 4), text: text))
                index += 1
            } else if trimmed == "---" {
                blocks.append(.rule)
                index += 1
            } else if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoted.append(lines[index].trimmingCharacters(in: .whitespaces)
                        .dropFirst().trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoted.joined(separator: " ")))
            } else if isTableRow(line) {
                var rows: [String] = []
                while index < lines.count, isTableRow(lines[index]) {
                    rows.append(lines[index])
                    index += 1
                }
                if rows.count >= 2, isDivider(rows[1]) {
                    blocks.append(.table(header: cells(rows[0]),
                                         rows: rows.dropFirst(2).map(cells)))
                } else {
                    blocks.append(.paragraph(rows.joined(separator: "\n")))
                }
            } else if isBullet(line) {
                var items: [String] = []
                while index < lines.count, isBullet(lines[index]) {
                    items.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    index += 1
                }
                blocks.append(.bullets(items))
            } else if numberedText(line) != nil {
                var items: [String] = []
                while index < lines.count, let item = numberedText(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.numbered(items))
            } else {
                var paragraph: [String] = []
                while index < lines.count, !startsBlock(lines[index]) {
                    paragraph.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                if paragraph.isEmpty { index += 1 } else { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            }
        }
        return blocks
    }
}

/// A report cut into its numbered sections ("## 3. Memory Compressor"): the
/// text before the first one, then each section with its own blocks. A long
/// report is read section by section, not as one scroll.
public struct ReportSection: Identifiable, Hashable, Sendable {
    public let title: String
    public let blocks: [MarkdownBlock]
    /// Position in the report: two sections can share a title.
    public let index: Int
    public var id: String { "\(index)|\(title)" }

    public static func split(_ blocks: [MarkdownBlock]) -> (preface: [MarkdownBlock], sections: [ReportSection]) {
        var preface: [MarkdownBlock] = []
        var sections: [ReportSection] = []
        var title: String?
        var current: [MarkdownBlock] = []
        func close() { if let t = title { sections.append(ReportSection(title: t, blocks: current, index: sections.count)) } }
        for block in blocks {
            if case .heading(let level, let text) = block, level == 2 {
                close()
                title = text
                current = []
            } else if title == nil {
                preface.append(block)
            } else {
                current.append(block)
            }
        }
        close()
        return (preface, sections)
    }
}
