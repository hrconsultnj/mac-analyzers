import Foundation
import AnalyzersKit

/// The Memory tab's topics, written with this Mac's numbers. A sentence that would quote a value that was not read is left out.
extension HowItWorksTopic {

    @MainActor func memoryContent(_ f: HowItWorksFacts) -> TopicContent {
        switch self {
        case .measures:
            var installed = ""
            if let total = f.totalMemory, let used = f.usedMemory { installed = " On this Mac, \(total) is installed and \(used) is in use." }
            var compressor = ""
            if let original = f.compressedOriginal, let held = f.compressed {
                compressor = " Right now the compressor holds about \(original) of idle app memory in \(held) of real memory."
            }
            return TopicContent(
                summary: f.usedMemory.flatMap { used in f.totalMemory.map { "\(used) of your \($0) is in use right now." } }
                    ?? "How the Monitor reads memory.",
                does: [
                    "The Monitor shows resident memory: the physical memory a program occupies right now. That is the number every size in Sparehold shows, and the one Memory Guard acts on.\(installed)",
                    "Activity Monitor's “Memory” column also counts compressed and swapped-out memory, so a program can show 7 GB or more there while its resident size stays under your limit of \(f.limit). That is why a big program can survive when memory pressure is low: macOS has already compressed it.\(compressor)",
                ],
                never: [
                    "Graphics (GPU) memory is deliberately not counted. macOS offers no public figure for how much of it each program uses, and on Apple Silicon's shared memory the pressure signal that Memory Guard already watches is the one that matters.",
                ],
                written: ["Looking at the Monitor writes nothing. What Memory Guard does is kept in its log (see \(Names.HowItWorks.whereWritten))."],
                buttons: [.init(title: "Open \(Names.Screen.monitor)", target: "monitor")])

        case .guardSteps:
            let hardCap = f.hardCapStops
                ? "When that program is over your limit (\(f.limitPhrase)), it is stopped at any pressure level, by default at most once a minute, and a crisis report is written first so you can see what was using the memory. You can change Memory Guard to only warn you in \(Names.Group.settings) › \(Names.Screen.memorySettings)."
                : "When that program is over your limit (\(f.limitPhrase)), Memory Guard writes a crisis report and tells you. You have switched it to warn only in \(Names.Group.settings) › \(Names.Screen.memorySettings), so it stops nothing."
            let pressure = f.pressureStops
                ? "When macOS says memory is critically short, the biggest program Memory Guard may stop that is using more than 500 MB is stopped. You can switch this to warn only in \(Names.Group.settings) › \(Names.Screen.memorySettings)."
                : "When macOS says memory is critically short, Memory Guard tells you. You have switched it to warn only in \(Names.Group.settings) › \(Names.Screen.memorySettings)."
            let kinds = f.devToolKinds.isEmpty
                ? "Only developer tools are ever stopped automatically."
                : "Only developer tools are ever stopped automatically: \(f.devToolKinds.joined(separator: ", ")). That covers programs such as node, npm, bun, tsx and deno, the dev servers of Next.js, Vite, Webpack and Turbo, Vitest and Jest, and Playwright and headless browsers."
            var summary = "Your limit is \(f.limitPhrase)."
            if f.logsRead { summary += " This week: \(f.week.stopped) stopped, \(f.week.spikes) sudden jumps." }
            return TopicContent(
                summary: summary,
                does: [
                    "Memory Guard checks \(f.guardEvery). Each time it looks at the single biggest program it is allowed to stop.",
                    hardCap,
                    pressure,
                    "A sudden jump (a program growing by \(f.megabytes(f.spikeMB)) since the last check while using more than \(f.megabytes(f.spikeMinMB))) and a program using more than \(f.cpuHogPercent) percent of a processor for \(f.cpuHogChecks) checks in a row only ever notify you. Nothing is stopped for either.",
                    kinds,
                    f.devSweepSeconds > 0 && !f.newerBashInstalled
                        ? "Memory Guard can also start a quieter pass of the memory cleaner every \(f.devSweepSeconds) seconds that stops idle developer tools, unused development servers, emulators and simulators, and build daemons. It needs a bash newer than the one macOS ships, and none is installed on this Mac, so it does nothing here."
                        : f.devSweepSeconds > 0
                        ? "Separately, while Memory Guard runs it starts a quieter pass of the memory cleaner every \(f.devSweepSeconds) seconds, and that pass applies without a preview: it stops developer tools whose parent is gone once they sit idle, development servers nobody is using, emulators and simulators nobody is using, and Gradle and Kotlin build daemons while no build runs. It never touches apps, protected programs or a live coding session."
                        : "Memory Guard does not run the quieter pass of the memory cleaner that stops idle developer tools, because you have set its interval to 0.",
                    "Rules for other kinds of program are only being watched: Memory Guard shows what they would have done and stops nothing for them.",
                ] + (f.logsRead ? ["In the last 7 days: \(f.week.stopped) programs stopped, \(f.week.spikes) sudden jumps, \(f.week.pressure) pressure warnings and \(f.week.cpuHogs) busy-processor alerts."] : []),
                never: [
                    "Stop and Quit in the Monitor are different: those are your own actions, so they work on any program, just as they do in Activity Monitor.",
                ],
                written: ["Every action is written in the guard log, and every stop first writes a crisis report (see \(Names.HowItWorks.whereWritten))."],
                buttons: [.init(title: "Open \(Names.Screen.memoryGuard)", target: "guard"),
                          .init(title: Names.HowItWorks.change, target: "memory")])

        case .guardNever:
            let extra = f.protectedExtra == 0
                ? "You have not added any programs of your own to the protected list."
                : "You have added \(f.protectedExtra) \(f.protectedExtra == 1 ? "program" : "programs") of your own to the protected list."
            return TopicContent(
                summary: "Apps and anything you protect are never stopped by themselves.",
                does: [
                    "Real apps, and anything on your protected list, are never stopped automatically. \(extra)",
                    "A program that belongs to a coding session that is running right now is always kept safe, and that is checked again at every stop.",
                ],
                never: [
                    "Memory Guard never stops an app or a protected program by itself, at any pressure.",
                    "It never stops anything that belongs to a live coding session.",
                    "Spikes and busy processors never stop anything: they only tell you.",
                ],
                written: ["The protected list is kept in your settings file (see \(Names.HowItWorks.editByHand))."],
                buttons: [.init(title: "Open \(Names.Screen.memoryGuard)", target: "guard"),
                          .init(title: Names.HowItWorks.change, target: "memory")])

        case .rowLocks:
            return TopicContent(
                summary: "A lock means Memory Guard and the cleanups never stop that row by themselves. You still can.",
                does: [
                    "A lock on a row in the Monitor is about automatic actions only. Hover the lock and it turns into the row's Stop or Quit button; the confirmation then says why the row is normally protected and what you could lose.",
                    "A row shows a lock when it is part of, or holds, a live coding session; when you put it on your Never Close list or it is on the built-in never list; when it is a Connection Tool that may be how you reach this Mac; or when Sparehold could not read its list of coding agents and so cannot tell.",
                    "A group is locked when some of its programs are. You can stop the whole group, or open it and stop one program or one process; a member is never locked just because its group is.",
                ],
                never: [
                    "Memory Guard, the cleanups, the menu-bar panel and notification actions keep honouring every lock exactly as before.",
                    "Some rows have no button at all, and say why instead: macOS's own processes, another account's, and a terminal session, which ignores a polite stop (close its window to end it), and Sparehold itself and the program that started it.",
                ],
                written: ["A stop you confirm is a polite request first; if anything is still running, you are asked separately about Force Stop."],
                buttons: [.init(title: "Open \(Names.Screen.monitor)", target: "monitor")])

        case .cleanup:
            let label = GuardControl.memoryCleanLabel
            let scheduled = f.memoryCleanDoes(label) ?? f.notScheduled(label)
            let alsoQuit = f.alsoQuit == 0
                ? "You have not listed any apps to be asked to quit."
                : "\(f.alsoQuit) \(f.alsoQuit == 1 ? "app is" : "apps are") on your list of apps to ask to quit."
            var summary = f.schedule(label)?.installed == true ? "Runs \(f.schedule(label)?.when?.lowercased() ?? "on a schedule"), by itself." : "Not scheduled on this Mac."
            if f.logsRead { summary += " This week it helped free \(f.megabytes(f.week.memoryFreedMB))." }
            return TopicContent(
                summary: summary,
                does: [
                    scheduled,
                    "When you start \(Names.Screen.memoryCleanup) yourself from its screen, it always shows a preview first, and nothing is closed until you review the preview and apply it. \(alsoQuit)",
                    "Change when the scheduled run happens in \(Names.Group.settings) › \(Names.Screen.schedule). The background jobs are switched off only all together, in \(Names.Screen.setup) › \(Names.Screen.turnOff).",
                ],
                never: ["A run you start yourself never closes anything you did not see in a preview, and no run touches your protected programs."],
                written: ["Each run writes a full report (see \(Names.HowItWorks.whereWritten)) and appears in Activity."],
                buttons: [.init(title: "Open \(Names.Screen.memoryCleanup)", target: "actions:memoryClean"),
                          .init(title: Names.HowItWorks.change, target: "schedule")])
        default:
            return TopicContent(summary: "")
        }
    }
}
