import Foundation

/// The names of things, written once. The sidebar, Activity, the toolbar, the
/// menu-bar panel, screen titles and notifications all read their names from
/// here, so one thing cannot be called two things.
///
/// Every name in this file is a NAME (a screen, a task, a category, a state)
/// and is written in title style — `scripts/check.sh names` runs
/// `agent-runner --probe-names`, which prints every entry below and fails on
/// one that `TitleStyle` rejects. Descriptions, tooltips and status
/// sentences are not names and are written where they are shown.
public enum Names {

    /// The product itself.
    public static let app = "Mac Analyzers"

    // MARK: - sidebar groups

    public enum Group {
        public static let memory = "Memory"
        public static let storage = "Storage"
        public static let system = "System"
        public static let history = "History"
        public static let settings = "Settings"
        public static let app = Names.app
    }

    // MARK: - screens (the sidebar rows, and the title of the screen each opens)

    public enum Screen {
        public static let overview = "Overview"
        public static let activity = "Activity"
        public static let setup = "Setup"
        public static let monitor = "Monitor"
        public static let memoryGuard = "Memory Guard"
        public static let memoryCleanup = "Memory Cleanup"
        public static let disk = "Disk"
        public static let cachesAndBuilds = "Caches & Builds"
        public static let downloads = "Downloads"
        public static let tempAndAgents = "Temp & Agents"
        public static let timeMachine = "Time Machine"
        public static let spotlight = "Spotlight"
        public static let unusedApps = "Unused Apps"
        public static let oldRecordings = "Old Recordings"
        public static let network = "Network"
        public static let loginItems = "Login & Startup Items"
        public static let reports = "Reports"
        public static let trends = "Trends"
        public static let undo = "Undo"
        public static let memorySettings = "Memory"
        public static let storageSettings = "Storage"
        public static let notifications = "Notifications"
        public static let schedule = "Schedule"
        public static let updates = "Updates"
        public static let howItWorks = "How It Works"
        public static let support = "Support"
        public static let turnOff = "Turn Off or Remove"
        /// The screen that previews and applies one cleaner (reached from the
        /// menu-bar panel and from Activity; it has no sidebar row).
        public static let actions = "Actions"
    }

    // MARK: - things that are not screens but are named in several places

    /// The guard's crisis snapshots. One name, wherever they are listed.
    public static let crisisReports = "Crisis Reports"
    public static let crisisReport = "Crisis Report"
    /// The log of the memory cleaner's sweep of every dev process at once.
    public static let memoryReclaim = "Memory Reclaim"
    /// What was added to or removed from startup.
    public static let startupChanges = "Startup Changes"

    // MARK: - states shown in more than one place

    public enum State {
        public static let upToDate = "Up to Date"
        public static let updateAvailable = "Update Available"
        public static let developmentBuild = "Dev Build"
    }

    // MARK: - update channels

    public enum Channel {
        public static let heading = "Update Channel"
        public static let releases = "Releases"
        public static let beta = "Beta"
        public static let thisCopy = "This Copy"
        public static let installBeta = "Update to Newest Beta"
        public static let rebuild = "Rebuild from This Copy"
    }

    /// The sentences the two development channels say (not names: they are not in the title-style table).
    public enum ChannelText {
        public static let notAClone = "This copy was downloaded, not built from a clone of the project, so it can only follow releases."
        public static func notOnDevelopment(_ branch: String?) -> String {
            "Beta follows the development branch. Your clone is on \(branch.map { "“\($0)”" } ?? "no branch")."
        }
        public static let offline = "Couldn't reach GitHub to check."
        public static let rateLimited = "GitHub is limiting checks from this network right now. Try again in a while."
        public static let cannotRead = "Couldn't read your clone with git, so it can't be compared with this copy."
        public static let builtWithLocalChanges = "This copy was built with changes that are not committed, so it is not the newest beta."
        public static let branchChanged = "Your clone is no longer on the development branch, so the newest beta can't be installed."
        public static let aheadOfDevelopment = "This copy has changes that are newer than the development branch on GitHub."
        public static let notOnGitHub = "This copy was built from changes that are not on GitHub."
        public static let divergedFromDevelopment = "This copy and the development branch on GitHub have each moved on."
        public static let cloneIsBehindInstall = "This copy has changes your clone no longer has."
        public static let cloneLacksCommit = "This copy was built from changes your clone doesn't have."
        public static let installHadChangesCloneLost = "This copy was built with changes your clone no longer has."
    }

