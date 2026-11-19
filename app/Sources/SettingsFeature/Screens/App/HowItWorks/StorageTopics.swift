import Foundation
import AnalyzersKit

/// The Storage tab's topics. What runs by itself on a schedule is read from the installed schedule; what a person starts is a
/// preview first, and the two are never confused.
extension HowItWorksTopic {

    @MainActor func storageContent(_ f: HowItWorksFacts) -> TopicContent {
        switch self {
        case .safeToRemove:
            let daily = GuardControl.storageCleanLabel, deep = GuardControl.storageDeepLabel
            let scheduledDaily = f.storageCleanDoes(daily) ?? f.notScheduled(daily)
            let scheduledDeep = f.storageCleanDoes(deep) ?? f.notScheduled(deep)
            var does: [String] = []
            if let free = f.freeDisk, let total = f.totalDisk {
                does.append("Your startup disk has \(free) free of \(total).\(f.runway.map { " At your current pace the disk fills in \($0)." } ?? "")")
            }
            does.append("\(Names.Screen.cachesAndBuilds) finds what your tools can make again: build caches, the dependency folders of projects you have not touched for \(f.days(f.nodeModulesDays))\(f.nodeModulesNeedClean ? ", and only when they have no unsaved changes" : ""), and package-manager caches.\(f.logsRead ? (f.week.reclaimableBytes.map { " The latest preview found \(ByteSize.text($0, .headline)) you could take back." } ?? " Nothing is waiting from a preview.") : "")")
            does.append("When you start a cleanup yourself it is a preview first: you see what would be removed and untick anything you want kept, and only then does Apply start. Caches and build folders are deleted for good, because your tools make them again, so Undo cannot bring them back.")
            does.append("The cleanups that run by themselves do not wait for you. \(scheduledDaily)")
            does.append(scheduledDeep)
            does.append("Change when they run in \(Names.Group.settings) › \(Names.Screen.schedule). The background jobs are switched off only all together, in \(Names.Screen.setup) › \(Names.Screen.turnOff).")
            if f.logsRead { does.append("In the last 7 days, \(f.week.cleanRuns) cleanups freed \(ByteSize.text(f.week.storageFreedBytes, .headline)).") }
            var summary = [f.freeDisk.flatMap { free in f.totalDisk.map { "\(free) free of \($0)." } }].compactMap { $0 }.joined()
            if f.logsRead { summary += (summary.isEmpty ? "" : " ") + "\(f.week.cleanRuns) cleanups this week." }
            return TopicContent(
                summary: summary.isEmpty ? "What can be removed, and what runs by itself." : summary,
                does: does,
                never: [
                    "Build folders are removed only when nothing has written to them for days, and a project that something live runs from is left alone.",
                    "A cleanup you start yourself never removes anything you have not reviewed in a preview.",
                ],
                written: ["Each run writes a full report and appears in Activity (see \(Names.HowItWorks.whereWritten))."],
                buttons: [.init(title: "Open \(Names.Screen.cachesAndBuilds)", target: "caches"),
                          .init(title: Names.HowItWorks.change, target: "schedule")])

        case .downloadsTemp:
            return TopicContent(
                summary: "Downloads older than \(f.days(f.downloadsDays)), screenshots older than \(f.days(f.screenshotsDays)).",
                does: [
                    "\(Names.Screen.downloads) looks for files you have not changed for \(f.days(f.downloadsDays)), and for screenshots older than \(f.days(f.screenshotsDays)). You review them in a preview; what you apply goes to the Trash, and Undo puts it back.",
                    "\(Names.Screen.tempAndAgents) clears temporary files that have been idle for \(f.hours(f.tempIdleHours)), scratch folders of coding agents idle for \(f.days(f.tempAgentScratchDays)), and tool downloads idle for \(f.days(f.tempToolDownloadDays)). It also shows a preview first, and what you apply goes to the Trash.",
                    "Neither of these has a schedule of its own: they run when you start them.",
                    "macOS also clears /tmp by itself every night: files nobody has touched for three days. It skips mounted disk images and anything still in use.",
                ],
                never: ["Anything that is open, in use, owned by someone else, or a mounted disk image you have not approved is never touched."],
                written: ["Each run writes a report and appears in Activity (see \(Names.HowItWorks.whereWritten))."],
                buttons: [.init(title: "Open \(Names.Screen.downloads)", target: "downloads"),
                          .init(title: "Open \(Names.Screen.tempAndAgents)", target: "temp")])

        case .timeMachine:
            let deep = GuardControl.storageDeepLabel
            var byItself = ""
            if let line = f.schedule(deep), line.installed, line.thinsSnapshots, let when = line.when {
                byItself = f.timeMachinePermission
                    ? "Because you have given the permission, \(line.name) deletes local snapshots by itself \(when.lowercased()), without asking."
                    : "\(line.name) runs \(when.lowercased()) and would delete local snapshots, but it skips them until you give the permission."
            }
            let permission = f.timeMachinePermission
                ? "You have given that permission on this Mac."
                : "You have not given that permission on this Mac yet, so Sparehold will ask the first time you delete snapshots yourself."
            return TopicContent(
                summary: f.timeMachinePermission ? "Permission given on this Mac." : "Needs a one-time permission.",
                does: [
                    "While Time Machine backs up, macOS keeps hourly snapshots on this Mac, and they use disk space. The \(Names.Screen.timeMachine) screen lists them so you can delete the ones you do not need.",
                    "Deleting snapshots needs a one-time permission, with your administrator password, for exactly one command. After that, any program running on your account can delete local snapshots without asking, and nothing else is allowed. \(permission)",
                ] + (byItself.isEmpty ? [] : [byItself]),
                never: ["Sparehold never touches your backups on the backup disk. It only deletes local snapshots on this Mac, and when you delete them yourself, only after you confirm."],
                written: ["The permission is one small file. You can remove it from the \(Names.Screen.timeMachine) screen or from Setup."],
                buttons: [.init(title: "Open \(Names.Screen.timeMachine)", target: "timemachine")])

        case .unusedApps:
            return TopicContent(
                summary: "Apps you have not opened in a long time, shown for you to decide.",
                does: [
                    "\(Names.Screen.unusedApps) lists apps you have never opened or have not opened in a long time, using what macOS recorded about their use. Apps with no record of use are listed separately, since not knowing is not the same as not using.",
                    "You choose what to move. It goes to the Trash, and Undo puts it back.",
                ],
                never: ["Apps that are running now are left alone, and nothing is moved without your review. It has no schedule of its own."],
                written: ["Each run appears in Activity (see \(Names.HowItWorks.whereWritten))."],
                buttons: [.init(title: "Open \(Names.Screen.unusedApps)", target: "unused")])

        case .oldRecordings:
            return TopicContent(
                summary: "Recordings older than \(f.days(f.recordingsDays)), in the folders you choose.",
                does: [
                    "\(Names.Screen.oldRecordings) looks through the folders where you keep recordings (Zoom, screen recordings, voice memos and the like; you choose them with Sources on its screen) for ones older than \(f.days(f.recordingsDays)).",
                    "You review a preview, and what you apply goes to the Trash, and Undo puts it back.",
                ],
                never: ["Nothing is removed without a preview you reviewed, and it has no schedule of its own."],
                written: ["Each run appears in Activity (see \(Names.HowItWorks.whereWritten))."],
                buttons: [.init(title: "Open \(Names.Screen.oldRecordings)", target: "recordings")])
        default:
            return TopicContent(summary: "")
        }
    }
}
