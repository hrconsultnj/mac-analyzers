import SwiftUI
import UniformTypeIdentifiers

/// A report's text, handed to the system's save panel for Export.
struct ReportFile: FileDocument {
    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText
    static var readableContentTypes: [UTType] { [markdown, .plainText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
