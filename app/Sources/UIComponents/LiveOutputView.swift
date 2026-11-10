import AnalyzersKit
import SwiftUI

/// A job's output as it is produced: the last 2,000 lines, monospaced,
/// following the newest line until the reader scrolls up.
public struct LiveOutputView: View {
    let job: Job

    public init(job: Job) { self.job = job }

    private struct Row: Identifiable {
        let id: Int      // absolute line number, stable while the ring rolls over
        let text: String
    }

    private var rows: [Row] {
        let first = job.receivedLineCount - job.lines.count
        return job.lines.enumerated().map { Row(id: first + $0.offset, text: $0.element) }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    Text(row.text.isEmpty ? " " : row.text)
                        .font(Tokens.Typography.mono)
                        .foregroundStyle(row.text.hasPrefix("### ") ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(Tokens.Space.m)
        }
        .defaultScrollAnchor(.bottom)
        .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
        .accessibilityLabel("Output of \(job.kind.title)")
    }
}