    // MARK: - Activity scopes

    public enum Scope {
        public static let all = "All"
        public static let running = "Running"
        public static let needsReview = "Needs Review"
        public static let failed = "Failed"
    }

    // MARK: - process categories in Monitor

    public enum Category {
        public static let apps = "Apps"
        public static let tools = "Command-Line & Developer Tools"
        public static let system = "macOS"
        /// The family list in Monitor groups apps and tools together.
        public static let appsAndServices = "Apps & Services"
        public static let singleProcesses = "Single Processes"
    }

    // MARK: - storage: what a reclaimable thing is called

    /// Kinds of build cache and package folder, as the review lists them.
    public enum Cache {
        public static let nextBuild = "Next.js Build Cache"
        public static let turbo = "Turborepo Cache"
        public static let buildOutput = "Build Output"
        public static let vite = "Vite Cache"
        public static let svelteKit = "SvelteKit Cache"
        public static let nuxt = "Nuxt Cache"
        public static let parcel = "Parcel Cache"
        public static let nodePackages = "Node.js Packages"
        public static let vendored = "Vendored Code"
        public static let pythonCache = "Python Cache"
        public static let pythonEnvironment = "Python Environment"
        public static let rustBuild = "Rust Build Output"
        public static let other = "Cache Folder"
        /// The two sweeps a cleanup can make.
        public static let daily = "Daily"
        public static let deep = "Deep"
    }

    /// What a file in Downloads or Screenshots is, and how long it has sat there.
    public enum Download {
        public static let onlyInICloud = "Only in iCloud"
        public static let documents = "Documents"
        public static let images = "Images"
        public static let archives = "Archives"
        public static let installers = "Installers & Disk Images"
        public static let video = "Video"
        public static let audio = "Audio"
        public static let folders = "Folders"
        public static let screenshots = "Screenshots"
        public static let other = "Other Files"
        public static let underThreeMonths = "Under 3 Months"
        public static let threeToSixMonths = "3 to 6 Months"
        public static let sixToTwelveMonths = "6 to 12 Months"
        public static let overAYear = "Over a Year"
        public static let dateUnknown = "Date Unknown"
    }

    /// Time Machine: the words of its actions and its one-time permission.
    public enum TimeMachine {
        public static let allow = "Allow…"
        public static let delete = "Delete Snapshots…"
        public static let startBackup = "Start a Backup Afterwards"
        public static let notAllowedYet = "Deleting snapshots isn't allowed yet. Click Allow… in the bar above first."
        public static let removePermission = "Remove Permission…"
        /// The row in Turn Off that removes it.
        public static let permissionRowTitle = "Time Machine Permission"
        public static let permissionTitle = "Deleting Snapshots Needs a One-Time Permission"
        public static let earlierPermissionTitle = "An Earlier Permission File Exists"
        public static let earlierPermissionDetail = "A permission file from an older install in Terminal is on this Mac, and it may be what allows this account to delete local snapshots without a password. Mac Analyzers cannot read it. This command, run in Terminal, removes it if it is this account's and leaves it alone otherwise:"
        public static let permissionDetail = "macOS asks for your administrator password once to allow one command: deleting local snapshots. Afterwards any program running on your account can do that without asking, and nothing else is allowed. You can remove the permission from this screen."
        public static let nothingToThin = "No Local Snapshots"
        public static let nothingToThinDetail = "Time Machine keeps hourly snapshots on this Mac while it backs up. There are none right now, so there is nothing to delete."
    }

    /// Unused Apps and Old Recordings: the groups and the words of what a finished run did.
    public enum Unused {
        public static let neverOpened = "Never Opened"
        public static let noRecord = "No Record of Use"
        public static let removed = "Removed"
        public static let movedToTrash = "Moved to Trash"
        public static let couldNotMove = "Couldn't Move"
        public static let leftInPlace = "Left in Place"
        public static let couldNotRemove = "Couldn't Remove"
        public static let runningKept = "Running: quit it first, then preview again. It is left alone."
        public static let recordings = "Old Recordings"
    }

