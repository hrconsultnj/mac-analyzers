import SwiftUI

/// A report's Markdown exactly as written, one level below the reader. The file
/// is read off the main actor and only the first part of a very long one is
/// shown, with a line saying so. (Stands in until the shared raw-output screen
/// is merged; then this file goes.)
/// A text view built for long text does not take a whole report as one `Text`.
private let reportRawLimit = 200_000

struct ReportRawView: View {
    let path: String
    @State private var text = ""
    @State private var truncated = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if truncated {
                    Label("Showing the first \(reportRawLimit.formatted()) characters of this report.",
                          systemImage: "info.circle").foregroundStyle(.secondary)
                }
                Text(text).font(.callout.monospaced()).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Report Source")
        .task {
            let read = await Task.detached(priority: .userInitiated) { () -> (String, Bool) in
                guard let all = try? String(contentsOfFile: path, encoding: .utf8) else {
                    return ("This report could not be read.", false)
                }
                return all.count > reportRawLimit ? (String(all.prefix(reportRawLimit)), true) : (all, false)
            }.value
            text = read.0
            truncated = read.1
        }
    }
}
