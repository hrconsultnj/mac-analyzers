import Foundation
import AnalyzersKit
import SwiftUI

/// The suite's logs — sidebar children of the Logs item.
enum LogKind: String, CaseIterable, Identifiable {
    case guardLog, memoryClean, reclaim, storageClean, janitor, network, persistence, loginItems, forensics
    var id: String { rawValue }

    var title: String {
        switch self {
        case .guardLog: "Memory Guard"
        case .memoryClean: "Memory Auto-Clean"
        case .reclaim: "Memory Reclaim"
        case .storageClean: "Storage Auto-Clean"
        case .janitor: "Downloads Janitor"
        case .network: "Network Snapshots"
        case .persistence: "Persistence Changes"
        case .loginItems: "Login-Items Audit"
        case .forensics: "Forensics"
        }
    }

    var symbol: String {
        switch self {
        case .guardLog: "shield.lefthalf.filled"
        case .memoryClean: "memorychip"
        case .reclaim: "arrow.counterclockwise.circle"
        case .storageClean: "internaldrive"
        case .janitor: "trash"
        case .network: "network"
        case .persistence: "person.badge.key"
        case .loginItems: "person.crop.circle.badge.questionmark"
        case .forensics: "stethoscope"
        }
    }

    var tileColor: Color {
        switch self {
        case .guardLog: .blue
        case .memoryClean: .teal
        case .reclaim: .cyan
        case .storageClean: .indigo
        case .janitor: .orange
        case .network: .purple
        case .persistence: .red
        case .loginItems: .brown
        case .forensics: .purple
        }
    }

    var url: URL? {
        switch self {
        case .guardLog: AnalyzersPaths.guardLog
        case .memoryClean: AnalyzersPaths.memoryAutoCleanLog
        case .reclaim: AnalyzersPaths.reclaimLog
        case .storageClean: AnalyzersPaths.storageAutoCleanLog
        case .janitor: AnalyzersPaths.janitorLog
        case .network: AnalyzersPaths.networkLog
        case .persistence: AnalyzersPaths.persistenceLog
        case .loginItems: AnalyzersPaths.loginItemsAuditLog
        case .forensics: AnalyzersPaths.latestForensics()
        }
    }
}