    /// Where an item found in temp and agent folders lives, and the verdict on it.
    public enum Temp {
        public static let tempFolder = "Temp Folder"
        public static let yourTempFolder = "Your Temp Folder"
        public static let sharedTempFolder = "Shared Temp Folder"
        public static let claudeCode = "Claude Code"
        public static let codex = "Codex"
        public static let claudeApp = "Claude App"
        public static let nodeTools = "Node Tool Caches"
        public static let otherTools = "Other AI Tools"
        public static let managedByMacOS = "Managed by macOS"
    }

    /// Why a row is shown but left alone, in the words the review's kept rows use.
    public enum Kept {
        public static let leftForOwner = "Left for Its Owner"
        public static let conversationHistory = "Conversation History"
        public static let keepList = "On Your Keep List"
        public static let currentVersion = "Current Version"
        /// A file kept only in iCloud: its row says what it is and that nothing is freed here.
        public static let onlyInICloud = "Only in iCloud: not downloaded to this Mac, so nothing is freed here. No cleanup moves it, because that would remove it from iCloud and your other devices once the Trash is emptied."
    }

    /// The categories (tabs) of each Storage screen, and what groups the rows in them.
    public enum StorageTab {
        public static let projects = "Projects"
        public static let appCaches = "App Caches"
        public static let developerTools = "Developer Tools"
        public static let documents = "Documents"
        public static let images = "Images"
        public static let screenshots = "Screenshots"
        public static let archivesAndInstallers = "Archives & Installers"
        public static let media = "Media"
        public static let foldersAndOther = "Folders & Other"
        public static let temporaryFiles = "Temporary Files"
        public static let codingAgents = "Coding Agents"
        public static let diskImages = "Disk Images"
        public static let packageManagers = "Package Managers"
        public static let xcodeSimulators = "Xcode Simulators"
        public static let docker = "Docker"
        public static let toolCaches = "Tool Caches"
        public static let timeMachine = "Time Machine"
        public static let apps = "Apps"
        public static let oldRecordings = "Old Recordings"
    }

    /// The cleanups that are not files: each is a reviewed row.
    public enum Prune {
        public static let pnpm = "pnpm Store"
        public static let npm = "npm Cache"
        public static let brew = "Homebrew Downloads"
        public static let simulators = "Unused Simulators"
        public static let docker = "Docker Cleanup"
        public static let snapshots = "Time Machine Snapshots"
        /// What a finished run did with each.
        public static let ran = "Ran"
        public static let started = "Started"
        public static let skipped = "Skipped"
        public static let couldNotRun = "Couldn't Run"
    }

    /// Developer-tool caches the deep cleanup can empty.
    public enum ToolCacheName {
        public static let pip = "pip Cache"
        public static let uv = "uv Cache"
        public static let cargo = "Cargo Registry Cache"
        public static let gradle = "Gradle Caches"
        public static let derivedData = "Xcode DerivedData"
        public static let bun = "Bun Install Cache"
        public static let cipd = "CIPD Cache"
        public static let goModules = "Go Module Cache"
        public static let androidSnapshots = "Android Emulator Snapshots"
        public static let aerials = "Aerial Wallpapers"
    }

    /// Whether Spotlight is kept out of a folder.
    public enum Fence {
        public static let fenced = "Fenced"
        public static let notFenced = "Not Fenced"
    }

    // MARK: - System: Login & Startup Items, Network, Reports

    /// What kind of startup item a row is, how it is doing, and what the audit
    /// found. The audit script writes engine tokens; these are their words.
    public enum Startup {
        public static let loginItem = "Login Item"
        public static let launchAgent = "Launch Agent"
        public static let launchDaemon = "Launch Daemon"
        public static let helperTool = "Helper Tool"

        public static let running = "Running"
        public static let loaded = "Loaded"
        public static let notLoaded = "Not Loaded"
        public static let disabled = "Disabled"
        public static let enabled = "Enabled"

        public static let leftover = "Leftover"
        public static let possibleLeftover = "Possible Leftover"
        public static let notChecked = "Not Checked"
        public static let removed = "Removed"

