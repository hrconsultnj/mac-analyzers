import Foundation
import AnalyzersKit
import SwiftUI

/// The suite's logs — sidebar children of the Logs item.
typealias LogKind = EngineLog

/// How each engine log looks: title, symbol and tile colour.
extension EngineLog {

    var title: String {
        switch self {
        case .guardLog: "Memory Guard"
        case .memoryClean: "Memory Auto-Clean"
        case .reclaim: "Memory Reclaim"
        case .storageClean: "Storage Auto-Clean"
        case .janitor: "Downloads Janitor"
        case .tempSpace: "Temp & Agents"
        case .persistence: "Persistence Changes"
        case .loginItems: "Login-Items Audit"
        case .spotlightAudit: "Spotlight Audit"
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
        case .tempSpace: "tray.full"
        case .persistence: "person.badge.key"
        case .loginItems: "person.crop.circle.badge.questionmark"
        case .spotlightAudit: "magnifyingglass"
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
        case .tempSpace: .mint
        case .persistence: .red
        case .loginItems: .brown
        case .spotlightAudit: .yellow
        case .forensics: .purple
        }
    }
}
