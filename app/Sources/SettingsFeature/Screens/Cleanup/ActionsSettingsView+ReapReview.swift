import SwiftUI
import AnalyzersKit
import UIComponents

/// Review of the process cleaners (Memory Clean, Reclaim): protected-session
/// note, one selectable card per process, and the status colours and badges.
extension ActionsSettingsView {

    func statusColor(_ status: ReapItem.Status) -> Color {
        switch status {
        case .dry: .blue
        case .killed, .quit: .red
        case .reported: .purple
        case .exempt: .green
        case .gone, .skip: .secondary
        }
    }

    func badge(for status: ReapItem.Status) -> (String, Color)? {
        switch status {
        case .dry: ("WOULD CLOSE", .blue)
        case .killed: ("CLOSED", .red)
        case .quit: ("QUIT", .red)
        case .reported: ("REPORTED", .purple)
        case .exempt: ("PROTECTED", .green)
        case .gone: ("GONE", .gray)
        case .skip: nil
        }
    }
}