        /// The categories (tabs) of the Login & Startup Items screen.
        public static let categoryApps = "Apps"
        public static let categoryBackground = "Background Items"
        public static let categoryLeftovers = "Leftovers"
        public static let categoryChanges = "Changes"

        /// The toolbar filter that narrows any of them.
        public static let filterAdministrator = "Needs Administrator"
        public static let filterNotChecked = "Not Checked"
    }

    /// The two reports the analyzers write.
    public enum Report {
        public static let memory = "Memory Report"
        public static let storage = "Storage Report"
    }

    /// The scopes of the Network screen.
    public enum NetworkScope {
        public static let snapshot = "Snapshot"
        public static let history = "History"
    }

    // MARK: - table column titles

    /// The title of a column in `OutlineTable`, so the same column is called
    /// the same on every screen that has it.
    public enum Column {
        public static let name = "Name"
        public static let size = "Size"
        public static let memory = "Memory"
        public static let cpu = "CPU"
        public static let pid = "PID"
        public static let whatItIs = "What It Is"
        public static let finding = "Finding"
        public static let state = "State"
        public static let kind = "Kind"
        public static let belongsTo = "Belongs To"
        public static let administrator = "Administrator"
        public static let total = "Total"
        public static let downloaded = "Downloaded"
        public static let uploaded = "Uploaded"
        public static let share = "Share"
        public static let running = "Running"
        public static let items = "Items"
        public static let removed = "Removed"
        public static let lastUsed = "Last Used"
        public static let fenced = "Fenced"
        public static let when = "When"
        public static let whatHappened = "What Happened"
        public static let project = "Project"
        public static let memoryFreed = "Memory Freed"

        /// Every title above, for the check.
        public static let all = [name, size, memory, cpu, pid, whatItIs, finding, state, kind, belongsTo,
                                 administrator, total, downloaded, uploaded, share, running, items, removed,
                                 lastUsed, fenced, when, whatHappened, project, memoryFreed]
    }

    // MARK: - the closed row that holds what is empty

    /// The one closed row at the end of a level that folds the rows with nothing in
    /// them; `OutlineFolding` and every review table use this name.
    public enum Fold {
        public static let empty = "Nothing to Free"
    }

    // MARK: - putting things back from the Trash (Undo's restore, as Activity lists it)

    public enum Restore {
        public static let restored = "Restored"
        public static let item = "Item"
        public static let items = "Items"
        public static let nothing = "Nothing Restored"
        /// The group a restore's screen lists what it put back under.
        public static let putBack = "Put Back"
    }

    // MARK: - lookups by type

    /// The screen a receipt ledger belongs to, by the source name `UndoLedger.ledgers` gives it.
    public static func screen(forLedgerSource source: String) -> String {
        switch source {
        case "Janitor": Screen.downloads
        case "Temp & Agents": Screen.tempAndAgents
        case "Unused Apps": Screen.unusedApps
        case "Old Recordings": Screen.oldRecordings
        default: source
        }
    }

    /// What a task is called: the screen that holds it.
    public static func job(_ kind: JobKind) -> String {
        switch kind {
        case .memoryClean, .reclaim: Screen.memoryCleanup
        case .storageClean: Screen.cachesAndBuilds
        case .janitor: Screen.downloads
        case .tempClean, .eject: Screen.tempAndAgents
        case .tmReclaim: Screen.timeMachine
        case .spotlight: Screen.spotlight
        case .loginItems: Screen.loginItems
        case .unusedApps: Screen.unusedApps
        case .recordings: Screen.oldRecordings
        case .networkSnapshot: Screen.network
        case .memoryReport, .storageReport: Screen.reports
        case .installAgents, .uninstallAgents, .sudoersInstall: Screen.setup
        }
    }

    /// What a log is called: the screen that shows it, where there is one.
    public static func log(_ log: EngineLog) -> String {
        switch log {
        case .guardLog: Screen.memoryGuard
        case .memoryClean: Screen.memoryCleanup
        case .reclaim: memoryReclaim
        case .storageClean: Screen.cachesAndBuilds
        case .janitor: Screen.downloads
        case .tempSpace: Screen.tempAndAgents
        case .persistence: startupChanges
        case .loginItems: Screen.loginItems
        case .spotlightAudit: Screen.spotlight
        case .cleanupApps: Screen.unusedApps
        case .tmReclaim: Screen.timeMachine
        case .cleanupRecordings: Screen.oldRecordings
        case .forensics: crisisReports
        }
    }

