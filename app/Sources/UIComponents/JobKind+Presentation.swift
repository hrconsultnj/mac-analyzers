import AnalyzersKit
import SwiftUI

/// How a job kind looks wherever it is listed: name, symbol and tint. The
/// kernel knows what a kind runs; only this file knows what it is called.
extension JobKind {

    public var title: String {
        switch self {
        case .memoryClean: "Memory Clean"
        case .reclaim: "Memory Reclaim"
        case .storageClean: "Storage Clean"
        case .janitor: "Downloads Janitor"
        case .tempClean: "Temp & Agents"
        case .tmReclaim: "Time Machine Snapshots"
        case .spotlight: "Spotlight Audit"
        case .loginItems: "Login Items Audit"
        case .unusedApps: "Unused Apps"
        case .recordings: "Old Recordings"
        case .networkSnapshot: "Network Snapshot"
        case .memoryReport: "Memory Report"
        case .storageReport: "Storage Report"
        case .installAgents: "Install Background Agents"
        case .uninstallAgents: "Turn Off Background Agents"
        case .sudoersInstall: "Allow Snapshot Thinning"
        case .eject: "Eject Disk Image"
        }
    }

    public var symbol: String {
        switch self {
        case .memoryClean: "memorychip"
        case .reclaim: "arrow.3.trianglepath"
        case .storageClean: "internaldrive.fill"
        case .janitor: "trash"
        case .tempClean: "tray.full"
        case .tmReclaim: "clock.arrow.circlepath"
        case .spotlight: "magnifyingglass"
        case .loginItems: "person.badge.key"
        case .unusedApps: "app.dashed"
        case .recordings: "waveform"
        case .networkSnapshot: "network"
        case .memoryReport, .storageReport: "doc.text.magnifyingglass"
        case .installAgents, .uninstallAgents: "clock.badge.checkmark"
        case .sudoersInstall: "lock.open"
        case .eject: "eject"
        }
    }

    public var tint: Color {
        switch self {
        case .memoryClean: .blue
        case .reclaim: .teal
        case .storageClean: .indigo
        case .janitor: .orange
        case .tempClean: .mint
        case .tmReclaim: .cyan
        case .spotlight: .yellow
        case .loginItems: .brown
        case .unusedApps: .pink
        case .recordings: .red
        case .networkSnapshot: .purple
        case .memoryReport, .storageReport: .purple
        case .installAgents, .uninstallAgents, .sudoersInstall: .gray
        case .eject: .mint
        }
    }
}

extension JobIntent {
    /// "Preview" / "Apply" / "Run", for a job row's badge.
    public var title: String {
        switch self {
        case .preview: "Preview"
        case .apply: "Apply"
        case .run: "Run"
        }
    }
}
