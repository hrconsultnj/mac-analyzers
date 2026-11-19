import SwiftUI
import AnalyzersKit
import AgentFeature

/// Settings → Agents → On-Device Models: the curated model catalog with fit
/// badges, downloads, the installed list, and the opt-in Hugging Face search.
///
/// PHASE 1 SCAFFOLD: the catalog service, downloader and model cards are
/// Phase 2 (lane A), which replaces this screen's body wholesale. The banner
/// below reads the real assessment so the screen is honest about this Mac
/// from the first build.
struct OnDeviceModelsScreen: View {
    @State private var assessment = MachineAssessment.assess()

    var body: some View {
        PaneScaffold(symbol: "internaldrive.fill", color: .mint, title: Names.Screen.onDeviceModels,
                     caption: "Local models that run entirely on this Mac.") {
            Section {
                Text("This Mac: \(assessment.physicalMemoryGB) GB memory · \(assessment.freeDiskGB) GB free.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The tested-model list and downloads arrive with the models update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Recommended models")
            }
        }
    }
}
