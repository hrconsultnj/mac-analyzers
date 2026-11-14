import Foundation

/// Setup's rows, as a pure function of what was read (`SetupInputs`): one row per thing, with its state, the evidence
/// and at most one action. Rows that need the person come first in each tab, then the rest in a fixed order.
public enum SetupItems {

    public static func build(_ inputs: SetupInputs) -> [SetupItem] {
        let all = permissions(inputs) + background(inputs) + protection(inputs)
        return SetupTab.allCases.flatMap { tab in
            let rows = all.filter { $0.tab == tab }
            // problems first, then the choices still open, then what is On or can't be told
            return rows.filter(\.needsYou) + rows.filter { !$0.needsYou && $0.state.needsPerson } + rows.filter { !$0.state.needsPerson }
        }
    }

    public static func items(_ items: [SetupItem], in tab: SetupTab) -> [SetupItem] { items.filter { $0.tab == tab } }

    /// How many rows of a tab are problems that need the person: the number on its tab. A choice is not counted.
    public static func needing(_ items: [SetupItem], in tab: SetupTab) -> Int { self.items(items, in: tab).filter(\.needsYou).count }

    /// The toolbar subtitle.
    public static func subtitle(_ items: [SetupItem]) -> String {
        let count = items.filter(\.needsYou).count
        return count == 0 ? Names.Setup.allSetUp : count == 1 ? "1 thing needs you" : "\(count) things need you"
    }

    // MARK: - Permissions

    static func permissions(_ inputs: SetupInputs) -> [SetupItem] {
        [notifications(inputs), fullDiskAccess(inputs), timeMachine(inputs), login(inputs), automation(inputs)]
    }

    static func notifications(_ inputs: SetupInputs) -> SetupItem {
        let why = "Tells you when an app was stopped or space was reclaimed, so nothing happens behind your back."
        func item(_ state: SetupItemState, _ evidence: String, _ action: SetupAction? = nil, _ title: String? = nil) -> SetupItem {
            SetupItem(id: "notifications", tab: .permissions, title: Names.Setup.notifications, why: why, state: state,
                      evidence: evidence, action: action, actionTitle: title, source: .system)
        }
        switch inputs.notifications {
        case .unavailable: return item(.cantTell, "Can't be read here: this is running without an app bundle.")
        case .notAsked: return item(.notAskedYet, "macOS hasn't been asked yet.", .allowNotifications, Names.Setup.allowNotifications)
        case .denied:
            return item(.off, "Turned off in System Settings. Mac Analyzers still works, but it acts silently.",
                        .openSettings(.notifications), Names.Setup.openSystemSettings)
        case .allowedAlertsOff:
            return item(.off, "Allowed, but alerts are switched off in System Settings, so you only see them in Notification Center.",
                        .openSettings(.notifications), Names.Setup.openSystemSettings)
        case .allowed: return item(.on, "Allowed, and alerts are visible.", .sendTest, Names.Setup.sendTest)
        }
    }

    static func fullDiskAccess(_ inputs: SetupInputs) -> SetupItem {
        let verdict = FullDiskAccessProbe.verdict(app: inputs.fdaApp, agent: inputs.fdaAgent, agentChecked: inputs.fdaAgentChecked, now: inputs.now)
        let acts = verdict.state != .on && verdict.state != .cantTell
        return SetupItem(id: "fullDiskAccess", tab: .permissions, title: Names.Setup.fullDiskAccess,
                         why: "Without it the storage report skips whole folders and under-reports what is using your disk.",
                         state: verdict.state, evidence: verdict.evidence,
                         action: acts ? .openSettings(.fullDiskAccess) : nil, actionTitle: acts ? Names.Setup.openSystemSettings : nil,
                         source: .system)
    }

    static func timeMachine(_ inputs: SetupInputs) -> SetupItem {
        SetupItem(id: "timeMachine", tab: .permissions, title: Names.Setup.timeMachineThinning,
                  why: "Lets Mac Analyzers delete Time Machine's local snapshots without asking for your password each time.",
                  state: inputs.timeMachineAllowed ? .on : .off,
                  evidence: inputs.timeMachineAllowed
                      ? "One command is allowed without a password: deleting Time Machine's local snapshots. Nothing else is."
                      : "Not allowed. Thinning snapshots asks for your administrator password each time.",
                  action: inputs.timeMachineAllowed ? .timeMachineRemove : .timeMachineAllow,
                  actionTitle: inputs.timeMachineAllowed ? Names.Setup.removePermission : Names.Setup.allow, source: .system,
                  weight: .choice)      // optional: it only saves typing a password
    }