    // MARK: - the shared review, raw output and run screens

    public enum Review {
        public static let selectAll = "Select All"
        public static let selectNone = "Select None"
        public static let previewAgain = "Preview Again"
        public static let preview = "Preview"
        public static let stop = "Stop"
        public static let history = "History"
        public static let showRawOutput = "Show Raw Output"
        /// Where a cleanup puts what it clears, said on every state of its screen.
        public static let goesToTrash = "Goes to the Trash"
        public static let deletedPermanently = "Deleted Permanently"
        public static let copyDiagnostics = "Copy Diagnostics"
        public static let discard = "Discard"
        public static let showInFinder = "Show in Finder"
        public static let copyPath = "Copy Path"
        public static let copyPaths = "Copy Paths"
    }

    public enum Raw {
        public static let screen = "Raw Output"
        public static let searchPrompt = "Search Output"
        public static let copy = "Copy"
        public static let noOutput = "No Output Was Kept"
        public static let showAll = "Show All"
        public static let showOlder = "Show Older"
    }

    // MARK: - Monitor

    public enum Monitor {
        public static let everything = "Everything"
        public static let tools = "Tools"
        public static let lens = "Lens"
        public static let lensMemory = "Memory"
        public static let lensEnergy = "Energy"
        public static let lensDisk = "Disk I/O"
        public static let name = "Name"
        public static let whatItIs = "What It Is"
        public static let memory = "Memory"
        public static let cpu = "CPU"
        public static let pid = "PID"
        public static let energy = "Energy"
        public static let read = "Read"
        public static let written = "Written"
        public static let ended = "Ended"
        public static let refresh = "Refresh"
        public static let refreshNow = "Refresh Now"
        public static let every5 = "Every 5 Seconds"
        public static let every15 = "Every 15 Seconds"
        public static let every60 = "Every 60 Seconds"
        public static let paused = "Paused"
        public static let inspector = "Inspector"
        public static let showDetails = "Show Details"
        public static let whereYourMemoryIs = "Where Your Memory Is"
        public static let nothingInScope = "Nothing in This Scope"
    }

    // MARK: - stopping things

    public enum Stop {
        public static let stop = "Stop"
        public static let quit = "Quit"
        public static let forceStop = "Force Stop"
        public static let leaveRunning = "Leave Running"
        public static let leftAlone = "Some Programs Were Left Alone"
        public static let leftAloneOne = "Left Alone"
    }

    // MARK: - Memory Guard

    public enum Guard {
        public static let stopped = "Stopped"
        public static let alerts = "Alerts"
        public static let period = "Period"
        public static let show = "Show"
        public static let last7 = "Last 7 Days"
        public static let last90 = "Last 90 Days"
        public static let nothingToReport = "Nothing to Report"
        public static let nothingHere = "Nothing Here"
        public static let eventGone = "This Event Is Gone"
        public static let whatHappened = "What Happened"
        public static let theProgram = "The Program"
        public static let whyTheGuardDoesThis = "Why the Guard Does This"
        public static let eachTime = "Each Time"
        public static let whatWasUsingMemory = "What Was Using Memory"
        public static let macAtThatMoment = "The Mac at That Moment"
        public static let showRawLines = "Show Raw Lines"
    }

    // MARK: - Memory Cleanup

