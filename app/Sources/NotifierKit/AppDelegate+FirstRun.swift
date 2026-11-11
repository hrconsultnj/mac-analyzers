import AppKit
import AnalyzersKit

/// First run: opening Setup when the Mac is new to the app or broken.
extension AppDelegate {

    /// First run, or a Mac where the background jobs are not installed: open
    /// Setup instead of leaving someone on an Overview that reports nothing.
    func openSetupIfUnconfigured() {
        Task { @MainActor in
            let engine = await Task.detached(priority: .userInitiated) {
                EngineStatus.probe()
            }.value
            // A window that opens itself has to earn it: either this Mac is
            // genuinely new to the app, or something is genuinely broken.
            // An upgrade on a healthy Mac gets nothing.
            let fresh = !UserDefaults.standard.bool(forKey: "setupSeen")
                && !FileManager.default.fileExists(atPath: AnalyzersPaths.configLocal.path)
            UserDefaults.standard.set(true, forKey: "setupSeen")
            guard fresh || !engine.isFullyInstalled else { return }
            SettingsOpener.open(target: "setup")
        }
    }
}
