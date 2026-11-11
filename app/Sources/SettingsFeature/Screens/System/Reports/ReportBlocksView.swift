import AnalyzersKit
import SwiftUI

/// A report, drawn the way a document reads: headings, paragraphs, lists,
/// tables and code, with text you can select.
struct ReportBlocksView: View {
    let preface: [MarkdownBlock]
    let sections: [ReportSection]
    /// The titles of the sections that are open.
    @Binding var expanded: Set<String>
    /// A section to scroll to (set by the Sections menu, cleared once done).
    @Binding var jumpTo: String?

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: jumpTo) {
                    guard let title = jumpTo else { return }
                    withAnimation { proxy.scrollTo(title, anchor: .top) }
                    jumpTo = nil
                }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(preface.enumerated()), id: \.offset) { _, block in view(for: block) }
                ForEach(sections) { section in
                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(section.id) },
                                                        set: { if $0 { expanded.insert(section.id) } else { expanded.remove(section.id) } })) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in view(for: block) }
                        }
                        .padding(.vertical, 6)
                    } label: {
                        Text(section.title).font(.title3.bold())
                    }
                    .id(section.id)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.styled(text)).font(font(forLevel: level)).padding(.top, level <= 2 ? 6 : 0)
        case .paragraph(let text):
            Text(Self.styled(text))
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline) {
                        Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(Self.styled(item))
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(Self.styled(item))
                    }
                }
            }
        case .table(let header, let rows):
            ReportTableView(header: header, rows: rows)
        case .code(let text):
            // column-aligned output: proportional text or wrapping would scramble it
            GroupBox {
                ScrollView(.horizontal) {
                    Text(text).font(.callout.monospaced())
                }
            }
        case .quote(let text):
            GroupBox { Text(Self.styled(text)).foregroundStyle(.secondary) }
        case .rule:
            Divider()
        }
    }

    private func font(forLevel level: Int) -> Font {
        switch level {
        case 1: .largeTitle.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }

    /// `code`, **bold** and _italic_ inside a block render as such; text that
    /// is not valid Markdown is shown as written.
    static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// A Markdown table as a grid of its first 200 rows (more on request): a bold header row, rules
/// between, numbers aligned to the right. Cells are parsed as they are drawn.
private struct ReportTableView: View {
    let header: [String]
    let rows: [[String]]
    /// Which columns read as numbers, found once when the table is built (not
    /// per cell drawn): a column whose every cell starts with a digit.
    private let numeric: [Bool]

    init(header: [String], rows: [[String]]) {
        self.header = header
        self.rows = rows
        numeric = header.indices.map { column in
            let cells = rows.compactMap { $0.indices.contains(column) ? $0[column] : nil }
            return !cells.isEmpty && cells.allSatisfy {
                let plain = $0.replacingOccurrences(of: "*", with: "")
                return plain.first.map(\.isNumber) ?? false && plain.count < 18
            }
        }
    }

    /// The first rows are drawn at once; a long table adds more on request. (A lazy grid drew only
    /// the header here, in a lazy stack inside a folding section: seen in a render.)
    @State private var shown = 200

    var body: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            Text(ReportBlocksView.styled(header[column])).font(.headline)
                                .gridColumnAlignment(numeric[column] ? .trailing : .leading)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(rows.prefix(shown).indices, id: \.self) { row in
                        GridRow {
                            ForEach(header.indices, id: \.self) { column in
                                Text(ReportBlocksView.styled(rows[row].indices.contains(column) ? rows[row][column] : ""))
                                    .monospacedDigit(numeric[column])
                            }
                        }
                    }
                }
                if rows.count > shown {
                    Button("Show \(min(200, rows.count - shown)) More Rows (\(rows.count - shown) left)") { shown += 200 }
                }
            }
        }
    }
}

private extension Text {
    func monospacedDigit(_ on: Bool) -> Text { on ? monospacedDigit() : self }
}