    static func login(_ inputs: SetupInputs) -> SetupItem {
        let why = "Puts the menu-bar icon back after a restart. The background protection runs either way."
        // opening at login is a choice; being stuck half-way (waiting for approval, not recognised) is not
        func item(_ state: SetupItemState, _ evidence: String, _ action: SetupAction? = nil, _ title: String? = nil) -> SetupItem {
            SetupItem(id: "login", tab: .permissions, title: Names.Setup.openAtLogin, why: why, state: state, evidence: evidence,
                      action: action, actionTitle: title, source: .system, weight: state == .off ? .choice : .problem)
        }
        switch inputs.login {
        case .enabled: return item(.on, "Mac Analyzers opens when you log in.")
        case .requiresApproval:
            return item(.needsYou, "Waiting for your approval in System Settings › General › Login Items & Extensions.",
                        .openSettings(.loginItems), Names.Setup.openSystemSettings)
        case .notFound:
            return item(.needsYou, "macOS doesn't recognise this copy of the app. Move it to your Applications folder and try again.",
                        .enableLogin, Names.Setup.tryAgain)
        case .notRegistered: return item(.off, "Not turned on.", .enableLogin, Names.Setup.turnOn)
        }
    }

    /// PENDING REMOVAL (blueprint §2.5): the product no longer sends Apple Events once the engine quits apps through the
    /// app, and this row goes with the check that no permission prompt appears (gate G1). Until then it stays, and its
    /// state is a remembered flag, which is the one exception the probe allows.
    static func automation(_ inputs: SetupInputs) -> SetupItem {
        SetupItem(id: "automation", tab: .permissions, title: Names.Setup.automation,
                  why: "Lets the reclaim ask an app to quit the same way you would, so unsaved work is never lost.",
                  state: inputs.automationProven ? .on : .cantTell,
                  evidence: inputs.automationProven ? "Allowed: apps can be asked to quit rather than force-stopped."
                                                    : "macOS asks the first time it is needed. Until then this can't be told.",
                  action: .openSettings(.automation), actionTitle: Names.Setup.openSystemSettings,
                  source: .remembered(pendingRemoval: true), weight: .choice)
    }

    // MARK: - Background

    static func background(_ inputs: SetupInputs) -> [SetupItem] {
        var rows = [SetupItem(id: "engine", tab: .background, title: Names.Setup.analyzerScripts,
                              why: "The part that does the actual watching and cleaning.",
                              state: inputs.engineFound ? .on : .needsYou,
                              evidence: !inputs.engineFound ? "Not found. Reinstall Mac Analyzers to restore them."
                                  : inputs.usingBundledEngine ? "Included with the app: nothing else to install."
                                  : "Running from your copy at ~/mac-analyzers.",
                              source: .file)]
        for job in inputs.jobs {
            let isGuard = job.label == EngineStatus.guardLabel
            let target = isGuard ? "log:guardLog" : job.label.contains("memory") ? "log:memoryClean" : "log:storageClean"
            let evidence: String
            if job.loaded {
                let last = job.lastActivity.map { "last wrote to its log \(relative($0, now: inputs.now))" } ?? "nothing in its log yet"
                evidence = "\(job.schedule ?? "Loaded"), \(last)."
            } else {
                evidence = "Not installed, so nothing runs \(isGuard ? "to watch memory" : "on a schedule") until you install it."
            }
            rows.append(SetupItem(
                id: "job.\(job.label)", tab: .background, title: Names.Setup.jobTitle(job.label), why: Names.Setup.jobWhy(job.label),
                state: job.loaded ? .on : (isGuard ? .needsYou : .off), evidence: evidence,
                action: job.loaded ? .showInActivity(target) : .installAgents,
                actionTitle: job.loaded ? Names.Setup.showInActivity : Names.Setup.install, source: .launchd))
        }
        return rows
    }

    // MARK: - Protection

    /// 20 % of this Mac's memory, to the nearest 256 MB: where the limit should sit.
    public static func suggestedCapMB(installedMB: Int) -> Int { max(1024, (installedMB / 5) / 256 * 256) }