    public enum Cleanup {
        public static let leftovers = "Leftovers"
        public static let everythingNow = "Everything Now"
        public static let devServers = "Dev Servers"
        public static let orphanedTools = "Orphaned Tools"
        public static let emulators = "Emulators & Browsers"
        public static let buildHelpers = "Build Helpers"
        public static let containers = "Containers"
        public static let editorHelpers = "Editor Helpers"
        public static let apps = "Apps on Your List"
        public static let liveSessions = "Live Sessions"
        public static let busyOrphans = "Include Busy Leftovers"
        public static let alsoQuit = "Also Quit"
        public static let other = "Other"
        public static let preview = "Preview"
        public static let closePrograms = "Close Programs"
        public static let options = "Options"
        public static let cleanup = "Cleanup"
        /// How the review says the apps it will quit without a tick: "2 apps will quit",
        /// "Close 1 Item now and Quit Opera, Docker?". Words, not names (they are not title style).
        public static let alsoActs = ReviewAlsoActs(singular: "app", plural: "apps", verb: "will quit",
                                                    confirmVerb: Names.Stop.quit)
        public static let stateReady = "Ready to Close"
        public static let stateWillQuit = "Will Be Asked to Quit"
        public static let stateKept = "Kept"
        public static let stateClosed = "Closed"
        public static let stateGone = "Already Gone"
        public static let stateNotApproved = "Left Out by You"
    }

    // MARK: - everything above, for the check

