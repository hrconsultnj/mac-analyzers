import Foundation
import AnalyzersKit

/// The System tab's topics.
extension HowItWorksTopic {

    func systemContent(_ f: HowItWorksFacts) -> TopicContent {
        switch self {
        case .loginItems:
            return TopicContent(
                summary: "Everything on this Mac that starts by itself, and what is new.",
                does: [
                    "The audit lists what starts by itself on this Mac: login items, launch agents, launch daemons and helper tools, and the leftovers of apps you removed. Each one says which app it belongs to and how it is doing.",
                    "Sparehold also checks at launch and every 6 hours for something new that installed itself to run at login or boot, and tells you once.",
                ],
                never: ["The audit only reads. Nothing is blocked, and nothing is removed unless you choose it and confirm."],
                written: ["Changes to what starts by itself are written down as they are noticed (see \(Names.HowItWorks.whereWritten))."],
                buttons: [.init(title: "Open \(Names.Screen.loginItems)", target: "loginitems")])

        case .network:
            return TopicContent(
                summary: "Which programs sent and received data, as snapshots you take.",
                does: [
                    "A snapshot reads how much data each program on this Mac has sent and received since it started, so you can see which ones have been using the network. Past snapshots are kept so you can compare.",
                ],
                never: ["Nothing is captured, blocked or changed. Only the totals the system already keeps are read, and only when you take a snapshot."],
                written: ["Snapshots are kept in your records folder (see \(Names.HowItWorks.whereWritten))."],
                buttons: [.init(title: "Open \(Names.Screen.network)", target: "network")])
        default:
            return TopicContent(summary: "")
        }
    }
}
