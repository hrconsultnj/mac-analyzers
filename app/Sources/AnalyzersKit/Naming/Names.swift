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
        public static let diskImages = "Disk Images"
        public static let ready = "Ready"
        public static let tooRecent = "Too Recent"
        public static let inUse = "In Use"
        public static let protected = "Protected"
        public static let notYours = "Not Yours"
        public static let leftAlone = "Left Alone"
        public static let sizedOnly = "Sized Only"
        public static let cleared = "Cleared"
        public static let failed = "Failed"
    }

    /// Whether Spotlight is kept out of a folder.
    public enum Fence {
        public static let fenced = "Fenced"
        public static let notFenced = "Not Fenced"
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

        /// Every title above, for the check.
        public static let all = [name, size, memory, cpu, pid, whatItIs, finding, state, kind, belongsTo,
                                 administrator, total, downloaded, uploaded, share, running, items, removed]
    }

    // MARK: - the closed row that holds what is empty

    /// The one closed row at the end of a level that folds the rows with nothing in
    /// them; `OutlineFolding` and every review table use this name.
    public enum Fold {
        public static let empty = "Nothing to Free"
    }

    // MARK: - lookups by type

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
        case .recordings: "Old Recordings"
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
        case .forensics: crisisReports
        }
    }

    // MARK: - the shared review, raw output and run screens

    public enum Review {
        public static let selectAll = "Select All"
        public static let selectNone = "Select None"
        public static let previewAgain = "Preview Again"
    }

    public enum Raw {
        public static let screen = "Raw Output"
        public static let searchPrompt = "Search Output"
        public static let copy = "Copy"
        public static let noOutput = "No Output Was Kept"
        public static let showAll = "Show All"
        public static let showOlder = "Show Older"
    }

    // MARK: - everything above, for the check

    /// Every name with the table it belongs to, for `agent-runner --probe-names`.
    public static var all: [(table: String, name: String)] {
        var rows: [(String, String)] = [("App", app)]
        rows += [Group.memory, Group.storage, Group.system, Group.history, Group.settings, Group.app]
            .map { ("Group", $0) }
        rows += [Screen.overview, Screen.activity, Screen.setup, Screen.monitor, Screen.memoryGuard,
                 Screen.memoryCleanup, Screen.disk, Screen.cachesAndBuilds, Screen.downloads,
                 Screen.tempAndAgents, Screen.timeMachine, Screen.spotlight, Screen.unusedApps,
                 Screen.network, Screen.loginItems, Screen.reports, Screen.trends, Screen.undo,
                 Screen.memorySettings, Screen.storageSettings, Screen.notifications, Screen.schedule,
                 Screen.updates, Screen.howItWorks, Screen.support, Screen.turnOff, Screen.actions]
            .map { ("Screen", $0) }
        rows += [crisisReports, crisisReport, memoryReclaim, startupChanges].map { ("Shared", $0) }
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
                 Temp.claudeApp, Temp.nodeTools, Temp.otherTools, Temp.managedByMacOS, Temp.diskImages,
                 Temp.ready, Temp.tooRecent, Temp.inUse, Temp.protected, Temp.notYours, Temp.leftAlone,
                 Temp.sizedOnly, Temp.cleared, Temp.failed].map { ("Temp", $0) }
        rows += [Fence.fenced, Fence.notFenced].map { ("Fence", $0) }
        rows += Column.all.map { ("Column", $0) }
        rows += [("Fold", Fold.empty)]
        rows += JobKind.allCases.map { ("Task \($0.rawValue)", job($0)) }
        rows += EngineLog.allCases.map { ("Log \($0.rawValue)", log($0)) }
        rows += [Review.selectAll, Review.selectNone, Review.previewAgain].map { ("Review", $0) }
        rows += [Raw.screen, Raw.searchPrompt, Raw.copy, Raw.noOutput, Raw.showAll, Raw.showOlder].map { ("Raw", $0) }
        rows += TokenWords.all.map { ("Token \($0.token)", $0.label) }
        return rows.map { (table: $0.0, name: $0.1) }
    }
}
