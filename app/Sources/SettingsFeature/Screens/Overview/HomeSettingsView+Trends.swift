import SwiftUI
import AnalyzersKit
import UIComponents

/// The trends teaser.
extension HomeSettingsView {

    // MARK: - trends teaser

    @ViewBuilder var trendsSection: some View {
        if let trends {
            Section {
                Button {
                    openPane("trends")
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trends.headline)
                                .font(.callout.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Open Trends for the full story.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true) // decorative disclosure arrow — the row's own text says where it goes
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack {
                    Text("Share a one-page health report")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Export…") { HealthReport.save() }
                }
            } header: {
                Text("This week")
            }
        }
    }
}
