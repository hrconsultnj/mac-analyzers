import Foundation
import AnalyzersKit

/// What feeds the panel's proactive card (S5). v1 reads this Mac's own
/// numbers — disk pressure is the one signal worth saying without a report
/// parser: when free space crosses the bar, the card offers a cleanup, the
/// same propose-and-approve flow as everything else. `AskSuggestionCenter`
/// owns the frequency cap and the per-category mute; this only decides
/// whether anything is worth raising.
public enum AskSuggestionFeed {

    /// Free space below either line is worth saying: an absolute floor (an
    /// almost-full disk) or a share of the disk.
    public static let absoluteFloorGB = 10.0
    public static let shareFloor = 0.1

    /// Called when the menu-bar panel opens (main actor — the Center is one).
    /// Reads the volumes once, records at most one suggestion, and stays
    /// quiet when the Center's cap or a mute says so. Cheap on purpose: two
    /// stat calls at most.
    @MainActor
    public static func considerDiskPressure() {
        let assessment = MachineAssessment.assess()
        guard assessment.freeDiskGB > 0 else { return }
        let total = totalDiskGB() ?? 0
        let share = total > 0 ? Double(assessment.freeDiskGB) / total : 1
        guard Double(assessment.freeDiskGB) < absoluteFloorGB || share < shareFloor else { return }
        AskSuggestionCenter.shared.record(AskSuggestion(
            category: .downloads,
            line: "Only \(assessment.freeDiskGB) GB free — a cleanup could make room.",
            bytes: nil))
    }

    /// The data root's volume capacity, in GB (nil when it cannot be read).
    private static func totalDiskGB() -> Double? {
        let values = try? FileManager.default.attributesOfFileSystem(
            forPath: AnalyzersPaths.userRoot.path)
        guard let bytes = values?[.systemSize] as? Int64 else { return nil }
        return Double(bytes) / 1_073_741_824.0
    }
}
