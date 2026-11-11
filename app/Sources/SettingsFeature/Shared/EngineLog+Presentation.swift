import Foundation
import AnalyzersKit
import SwiftUI

/// The suite's logs — sidebar children of the Logs item.
typealias LogKind = EngineLog

/// How each engine log looks: title, symbol and tile colour.
extension EngineLog {

    var title: String { Names.log(self) }

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
        case .cleanupApps: "app.badge.checkmark"
        case .cleanupRecordings: "film"
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
        case .cleanupApps: .pink
        case .cleanupRecordings: .gray
        case .forensics: .purple
        }
    }
}
