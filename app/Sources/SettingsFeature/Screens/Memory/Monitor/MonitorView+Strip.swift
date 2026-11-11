import SwiftUI
import AnalyzersKit
import UIComponents

/// The memory bar above the table: how much is in use, in one glance, with
/// the pressure and heat beside it. The five-line legend that used to push the
/// table below the fold is in the inspector, where nothing is selected.
extension MonitorView {

    @ViewBuilder var strip: some View {
        if let memory = model.breakdown, model.lens == .memory {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(MemorySize.text(memory.usedBytes)) in use")
                        .font(Tokens.Typography.statValue)
                    Text("of \(MemorySize.text(memory.totalBytes))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    pressureLabel
                }
                StackedBar(segments: [
                    .init(id: "app", value: Double(memory.appBytes), color: .blue),
                    .init(id: "wired", value: Double(memory.wiredBytes), color: .indigo),
                    .init(id: "compressed", value: Double(memory.compressedBytes), color: .purple),
                    .init(id: "cached", value: Double(memory.cachedBytes), color: .teal),
                ], total: Double(memory.totalBytes))
                // the same numbers as text — a bar alone reaches no one using VoiceOver
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading) {
                    legend(.blue, "App", memory.appBytes)
                    legend(.indigo, "Wired", memory.wiredBytes)
                    legend(.purple, "Compressed", memory.compressedBytes)
                    legend(.teal, "Cached Files", memory.cachedBytes)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var pressureLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.pressure == .normal ? Color.green : model.pressure == .warning ? Color.orange : Color.red)
                .frame(width: Tokens.Icon.dot, height: Tokens.Icon.dot)   // a status dot: its size is its job
                .accessibilityHidden(true)
            Text("Memory pressure: \(model.pressure.label)")
                .foregroundStyle(model.pressure == .normal ? Color.secondary : Color.primary)
            let thermal = ThermalWatcher.shared
            if thermal.isElevated {
                BadgeCapsule(text: "Throttling", color: .red)
                    .help("macOS is slowing the CPU to cool down")
            } else if thermal.state == .fair {
                BadgeCapsule(text: "Warm", color: .orange)
            }
        }
        .font(.callout)
    }

    private func legend(_ color: Color, _ title: String, _ bytes: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: Tokens.Icon.dotMicro + 1, height: Tokens.Icon.dotMicro + 1)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(.secondary)
            Text(MemorySize.text(bytes)).monospacedDigit()
        }
        .font(.caption)
    }
}
