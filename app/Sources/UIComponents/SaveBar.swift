import SwiftUI

/// Save-bar shared by the panes: prominent Save, transient confirmation,
/// and a visible error instead of a silent failure.
public struct SaveBar: View {
    let onSave: () throws -> Void
    @State private var savedAt: Date?
    @State private var errorText: String?

    public init(onSave: @escaping () throws -> Void) {
        self.onSave = onSave
    }

    public var body: some View {
        HStack {
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(2)
            } else if let savedAt {
                Label("Saved \(savedAt.formatted(.dateTime.hour().minute().second()))",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
            Spacer()
            Button("Save") {
                do {
                    try onSave()
                    savedAt = .now
                    errorText = nil
                } catch {
                    errorText = "Could not save: \(error.localizedDescription)"
                }
            }
            .buttonStyle(.glassProminent)      // the one standout action per pane
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: .command)
        }
    }
}
