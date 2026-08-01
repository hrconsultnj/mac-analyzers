import Foundation
import AnalyzersKit
import SwiftUI

/// The suite's logs — sidebar children of the Logs item.
enum LogKind: String, CaseIterable, Identifiable {
    case guardLog, memoryClean, reclaim, storageClean, loginItems, forensics
    var id: String { rawValue }

    var title: String {
        switch self {
        case .guardLog: "Memory Guard"
        case .memoryClean: "Memory Auto-Clean"
        case .reclaim: "Memory Reclaim"
        case .storageClean: "Storage Auto-Clean"
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
        case .loginItems: AnalyzersPaths.loginItemsAuditLog
        case .forensics: AnalyzersPaths.latestForensics()
        }
    }
}
