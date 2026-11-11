import SwiftUI

/// Overview's boxes in as many columns as fit (each at least `minimum` wide), left to right and
/// then down, with the boxes of one row all as tall as the tallest of them: a short box next to
/// a tall one is not left with a hole under it. A box fills the height it is offered
/// (`OverviewBox` does), so its group-box background reaches the bottom of the row.
struct OverviewColumns: Layout {
    var minimum: CGFloat = 340
    var spacing: CGFloat = 16

    private func columnCount(_ width: CGFloat) -> Int { max(1, Int((width + spacing) / (minimum + spacing))) }

    private func columnWidth(_ width: CGFloat, _ count: Int) -> CGFloat {
        (width - spacing * CGFloat(count - 1)) / CGFloat(count)
    }

    /// The height of each row: the tallest box in it at the column's width.
    private func rowHeights(width: CGFloat, subviews: Subviews) -> (heights: [CGFloat], columns: Int, columnWidth: CGFloat) {
        let count = columnCount(width)
        let boxWidth = columnWidth(width, count)
        var heights: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: count) {
            let row = subviews[start..<min(start + count, subviews.count)]
            heights.append(row.map { $0.sizeThatFits(ProposedViewSize(width: boxWidth, height: nil)).height }.max() ?? 0)
        }
        return (heights, count, boxWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimum
        let rows = rowHeights(width: width, subviews: subviews).heights
        return CGSize(width: width, height: rows.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (heights, count, boxWidth) = rowHeights(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (rowIndex, height) in heights.enumerated() {
            for column in 0..<count {
                let index = rowIndex * count + column
                guard index < subviews.count else { break }
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (boxWidth + spacing), y: y),
                                      anchor: .topLeading,
                                      proposal: ProposedViewSize(width: boxWidth, height: height))
            }
            y += height + spacing
        }
    }
}
