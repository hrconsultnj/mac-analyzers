import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The control row: the one line that changes with the phase (idle, previewing,
/// review, applying, done, failed).
extension ActionsSettingsView {

    @ViewBuilder var controlSection: some View {
        Section {
            switch phase {
            case .idle:
                HStack {
                    lastRunText
                    Spacer()
                    Button("See what would be cleaned") {
                        Task { await preview() }
                    }
                    .buttonStyle(.glassProminent)
                }
            case .previewing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking what could be cleaned — nothing is being changed yet…")
                        .foregroundStyle(.secondary)
                }
            case .review:
                HStack {
                    Label(reviewHeadline, systemImage: "eye")
                        .font(.callout.weight(.medium))
                    Spacer()
                    if cleaner.isStorageShaped || cleaner == .tempClean {
                        Picker("", selection: $sortByName) {
                            Text("Size").tag(false)
                            Text("Name").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 110)
                    }
                    Button("Discard") { resetToIdle() }
                    Button(applyButtonTitle) { confirmingApply = true }
                        .buttonStyle(.glassProminent)
                        .disabled(!hasAnythingToApply)
                }
            case .applying:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Applying — receipts are being written to the log…")
                        .foregroundStyle(.secondary)
                }
            case .done(let summary):
                HStack {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("New preview") { resetToIdle() }
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Try again") { resetToIdle() }
                    }
                    if !lastOutput.isEmpty {
                        DisclosureGroup("Details") {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(lastOutput.split(separator: "\n").suffix(25).enumerated()),
                                        id: \.offset) { _, line in
                                    Text(line)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        Button("Copy diagnostics") {
                            let report = """
                            script: \(cleaner.script.path)
                            args: \(modeArgs.joined(separator: " "))
                            message: \(message)

                            \(lastOutput.split(separator: "\n").suffix(40).joined(separator: "\n"))
                            """
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(report, forType: .string)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var lastRunText: some View {
        Group {
            if let url = cleaner.logKind.url,
               let date = AnalyzersPaths.modificationDate(of: url) {
                Text("Last run \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Never run on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
