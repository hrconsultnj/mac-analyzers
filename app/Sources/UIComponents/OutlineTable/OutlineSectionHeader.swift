import AppKit

/// A row drawn as a full-width section header (a day in a history).
public struct OutlineSectionHeader: Equatable {
    public var title: String
    /// "3 runs · 2.1 GB"
    public var summary: String?

    public init(title: String, summary: String? = nil) {
        self.title = title
        self.summary = summary
    }
}

/// The full-width cell of a section header row: the title in the system's
/// emphasized style, the summary in secondary after it.
@MainActor
final class OutlineSectionHeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("outline-section-header")

    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        titleLabel.textColor = .labelColor
        summaryLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        summaryLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [titleLabel, summaryLabel])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // `textField` is deliberately not set: AppKit restyles a cell's textField as a group row's
        // small title, which would leave the summary beside it in another size
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ header: OutlineSectionHeader) {
        titleLabel.stringValue = header.title
        summaryLabel.stringValue = header.summary ?? ""
        summaryLabel.isHidden = header.summary == nil
        OutlineAccessibility.describe(sectionHeader: self, header: header)
    }
}