    /// Every name with the table it belongs to, for `agent-runner --probe-names`.
    public static var all: [(table: String, name: String)] {
        var rows: [(String, String)] = [("App", app)]
        rows += [Group.memory, Group.storage, Group.system, Group.history, Group.settings, Group.app]
            .map { ("Group", $0) }
        rows += [Screen.overview, Screen.activity, Screen.setup, Screen.monitor, Screen.memoryGuard,
                 Screen.memoryCleanup, Screen.disk, Screen.cachesAndBuilds, Screen.downloads,
                 Screen.tempAndAgents, Screen.timeMachine, Screen.spotlight, Screen.unusedApps, Screen.oldRecordings,
                 Screen.network, Screen.loginItems, Screen.reports, Screen.trends, Screen.undo,
                 Screen.memorySettings, Screen.storageSettings, Screen.notifications, Screen.schedule,
                 Screen.updates, Screen.howItWorks, Screen.support, Screen.turnOff, Screen.actions]
            .map { ("Screen", $0) }
        rows += [crisisReports, crisisReport, memoryReclaim, startupChanges].map { ("Shared", $0) }
        rows += [Startup.loginItem, Startup.launchAgent, Startup.launchDaemon, Startup.helperTool,
                 Startup.running, Startup.loaded, Startup.notLoaded, Startup.disabled, Startup.enabled,
                 Startup.leftover, Startup.possibleLeftover, Startup.notChecked, Startup.removed,
                 Startup.categoryApps, Startup.categoryBackground, Startup.categoryLeftovers,
                 Startup.categoryChanges, Startup.filterAdministrator, Startup.filterNotChecked].map { ("Startup", $0) }
        rows += [Report.memory, Report.storage].map { ("Report", $0) }
        rows += [NetworkScope.snapshot, NetworkScope.history].map { ("Network", $0) }
        rows += [State.upToDate, State.updateAvailable, State.developmentBuild].map { ("State", $0) }
        rows += [Scope.all, Scope.running, Scope.needsReview, Scope.failed].map { ("Scope", $0) }
        rows += [Category.apps, Category.tools, Category.system, Category.appsAndServices,
                 Category.singleProcesses].map { ("Category", $0) }
        rows += [Cache.nextBuild, Cache.turbo, Cache.buildOutput, Cache.vite, Cache.svelteKit, Cache.nuxt,
                 Cache.parcel, Cache.nodePackages, Cache.vendored, Cache.pythonCache, Cache.pythonEnvironment,
                 Cache.rustBuild, Cache.other, Cache.daily, Cache.deep].map { ("Cache", $0) }
        rows += [Download.documents, Download.images, Download.archives, Download.installers, Download.video,
                 Download.audio, Download.folders, Download.screenshots, Download.other,
                 Download.underThreeMonths, Download.threeToSixMonths, Download.sixToTwelveMonths,
                 Download.overAYear, Download.dateUnknown].map { ("Download", $0) }
        rows += [Temp.tempFolder, Temp.yourTempFolder, Temp.sharedTempFolder, Temp.claudeCode, Temp.codex,
                 Temp.claudeApp, Temp.nodeTools, Temp.otherTools, Temp.managedByMacOS].map { ("Temp", $0) }
        rows += [Kept.leftForOwner, Kept.conversationHistory, Kept.keepList, Kept.currentVersion]
            .map { ("Kept", $0) }
        rows += [StorageTab.projects, StorageTab.appCaches, StorageTab.developerTools, StorageTab.documents,
                 StorageTab.images, StorageTab.screenshots, StorageTab.archivesAndInstallers, StorageTab.media,
                 StorageTab.foldersAndOther, StorageTab.temporaryFiles, StorageTab.codingAgents,
                 StorageTab.diskImages, StorageTab.packageManagers, StorageTab.xcodeSimulators,
                 StorageTab.docker, StorageTab.toolCaches].map { ("Storage tab", $0) }
        rows += [Prune.pnpm, Prune.npm, Prune.brew, Prune.simulators, Prune.docker].map { ("Prune", $0) }
        rows += [ToolCacheName.pip, ToolCacheName.uv, ToolCacheName.cargo, ToolCacheName.gradle,
                 ToolCacheName.derivedData, ToolCacheName.bun, ToolCacheName.cipd, ToolCacheName.goModules,
                 ToolCacheName.androidSnapshots, ToolCacheName.aerials].map { ("Tool cache", $0) }
        rows += [Fence.fenced, Fence.notFenced].map { ("Fence", $0) }
        rows += Column.all.map { ("Column", $0) }
        rows += [("Fold", Fold.empty)]
        rows += JobKind.allCases.map { ("Task \($0.rawValue)", job($0)) }
        rows += EngineLog.allCases.map { ("Log \($0.rawValue)", log($0)) }
        rows += [Review.selectAll, Review.selectNone, Review.previewAgain, Review.preview, Review.stop, Review.history,
                 Review.showRawOutput, Review.showInFinder, Review.copyPath, Review.copyPaths].map { ("Review", $0) }
        rows += [Channel.heading, Channel.releases, Channel.beta, Channel.thisCopy, Channel.installBeta, Channel.rebuild].map { ("Channel", $0) }
        rows += [TimeMachine.removePermission, TimeMachine.permissionRowTitle].map { ("Time Machine", $0) }
        rows += [Raw.screen, Raw.searchPrompt, Raw.copy, Raw.noOutput, Raw.showAll, Raw.showOlder].map { ("Raw", $0) }
        rows += [Monitor.everything, Monitor.tools, Monitor.lens, Monitor.lensMemory, Monitor.lensEnergy, Monitor.lensDisk,
                 Monitor.name, Monitor.whatItIs, Monitor.memory, Monitor.cpu, Monitor.pid, Monitor.energy, Monitor.read,
                 Monitor.written, Monitor.ended, Monitor.refresh, Monitor.refreshNow, Monitor.every5, Monitor.every15,
                 Monitor.every60, Monitor.paused, Monitor.inspector, Monitor.showDetails, Monitor.whereYourMemoryIs,
                 Monitor.nothingInScope].map { ("Monitor", $0) }
        rows += [Stop.stop, Stop.quit, Stop.forceStop, Stop.leaveRunning, Stop.leftAlone, Stop.leftAloneOne].map { ("Stop", $0) }
        rows += [Guard.stopped, Guard.alerts, Guard.period, Guard.show, Guard.last7, Guard.last90, Guard.nothingToReport,
                 Guard.nothingHere, Guard.eventGone, Guard.whatHappened, Guard.theProgram, Guard.whyTheGuardDoesThis,
                 Guard.eachTime, Guard.whatWasUsingMemory, Guard.macAtThatMoment, Guard.showRawLines].map { ("Guard", $0) }
        rows += [Cleanup.leftovers, Cleanup.everythingNow, Cleanup.devServers, Cleanup.orphanedTools, Cleanup.emulators,
                 Cleanup.buildHelpers, Cleanup.containers, Cleanup.editorHelpers, Cleanup.apps, Cleanup.liveSessions,
                 Cleanup.busyOrphans, Cleanup.alsoQuit, Cleanup.other, Cleanup.preview, Cleanup.closePrograms, Cleanup.options, Cleanup.cleanup, Cleanup.stateReady, Cleanup.stateWillQuit, Cleanup.stateKept,
                 Cleanup.stateClosed, Cleanup.stateGone, Cleanup.stateNotApproved].map { ("Cleanup", $0) }
        rows += TokenWords.all.map { ("Token \($0.token)", $0.label) }
        return rows.map { (table: $0.0, name: $0.1) }
    }
}
