import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory lens, top half: where physical memory is, and the totals per kind
/// of owner.
extension MonitorSettingsView {

    // MARK: - where memory is

    /// The system-wide split, in Activity Monitor's own terms: "in use" is
    /// app + wired + compressed. Every bar segment repeats as a labelled row
    /// with its value — the bar is the glance, the rows are the answer.
    @ViewBuilder var breakdownSection: some View {
        if let memory = census?.breakdown {
            Section("Where Your Memory Is") {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text("\(MemorySize.text(memory.usedBytes)) in use")
                            .font(Tokens.Typography.statValue)
                        Text("of \(MemorySize.text(memory.totalBytes))")
                            .foregroundStyle(.secondary)
                    }
                    StackedBar(segments: [
                        .init(id: "app", value: Double(memory.appBytes), color: .blue),
                        .init(id: "wired", value: Double(memory.wiredBytes), color: .indigo),
                        .init(id: "compressed", value: Double(memory.compressedBytes), color: .purple),
                        .init(id: "cached", value: Double(memory.cachedBytes), color: .teal),
                    ], total: Double(memory.totalBytes))
                }
                .padding(.vertical, Tokens.Space.xxs)

                legendRow(.blue, "App Memory", memory.appBytes,
                          "Held right now by the apps and processes listed below.")
                legendRow(.indigo, "Wired Memory", memory.wiredBytes,
                          "macOS itself — the kernel, drivers and graphics. Can't be moved or squeezed.")
                legendRow(.purple, "Compressed", memory.compressedBytes,
                          "Idle memory macOS squeezed to make room — \(MemorySize.text(memory.compressedOriginalBytes)) of it packed into this.")
                legendRow(.teal, "Cached Files", memory.cachedBytes,
                          "Recently used files kept for speed. Not counted as in use — handed back the moment an app needs the room.")
                legendRow(nil, "Free", memory.freeBytes, "Untouched.")
            }
        }
    }

    func legendRow(_ color: Color?, _ title: String, _ bytes: Int64,
                           _ explanation: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
            Circle()
                .fill(color.map { AnyShapeStyle($0) } ?? Tokens.Surface.track)
                .frame(width: Tokens.Icon.dot, height: Tokens.Icon.dot)
                .accessibilityHidden(true)  // decorative — the title names the row
            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                Text(title).font(Tokens.Typography.rowTitleKey)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Tokens.Space.s)
            Text(MemorySize.text(bytes))
                .font(Tokens.Typography.value)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - who is holding it

    /// Totals for the whole table, then one chip per kind of owner — each
    /// chip carries its own total and process count, so the split is readable
    /// before a single row is opened.
    @ViewBuilder var ledgerSection: some View {
        if let census {
            Section("Who Is Holding It") {
                Text("\(census.processCount.formatted()) processes are running, holding \(MemorySize.text(census.totalBytes)) between them.")
                FilterChipsBar(
                    chips: [.init(CensusGroup.Category?.none,
                                  "Everything · \(MemorySize.text(census.totalBytes))",
                                  count: census.processCount,
                                  color: Tokens.Status.neutral.tint)]
                        + CensusGroup.Category.allCases.map { category in
                            .init(CensusGroup.Category?.some(category),
                                  "\(category.title) · \(MemorySize.text(census.totalBytes(in: category)))",
                                  count: census.processCount(in: category),
                                  color: Tokens.Status.neutral.tint)
                        },
                    selection: $scope
                )
                Text("A group's total counts compressed memory at its full size, so the groups add up to roughly App Memory plus what is packed inside Compressed."
                     + (census.unmeasuredCount > 0
                        ? " \(census.unmeasuredCount) processes could not be measured and count as zero."
                        : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
