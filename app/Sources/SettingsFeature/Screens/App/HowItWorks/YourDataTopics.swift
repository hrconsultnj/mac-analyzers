import Foundation
import AnalyzersKit

/// The Your Data tab's topics: what is kept, where, and what leaves this Mac and when.
extension HowItWorksTopic {

    @MainActor func yourDataContent(_ f: HowItWorksFacts) -> TopicContent {
        let records = AnalyzersPaths.displayPath(AnalyzersPaths.userRoot)
        switch self {
        case .whereWritten:
            var does = ["Every action Memory Guard takes is written in the guard log.\(f.guardLogBytes.map { " The guard log is \(ByteSize.text($0, .headline)) on this Mac." } ?? "")"]
            does.append("Every cleanup writes a full report under \(records)/reports/, a folder for each day. Clicking any notification opens the app or the exact log behind it.")
            does.append("The Clear button in the menu-bar panel only resets what the panel shows. The logs are never trimmed by the app.")
            return TopicContent(
                summary: "Everything is kept in \(records), nothing inside the app.",
                does: does,
                never: ["Nothing is written inside the app itself, so removing or updating the app never loses your records."],
                written: ["Your records folder is \(records). Your settings file is \(records)/config.local.sh."],
                buttons: [.init(title: "Open \(Names.Screen.reports)", target: "reports")])

        case .editByHand:
            let jobs = f.schedules.filter(\.installed).compactMap { line in line.when.map { "\(line.name) \($0.lowercased())" } }
            let ran = jobs.isEmpty ? "" : " On this Mac the jobs run like this: \(jobs.joined(separator: "; "))."
            return TopicContent(
                summary: "Plain shell scripts and one settings file you can open in any editor.",
                does: [
                    "The watching and cleaning is done by plain shell scripts that macOS's own scheduler (launchd) runs. This app is the control surface over them.\(ran)",
                    "The settings you change in this app are written into one marked block of \(records)/config.local.sh. Anything you write by hand outside that block is kept exactly as you wrote it.",
                ],
                never: ["The app never rewrites the parts of your settings file that it did not write."],
                written: ["Your settings file is \(records)/config.local.sh."],
                buttons: [.init(title: "Open \(Names.Screen.schedule) Settings", target: "schedule")])

        case .healthReport:
            var about = "memory"
            if let total = f.totalMemory { about += " (\(total) installed)" }
            about += ", storage"
            if let free = f.freeDisk, let total = f.totalDisk { about += " (\(free) free of \(total))" }
            about += " and what Sparehold did"
            return TopicContent(
                summary: "A one-page summary of the last 30 days, made on this Mac.",
                does: ["The Mac Health Report is a one-page HTML summary of the last 30 days, for IT, family or a buyer. It is generated locally, from this Mac's own records: \(about)."],
                never: ["It is not sent anywhere. You choose where to save it."],
                written: ["The report is saved where you choose; nothing is kept by the app."])

        case .privacy:
            let following: String
            switch f.channel {
            case .beta: following = "You follow Beta, so this happens on this Mac."
            case .releases: following = "You follow Releases, so this does not happen on this Mac unless you switch to Beta."
            case .thisCopy: following = "You follow Development, so this does not happen unless you switch to Beta."
            }
            return TopicContent(
                summary: "Everything is read and written on this Mac; three kinds of request go out.",
                does: [
                    "Memory, storage, login items and network figures are read from this Mac and stay on it.",
                    "The release check: at launch and every 6 hours the app asks GitHub which release is newest. It sends nothing about your Mac.\(f.version.isEmpty || f.version == "0" ? "" : " You are on version \(f.version).")",
                    "Beta: it also asks GitHub how far your copy is behind the development branch, which sends the identifier of the commit your copy was built from, and it reads the development branch's change notes, every 6 hours. \(following)",
                    "Install: choosing Install on a copy built from a clone runs git pull in that clone, which contacts that clone's own remote.",
                ],
                never: ["No usage data, logs or reports are uploaded, and there is no account."],
                written: ["Your records are in \(records) (see \(Names.HowItWorks.whereWritten))."],
                buttons: [.init(title: "Open \(Names.Screen.updates)", target: "update")])
        default:
            return TopicContent(summary: "")
        }
    }

    /// What a topic says on this Mac.
    @MainActor func content(_ f: HowItWorksFacts) -> TopicContent {
        switch tab {
        case .memory: memoryContent(f)
        case .storage: storageContent(f)
        case .system: systemContent(f)
        case .yourData: yourDataContent(f)
        }
    }
}