    static func protection(_ inputs: SetupInputs) -> [SetupItem] {
        let suggested = suggestedCapMB(installedMB: inputs.installedMB)
        let deviation = abs(Double(inputs.capMB - suggested)) / Double(max(suggested, 1))
        let installed = ByteSize.text(Int64(inputs.installedMB) * 1_048_576, .headline)
        let current = ByteSize.text(Int64(inputs.capMB) * 1_048_576, .headline)
        let wanted = ByteSize.text(Int64(suggested) * 1_048_576, .headline)
        var rows: [SetupItem] = []
        if deviation <= 0.25 {
            rows.append(SetupItem(id: "cap", tab: .protection, title: Names.Setup.memoryLimit,
                                  why: "How much memory one app may hold before the guard steps in.", state: .on,
                                  evidence: "\(current), which suits a \(installed) Mac.",
                                  action: .change("memory"), actionTitle: Names.Setup.change, source: .file))
        } else {
            let high = inputs.capMB > suggested
            rows.append(SetupItem(id: "cap", tab: .protection, title: Names.Setup.memoryLimit,
                                  why: "How much memory one app may hold before the guard steps in.", state: .needsYou,
                                  evidence: high ? "\(current) is high for a \(installed) Mac: a runaway app could take a fifth of your memory before anything happens."
                                                 : "\(current) is low for a \(installed) Mac: normal apps may be stopped.",
                                  action: .setMemoryCap(suggested), actionTitle: "Use \(wanted)", source: .file))
        }
        rows.append(listRow("neverClose", Names.Setup.neverClose, "Anything on this list is left alone, whatever it is doing.",
                            inputs.neverClose, empty: "Nothing added yet. The built-in safety rules still apply."))
        rows.append(listRow("mayQuit", Names.Setup.mayBeAskedToQuit, "Apps the memory cleanup may ask to quit when it frees memory.",
                            inputs.mayQuit, empty: "None. The cleanup only closes what it finds idle."))
        let on = inputs.recordingSourcesOn
        rows.append(SetupItem(
            id: "recordings", tab: .protection, title: Names.Setup.recordingFolders,
            why: "The folders Old Recordings looks through, and how old a recording has to be.",
            state: on.isEmpty ? .off : (inputs.recordingSourcesNeedAccess > 0 ? .needsYou : .on),
            evidence: on.isEmpty ? "No folders chosen, so Old Recordings has nothing to look through."
                : "\(Names.Setup.list(on)) \(on.count == 1 ? "is" : "are") looked through" + (inputs.recordingSourcesNeedAccess > 0
                    ? ", and \(inputs.recordingSourcesNeedAccess) \(inputs.recordingSourcesNeedAccess == 1 ? "needs" : "need") your permission to look in a folder macOS protects." : "."),
            action: .change("recordings:sources"), actionTitle: Names.Recordings.sourcesButton, source: .file,
            // no folders chosen is a choice; folders chosen that macOS won't let it look in is not
            weight: on.isEmpty ? .choice : .problem))
        rows.append(SetupItem(
            id: "config", tab: .protection, title: Names.Setup.settingsFile,
            why: "Holds your memory limit, your protected apps and your schedule. An update never overwrites it.",
            state: inputs.settingsFileExists ? .on : .off,
            evidence: inputs.settingsFileExists ? "Saved at ~/mac-analyzers/config.local.sh."
                                                : "Not created yet. It is written the first time you save a setting.",
            action: inputs.settingsFileExists ? nil : .writeConfig, actionTitle: inputs.settingsFileExists ? nil : Names.Setup.createIt,
            source: .file, weight: .choice))
        return rows
    }

    private static func listRow(_ id: String, _ title: String, _ why: String, _ list: [String], empty: String) -> SetupItem {
        SetupItem(id: id, tab: .protection, title: title, why: why, state: list.isEmpty ? .off : .on,
                  evidence: list.isEmpty ? empty : "\(list.count) \(list.count == 1 ? "app" : "apps"): \(Names.Setup.list(Array(list.prefix(3))))\(list.count > 3 ? " and \(list.count - 3) more" : "").",
                  action: .change("memory"), actionTitle: Names.Setup.change, source: .file, weight: .choice)
    }

    private static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
