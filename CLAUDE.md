# CLAUDE.md — mac-analyzers

Shell-script toolkit (bash, macOS-only, no dependencies — every script MUST
run under the bash macOS ships, `/bin/bash` 3.2; see the bash rule below) plus one compiled
part: the SwiftUI menu-bar app in `app/` (SPM, Swift 6, macOS 26).
Read `CONTRIBUTING.md` first — its **safety invariants are hard rules**:
analyzers read-only, cleaners dry-run by default, guard kills dev-tooling only,
protect list always wins, live AI-session exemption stays, personal values go
through `config.local.sh` (never hardcoded).

## Conventions

- Repo root is `~/mac-analyzers`; run reports live inside it at `reports/`.
  The app BUNDLES the engine (`build.sh` copies `memory-analyzer/`,
  `storage-analyzer/`, `network-analyzer/`, `lib/` into
  `Contents/Resources/engine/`), and `AnalyzersPaths.suiteRoot` resolves the
  clone first, the bundle second — so a downloaded app works alone while a
  checkout stays the copy you edit. Config and reports are ALWAYS read from
  `$HOME/mac-analyzers/`, never from inside the bundle: every cleaner sources
  `${ANALYZERS_ROOT}/config.local.sh` and then `$HOME/mac-analyzers/config.local.sh`,
  user copy last so it wins.
  The pre-consolidation paths (`~/scripts`, `~/system-reports`) are RETIRED —
  never reintroduce them in code or docs.
- `$HOME`-based paths everywhere; launchd plists are
  `__SUITE_DIR__`/`__HOME__`/`__RUNNER__` templates hydrated by
  `*-manage-agents.sh install` (entry point: the app bundle's compiled
  `agent-runner`, `/Applications` copy preferred, plain-script fallback;
  user-edited schedules from the app's Schedule pane are preserved across
  reinstalls); labels `com.mac-analyzers.*`; plists keep
  `AbandonProcessGroup` + `AssociatedBundleIdentifiers=com.mac-analyzers.app`.
- Every user-facing script: interactive menu when run bare in a TTY
  (`FORCE_INTERACTIVE=1` to test), flags for automation, run-input logged.
- Reports → `~/mac-analyzers/reports/{memory,storage}/<YYYY-MM-DD>/`; `latest.md`
  symlink at suite root; logs at suite root. All gitignored.
- Notifications go through `lib/notify.sh`: app CLI
  (`/Applications/MacAnalyzers.app/Contents/MacOS/notify`, repo `app/` copy
  as fallback) → `alerter` → `osascript`;
  knobs `ANALYZERS_NOTIFIER` / `ANALYZERS_LOG_VIEWER` / `ANALYZERS_NOTIFY_TIMEOUT`.
- The app's Settings write ONLY the marked managed block in `config.local.sh`
  (user content outside markers untouched); memory saves kickstart the guard.
- **Bash 3.2 rule.** macOS ships bash 3.2 and an app's PATH has no Homebrew,
  so `#!/usr/bin/env bash` can land on 3.2 even on a Mac that has bash 5. A
  script may use bash 4+ features (associative arrays, `mapfile`, `declare
  -g`, `${x,,}`) ONLY behind a version check that re-execs into a newer bash
  when one exists and otherwise skips that part with a plain logged line —
  `memory-auto-clean.sh` is the model (`DEV_PASS_OK`). Verify every touched
  script's dry-run under BOTH `bash` and `/bin/bash`; force the old-bash path
  with `ANALYZERS_BASH_CANDIDATES=/nonexistent /bin/bash <script>`.
- **Checks and CI.** Every check lives in `scripts/check.sh` (`--list` names
  them; `--changed <a>..<b>` runs only what a range touched; names plus
  `--changed` narrows to those names). **The gate for our own pushes is this
  Mac, not GitHub:** the pre-push hook (`scripts/install-git-hooks.sh`) runs
  the script and refuses a push that fails, and `scripts/cut-release.sh`
  runs all of it before a release. A push starts NO workflow — the project
  is macOS-only, so the Mac is the one machine that can judge all of it, and
  a cloud run after the push could only repeat it. So: never
  `git push --no-verify`, and on a fresh clone run
  `scripts/install-git-hooks.sh` before the first push (without it nothing
  checks a push). The workflows (`.github/workflows/`) exist for PULL
  REQUESTS, whose authors lack the hook: `checks.yml` on Linux runs what
  Linux can judge (syntax, shellcheck, secrets, release-notes format,
  actionlint) and reports the engine tests and the app build as "not run";
  `mac.yml` runs those on a Mac runner (bash 3.2 syntax, engine tests,
  `swift build`) only when a pull request touches a script, a test or the
  app. Both only call `scripts/check.sh` and only verify. After changing a
  workflow, prove it on a pull request (or start it by hand once it is on
  `main`) and watch it to the end: `gh run watch <id> --exit-status`.
- **Warnings are defects, not noise.** A compiler or shellcheck warning says
  the code uses something in a way its documentation does not intend —
  usually because it was written from memory. Never hide, defer or
  suppress one to get a build through: look up the current documentation
  and fix the cause. A suppression (`@preconcurrency import`,
  `nonisolated(unsafe)`, `@unchecked Sendable`, `# shellcheck disable=`)
  needs a comment saying why it is the right design at that spot. New code
  adds none — check with a CLEAN build (`swift build --build-path
  <scratch>`), because an incremental build does not repeat warnings for
  files it did not recompile. **This is enforced:** every Swift target
  treats warnings as errors (`treatAllWarnings` in `app/Package.swift`), so
  `swift build`, `scripts/check.sh`, the pre-push gate, `scripts/package.sh`
  and GitHub's Mac run all fail on one; `scripts/check.sh lint` fails on any
  shellcheck warning, one file at a time. The single exception is
  `app/build.sh` installing on a person's own Mac (`MA_RELAX_WARNINGS=1`):
  people build with whatever Xcode they have, so a newer compiler's new
  warning must not block their install or update — it is printed, and
  `upgrade.command` reports the count. Never set that variable to get your
  own change through.
- Verify changes: `bash -n` every touched script + run its dry-run and read the
  output. The one automated suite is `memory-analyzer/tests/`; otherwise the
  dry-run IS the test. For the app:
  `cd app && swift build` (bundle assembly is `./app/build.sh` — no Xcode; it
  signs with an Apple Development identity when present, ad-hoc fallback, and
  installs to `/Applications/MacAnalyzers.app` — the canonical run location;
  the repo `app/` bundle is the build artifact / script-only fallback).

## Building features in the app

- SPM target map: `AnalyzersKit` (shared kernel — paths, log/report parsers,
  config bridge, launchd + schedule control, live stats, update checker) ·
  `NotifierKit` (UN center, delegate, distributed-notification bridge,
  login item, 6-hourly update watcher) ·
  `MenuBarFeature` / `SettingsFeature` (views) · `UIComponents` (shared
  tiles/pane headers) · `MacAnalyzersApp` (thin shell) · `NotifierCLI` (the
  bundled `notify` shim) · `AgentRunner` (the compiled launchd entry point —
  `execv`s the engine script for BTM attribution).
- A screen of settings (a `Form`: the Preferences panes, How It Works,
  Support) renders inside `PaneScaffold`
  (`SettingsFeature/Shared/PaneScaffold.swift`); a screen that shows data (a
  table, a list, a review) is a `DataScreen`
  (`SettingsFeature/Shared/DataScreen.swift`), which fills the window, carries
  the title and subtitle. A screen never draws its own empty, failed or
  loading state: it is `EmptyState` or `LoadingState`
  (`SettingsFeature/Shared/ScreenState.swift`: the system's
  `ContentUnavailableView` and `ProgressView`, filling the space the screen has
  left and centring in it, with the icon, title, description and the button
  that fixes it where one exists); `scripts/check.sh states` refuses a bare
  one. The main window is
  `SettingsFeature/Shell/`: `MainWindowView` over one `Navigator` (selection,
  a path per section, ONE back/forward history recorded only in its four
  mutators `select` / `push` / `setPath` / `open`); the sidebar is a plain
  `List` built from `SettingsFeature/Groups/<Group>Group.swift` — each group
  file owns its `SectionID`s, rows, screens, route payloads and deep-link
  aliases, and `Shell/SectionRegistry.swift` only fixes the group order, so
  parallel work edits one group file each. Screens navigate through the
  `Navigator` in the environment (`push(.memory(.dossier(…)))`,
  `open(target: "log:guardLog")`), never by posting a notification.
  The sidebar's visibility is ONE state, the split view's `columnVisibility` held by
  `MainWindowView` (remembered across launches): the toolbar button
  (`SidebarVisibility.swift`, a `Toggle` in the system's look, no accent colour), its tooltip
  and the View menu item (Control-Command-S, through `focusedSceneValue`) all derive from it.
  Both send `toggleSidebar:` through the responder chain, as the system's own button does, so
  the sidebar collapses inside the window and the window never changes size (`scripts/check.sh
  sidebar` toggles at 900 and 780 wide and fails on any frame change); if the sidebar has not
  moved shortly after, the button sets the state itself. The window's minimum width is on the
  content, never on the split view (a minimum there grows the window by the sidebar's width). And
  while the sidebar is hidden resting the pointer on the leading edge or the button shows
  it as an overlay over the content (`SidebarPeek.swift`; the content never resizes; in
  full screen the system's own edge reveal is left alone).
  `Shell/DeepLinkRouter.swift` resolves every target string (the URL scheme,
  `--pane` and the in-process `com.mac-analyzers.open-pane` notification all
  land there). No screen shows a log as text: what a task found or did is
  rows (a table, tabs, groups that open: see the levels rule below), read
  from the log by a parser in `AnalyzersKit`. The text a run printed is one
  level down, inside the app, as the shared raw-output screen
  (`Screens/Shared/RawOutput/RawOutputScreen.swift`, "Show Raw Output":
  search, copy, the exact lines); nothing opens another app to show output.
  Menu rows and components live in `MenuBarFeature/MenuComponents.swift`.
  The engine stays bash — the app is a control surface over the scripts +
  launchd, never a reimplementation.
- Old Recordings reads every place a recording app saves, not one folder: the
  sources are `lib/recording-sources.tsv` (read by `cleanup.sh` and by
  `RecordingSourceCatalog`; `agent-runner --probe-recording-sources` fails if they
  differ), each is a tab, and ONLY THE APP DISCOVERS a folder (never inside
  Documents, Desktop or Downloads before a click): the engine is told the paths in
  `ANALYZERS_RECORDING_SOURCES` and refuses the folders the Sources window refuses: a source must
  be inside the home folder (not the Library or a hidden folder) or on `/Volumes/<disk>/…`, checked on the path
  as written AND where it really leads (`RecordingFolderRule`; `rec_refusal` in `cleanup.sh`).
- The **Welcome flow** is its own `Window` scene (`id: "welcome"`, `Screens/Welcome/`), opened through the open-window signal like the main
  window (`SettingsOpener.open(target: "welcome")`, deep link `welcome`; `WelcomeRequest.open(.automatic|.continuing|.again)` says why).
  WHEN it opens by itself is `WelcomePlanner` (`AnalyzersKit/Setup/WelcomeStep.swift`): a new install (no `~/mac-analyzers/setup-state.json`,
  no settings file, no background job) gets every step and the window opens (the first launch); an update never takes focus at
  login: a step introduced after `seenVersion` (each step carries the release that FIRST had what it asks for, so an existing install is
  not re-onboarded) that is not satisfied, answered or merely informational (the guard preview) badges Setup, and Continue Setup… carries
  it out; a finished flow, a permission lost after an update, and anything when the defaults key `welcome.neverOpen` is set (the tools set
  it) get nothing. What is saved when the flow is shown is the newer of the release and the newest step's version, so a development build
  cannot loop. What each step shows is the SAME reading Setup uses (`SetupInputs`, `SetupItems`,
  `SystemSettingsHandoff`, `SetupActions`): never a second checker. A new install also marks the version it came with as seen for the
  What's New card (`whatsNew.seenVersion`). `agent-runner --probe-onboarding [--state …]` judges the rules; render a step inside the main window with
  `SnapshotRunner welcome:fixture:<fresh|upgraded|continuing>:<step>`, or the window's own content at its own size with
  `SnapshotRunner overview out.png --welcome <state>:<step> --size 560x680`. Turn Off › Remove from this Mac deletes
  `setup-state.json` (the app's memory of what it showed, not the person's records), so a reinstall is a new install.
- Every Storage task is one screen (`Screens/Storage/`): Preview, the
  preview's rows as tabs and groups in the shared review table, one Apply
  through `JobStore.apply(from:approved:)`, History and Show Raw Output; a
  finished run's screen shows the same tabs and groups
  (`StorageGroup.runResults`). `agent-runner --probe-storage <screen>`
  prints them, `--probe-storage-apply` proves tick-to-engine and
  `--probe-fence` proves the Spotlight fence marker.
- Verify: `cd app && swift build`, then `./app/build.sh` (rebuild + reinstall
  to /Applications) and relaunch the app to see it live. Drive navigation with
  `open -g "macanalyzers://pane/<target>"` — the URL scheme reaches a RUNNING
  app, unlike `--args --pane`, which macOS only delivers at launch. Nav cost is
  measured from `log show --predicate 'category == "nav"'`.
  **Look at a screen without taking over the Mac:**
  `app/.build/debug/SnapshotRunner <target> <out.png> [--size 1100x720] [--wait 3]`
  renders the REAL main window (real stores, real data) for any deep-link
  target into a PNG, in a window placed far outside every display (an
  `OffscreenWindow`, `app/Sources/ToolWindows`, a target only the tools use:
  AppKit moves a plain titled window back onto the main display when it is
  ordered in, so this type returns its frame unchanged and places itself
  again after ordering in) — it never activates, never shows in the Dock,
  never moves focus. Placement is enforced, not assumed: the window refuses
  to be ordered in when its frame is on a screen, checks the window server's
  bounds for it the moment it is ordered in, and every tool checks again
  before each capture; a window on a display, or one the window server will
  not confirm, prints why and exits 3 WITHOUT capturing, and each render
  prints the frame and bounds it was taken at. The picture is drawn from the
  window's own views (`OffscreenWindow.snapshotPNG`: the frame view, so title
  bar, toolbar, sidebar and content), because `screencapture -l` cannot image
  a window that is on no display; it needs no display and works with the
  screen locked. **It is partly invented, and a render is never evidence for
  these: judge the sidebar's colour, its selection, the legibility of anything
  on glass, and key-window states (an active window's selection, traffic
  lights and focus ring) on screen.** What the picture does that the real window
  does not: (1) the Liquid Glass sidebar is a flat stand-in colour
  (`underPageBackgroundColor`) with no blur, lens or edge, and only a glass
  surface taller than 100 pt is drawn (the toolbar's small groups draw
  themselves); (2) the sidebar's selected row is a rounded rectangle drawn by hand
  (white 14% on dark, black 10% on light), because the system's highlight comes
  out of this kind of draw as a solid black bar; (3) on a dark window every
  near-black pixel of the sidebar's table is recoloured white, because inside
  the glass its labels are vibrant masks (black with an alpha) that the glass
  would colour: this also recolours a label that is hard-coded black, so a
  contrast bug on a sidebar label cannot show in a render; (4) the window's
  appearance is set on the window and on each glass view before the draw, and
  the run loop is spun for 0.4 s so SwiftUI redraws under it, because a glass
  surface with nothing behind it chooses light; (5) the window is never key or
  active, so selection, traffic lights and controls draw in their inactive
  state; (6) no rounded outer corners, edge or shadow, a dimmed button has no
  bezel, and pixels are 1x. Parts are found by what they are (the close button's
  ancestor is the title bar, the glass's `contentView`, an `NSTableView`), never
  by a private class name, and a part that cannot be found is an error: the
  tool prints why and exits non-zero without writing a picture. `--view-tree`
  prints the view hierarchy. `--outline-probe snapshot` (in `scripts/check.sh
  outline`, dark and light) fails if the close button, a known sidebar label's
  text (right polarity), the selected row, the footer or the content is
  missing from the picture.
  Built by `swift build`, never bundled into the app. Use it while building a screen and
  before calling it done (the blueprint's screen acceptance bar requires
  it); the owner's screen is not a test fixture. It cannot click: anything
  interactive (a running job, a confirmation, the menu-bar panel) still
  needs an on-screen check, and those are asked for first.
  `agent-runner --probe-setup` prints Setup's rows (three tabs, each with its state, evidence and action) as text, read
  live from this Mac; `--probe-setup-fixtures` judges them on example states and `--probe-fda` is the Full Disk Access
  spot-check of the folders the product reads, as this program reads them. A Setup row is a READ (`SetupInputs`), and a
  row that only System Settings can change goes through `SystemSettingsHandoff`: the exact pane, which switch, watched and
  confirmed. `Setup/ProtectedPlaces.swift` is the list that check reads, as data.
  `agent-runner --probe-memory [--all]` prints the Monitor pane's memory
  census as text (where memory is + every process group with its total).
  The census is the ONE classifier: it gives every group its category AND its
  kind (`CensusGroup.kind`, from `memory-analyzer/rules/kinds.json` through
  `AnalyzersKit/Memory/Kinds/`); the app's screens read that field and never
  classify a process a second time. The guard script does not read it yet: it keeps its own `KILLABLE_RE` until the rules engine
  (phase B) replaces that, and its live-session exemption must first cover every
  agent in `lib/coding-agents.tsv`.
  `agent-runner --probe-kinds [--all]` prints every group's kind, the rule that
  decided it and what the guard may do, with the parity check against the guard
  script's own pattern; `--probe-kinds-fixture` is the same rules on stand-in
  processes, in the gate.
  `agent-runner --probe-job <kind> [--cancel-after <s>]` runs one tracked job
  headless through the same kernel the app uses (`AnalyzersKit/Jobs/`) and
  prints its lines, the log block it was matched to and how it ended.
  Cleaners run as a PREVIEW (dry run) only: `--apply` is refused against the
  real engine and exists solely for `--probe-job-script <test script>`.
- Jobs kernel rules (`AnalyzersKit/Jobs/`): one engine lane (jobs queue);
  `JobStore.enqueue` refuses `.apply` for cleaners — `apply(from: preview,
  approved:)` is the only constructor, so an unreviewed apply cannot be
  built; cancel terminates the whole descendant tree; engine scripts are
  executed directly (their own `#!/usr/bin/env bash`) with the launchd
  plists' PATH — never forced through `/bin/bash`, which is 3.2.
- Jobs on screen: `MacAnalyzersApp` owns the ONE `JobStore` and ONE
  `UpdateState` and injects both into the main window and the menu-bar panel;
  a screen never creates a store. Every button that starts an engine script
  enqueues a job (`ActionRunner` is no longer called from a screen) and a
  converted screen finds its job again by kind on appear (`Shared/JobAdoption`).
  A cleaner apply goes only through `JobStore.apply(from:approved:)` with an
  `ApprovedSet` — a list that cannot be written stops the apply. A finished
  preview is adopted again by a screen only while it is recent (15 minutes) and
  not dismissed (`JobStore.dismiss`), and Apply is never enabled past that.
  Activity (`Screens/Activity/`) is a day-grouped `List` ("Running now", one
  collapsible section per day, "Hasn't run yet") of every job plus every run in
  the engine logs, joined with the job index in
  `AnalyzersKit/Activity/ActivityJoin` so a run is listed once, with a row id
  built from log + banner + ordinal (never a file position). A row pushes the
  run's own screen (`Route.job(uuid)` for tracked runs, `Route.run(RunReference)`
  for logged ones); who started an untracked run is inferred from the run's
  own flags or its timing and is "Unknown" otherwise. "Needs review" means a
  store preview finished within `JobStore.reviewWindow` and not dismissed — the
  kernel's `apply(from:)` refuses anything older. Quitting with a job running
  asks (Stop and Quit / Quit and Let It Finish / Cancel) in
  `NotifierKit/AppDelegate+Quit.swift` (a quit macOS starts — logout, restart,
  shutdown — never asks; in-app Install refuses while a job runs). The job
  store's test hooks (`scriptOverride`, `outcomeOverride`, the clock, the schedule
  reader) are `@_spi(TestSupport)`: only `AgentRunner` and `SnapshotRunner`
  import that interface, `scripts/check.sh spi` fails if anything else does, and
  it is a compile-time wall between our own targets, not a runtime one. The
  app people install reads NO environment variable (`scripts/check.sh env`):
  a tool that never ships (`AgentRunner`, `SnapshotRunner`) reads it and
  hands the value in. Probes that judge themselves on stand-in data run in
  the gate (`scripts/check.sh probes`; add one to `PROBES` once it exits
  non-zero on a broken rule). For a
  scheduled replay the store reads the installed plist's arguments itself. The shell's `.status`
  toolbar item (`JobStatusToolbarItem`, attached to the split view, never to a
  stack) and the menu panel's `MenuJobsStrip` show the running job, and
  `job:<uuid>` opens it. Look at it headless with `SnapshotRunner jobs|activity:failed|
  activity:review|activity:collapsed|activity:run:<log>|job:<uuid> out.png`
  (`--fake-running`/`--fake-failed` start a throwaway test job). `agent-runner
  --probe-activity [--real]` prints the sections, `--probe-activity-ids` proves
  ids survive a log growing, `--probe-failures` prints the failure sentences, and
  `--probe-pid-recycle` proves a stop refuses a recycled pid.
- **Memory Guard's rules are data, and in this version they only watch.** `memory-analyzer/rules/{kinds,plan,protected}.json`
  are read by `AnalyzersKit/Rules/` (`GuardRules`: the plan plus the person's sparse `~/mac-analyzers/rules.local.json`;
  an unknown field makes that rule, or the whole local file, unusable and says so). `RulesEngine` looks at the census once a
  minute while the app runs and `RuleEvaluator` says what each rule would do; the only thing written is a would-have row
  in `reports/memory/rule-outcomes.jsonl`. NOTHING in the app stops, quits or signals anything: a rule that reads Acting is
  one the guard SCRIPT already carries out (the dev-tooling cap and the critical-pressure step), and the engine writes no
  row for it. The script reads from the app only `.guard-fallback.tsv` (`lib/guard-select.sh`: the Never Close names and paths and a
  pause, which can only NARROW what it does; the cap and the stop switches are `config.local.sh`'s alone) and its own `KILLABLE_RE`, and spares
  every live coding session of `lib/coding-agents.tsv` (`memory-analyzer/tests/guard-exemption-test.sh`). Acting rules and
  CONTRIBUTING's invariant text are a later phase. `agent-runner --check-rules`, `--compare-legacy [--real]` (the script's
  set against the engine's: the engine's must be inside) and `--rules-once` show it; `--probe-rules-fixture` judges it.
- **One period, one loader.** A screen with a period (Trends, Memory Guard) takes it from the shared
  `ReportPeriod` (`AnalyzersKit/History/`: 24 hours, 3, 7, 14, 30, 90 days, begun by `GuardHistory.periodStart`; a
  chart's bars are `TrendBuckets`: hourly for 24 hours, daily after) and shows it with `PeriodToolbar` in
  `SettingsFeature/Shared/PeriodMenu.swift`: a change starts its load with `.task(id: period)`, keys every cached read
  by the period (`LoadCoordinator` serves a key for seconds), keeps the old content in place and shows a small
  progress indicator beside the menu with the subtitle "Loading Last 3 Days…" (`periodSubtitle`). Render it with
  `SnapshotRunner trends:memory:24h out.png --then trends:memory:7d --load-delay 8` (`guard:period:3d` and
  `trends:<tab>:<24h|3d|7d|14d|30d|90d>` are the period links); `agent-runner --probe-trend-buckets` judges the buckets.
- **Native controls, native padding, one layout per component** (owner,
  2026-11-10, after three screenshots of v2.69.0: "stop fabricating and just
  use native … buttons"). A button is a `Button` with a system `buttonStyle`;
  a set of choices is a `Picker` with `.segmented`; search is `.searchable`;
  a toolbar item is a `ToolbarItem` holding a plain system control; a
  title-and-value row is `LabeledContent`; rows are `List`/`Form` rows with
  their default insets; spacing is the default `.padding()` and stack
  spacing. No hand-drawn capsules or backgrounds standing in for a control,
  no `.frame(width:)`/`maxWidth` or `lineLimit(1)` to force something to
  fit, no `ViewThatFits` that changes a component's shape with its state.
  When content does not fit, change WHAT is shown (a short name in the
  toolbar, the sentence in the tooltip and on the screen it opens). A
  component looks the same in every state — render each state to prove it.
  A fixed size is allowed only where it is the actual job (an icon tile, a
  chart), with a comment saying so.
- **One way to write a size, by where it is shown** (owner, 2026-11-13): `ByteSize.text(_, style)` and `ByteSize.rate`,
  never an ad-hoc format at a call site. The decimals are a MAXIMUM, never padding (exactly 5 GB is "5 GB", 5.4 is
  "5.4 GB", 18.63 is "18.63 GB"): chart axes and crosshair readouts (`.axis`) and figure lists in the style of Activity
  Monitor's footer (`.figure`) take up to two decimals in gigabytes; headline numbers (`.headline`) and table or list cells
  (`.cell`, also `MemorySize.text`) one, and none in megabytes; rates one decimal under 10 MB/s, none above.
- **Native does not mean plainer, and a fix must not take things away**
  (owner, 2026-11-10: "the icons, they're gone … you guys are just
  introducing regressions"). A control that names a kind of thing shows its
  icon AND its title (`Label(title, systemImage:)`) — find the native way to
  show both, never drop the icon to make the native control easy. Before
  replacing a screen or a control, list what the old one showed (icons,
  counts, colour, a state, a shortcut): the new one shows all of it, or the
  change says what was removed and why. Compare before and after renders for
  what disappeared, not only for what improved.
- **Toolbars adapt by priority, the way Activity Monitor's does.** For each
  screen decide what the person uses most there — it stays visible at every
  window width — what is secondary and moves into the system's overflow
  menu first, and let search collapse to its icon. Use toolbar placements,
  `visibilityPriority`, the system overflow and `.searchable`; nothing is
  ever clipped at the window edge. With the search field focused, one click
  anywhere else must take focus away and do what was clicked.
- **Categories are tabs, groups are rows that open — never one long list**
  (owner, 2026-11-10, after a run's results came up as about 300 rows in one
  flat list: "these should be tabs … just like the monitor … a cohesive and
  consistent scenario to apply uniformly"). The app has one way of going
  from many things to one, the same on every screen: the screen is a sidebar
  item; its categories (different kinds of thing) are the shared scope tabs
  with icon, title and count; inside a category, rows are grouped under the
  real thing they belong to (a project, an app, a day) as one parent row
  with its count and total that opens to its members; one thing is a row
  whose detail is the inspector or its own screen. The row model carries
  the category and the group as typed data — never recovered by splitting a
  title — and every level says how much is in it. Biggest or newest first;
  rows that are nothing (0 KB) fold into one closed row. One tabs control
  for the whole app: no second segmented control, chips, cards or button
  rows standing in for tabs. A filter (the same rows, fewer) is a toolbar
  menu or a search token, not a tab; a screen with one kind of thing has no
  tabs. A run's screen shows its results in the same categories and groups
  as the task's own screen. **The tabs are a bar directly under the
  toolbar, never toolbar items** (2026-11-11): in the toolbar the system
  sends a tab group to the `»` overflow as soon as a screen has its own
  buttons, whatever its placement or `visibilityPriority`; SwiftUI has no
  collapse-to-a-pop-up; macOS 27's tabs picker shows bare icons. So
  `scopeTabsToolbar(…)` (the name is historical) adds one
  `safeAreaBar(edge: .top)` holding `ScopeTabs`: icon, title and count,
  the selected tab distinct even in a window that is not in front; when
  the titles do not all fit, tabs give them up one at a time and none is
  ever hidden; a zero count is not drawn. Never measure widths by hand or
  swap in a menu. A screen's toolbar is for its actions, each with icon
  and title (only search may be an icon).
- **One table for rows that open: `OutlineTable`** (2026-11-11, after
  measuring every SwiftUI hierarchical control — `Table` with
  `DisclosureTableRow`, `Table(children:)`, `List` with `OutlineGroup`,
  `DisclosureGroup` rows or `Section(isExpanded:)` — logging AppKit's
  "reentrant operation in its NSTableView delegate. This warning will become
  an assert in the future." when all groups open or the rows are re-sorted
  in place; a flat SwiftUI `Table` re-sorted in place logs it too; the
  released app logged it on screen). Every table whose rows open to other
  rows, and every sortable table, is an `OutlineTable`
  (`UIComponents/OutlineTable/`): columns declared like `Table`, the caller
  sorts its own rows, and selection, open groups (`RememberedExpansion`,
  kept per screen), ticks and section headers are the screen's own
  bindings; cells are SwiftUI or plain text. Inside the component the
  system view is changed only from its updater and never while AppKit is
  calling in, and every write back to a binding that arises inside one of
  AppKit's callbacks (selection, open groups, sort) happens on the next main
  turn; a tick from a box or the Space key is an event, not a callback, and
  is delivered at once so ticks reach the screen in the order they were
  made — a change that breaks either rule is a defect even when no warning
  shows. It uses the system's standard row height (automatic row heights
  bring the warning back); a cell that needs more lines declares them.
  `scripts/check.sh outline` runs the two changes that used to warn
  (`scripts/outline-probe.sh` has the full set) and every case of the review
  table, and it refuses the SwiftUI hierarchical controls anywhere under
  `app/Sources`. A `List` is for a history whose rows
  push a screen: it never gains more than 200 rows in one update (newest
  200, then "Show Older"). A `DisclosureGroup` around ONE block of content
  (raw output, details) is fine and carries the comment
  `// one disclosed block, not rows` on the line above it. Need something the component does not do?
  Add it there — never a second grouped table. This is a deliberate
  departure from "SwiftUI controls only" in the rule above: the system's
  outline view is the platform's control for hierarchical data, wrapped
  once.
- v2.7.1 lesson: NEVER hoist a pane header outside the `Form` (it lands in
  the toolbar backdrop — light band, doubled title); no
  `.scrollEdgeEffectStyle(.hard)` in the Settings window;
  `.listSectionSpacing` is iOS-only.

## Branches, releases, upgrades

`development` is the working branch and PR target; `main` is the release line.
Both are protected (code-owner review required for PRs; owner pushes directly).

- ANY commit or merge on `main` SHIPS: the post-commit/post-merge hook
  (`scripts/release.sh`, installed by `scripts/install-git-hooks.sh`) pushes,
  builds `mac-analyzers-v<V>.tar.gz` via `git archive`, and creates the
  GitHub release with that version's `CHANGELOG.md` entry as its notes.
  Same-version merges no-op (tag already exists).
- Cut a release with `scripts/cut-release.sh <version|patch|minor|major>`
  (`--dry-run` to rehearse) — the ONE way to ship. It refuses to start
  without a What's New entry for the new version in `CHANGELOG.md` that
  passes `scripts/changelog-check.sh`, then bumps `VERSION` (single source
  of truth), pushes development, and merges development → main **in the
  main worktree** (`.composure/workspaces/main`) — never by switching the
  root checkout. Never bump `VERSION` by hand without releasing: 2.65–2.67
  were bumped on development and never reached anyone.
- `scripts/package.sh` builds the download for other people:
  `dist/MacAnalyzers-<V>.dmg` (app + Applications shortcut) and the matching
  `.zip` (what an installed copy downloads to update), from a re-signed
  COPY — it never installs and never changes the repo bundle's signature.
  Signing level is automatic: a keychain "Developer ID Application" identity
  (+ `MA_NOTARY_PROFILE` to notarize) when there is one, ad-hoc otherwise —
  NEVER the personal Apple Development identity, which carries the
  developer's email. Not attached to releases yet: a downloaded copy still
  needs the in-app first-run/update path (see the app blueprint).
- `CHANGELOG.md` is the single source for release notes: the GitHub release
  body AND the app's What's New (bundled by `build.sh`). Entries are written
  for someone who uses the app and has never seen the code — full sentences,
  what changed for THEM, no commit shorthand, no code names. The gate runs
  three times (cut-release, the pre-merge-commit hook on main, release.sh),
  so a hand-made merge cannot ship without one either.
- Installed clones update via `./upgrade.command` (Finder double-clickable):
  `git pull --ff-only` → `app/build.sh` (reinstalls to /Applications) → both
  `*-manage-agents.sh install` → relaunch the app (prefers the /Applications
  copy). It never touches `config.local.sh`.
- The app self-checks for releases (launch + every 6 h, `UpdateChecker`) and
  notifies once per new version; the Update pane and menu footer show
  installed vs latest and run `upgrade.command` on Install.
  A copy built from a git clone can also follow an update channel, picked on
  the Updates screen (`UpdateChannel`, saved in defaults): **Releases** (the
  default, as above), **Beta** (the newest commit on `development`, read with
  two public GitHub requests, a compare of the commit this copy was built from
  and the changelog on `development`; Install is `upgrade.command`, a `git pull
  --ff-only` on development plus a rebuild; only offered when the clone is on
  `development`) and **This Copy** (the clone itself, uncommitted changes
  included, read with local `git`; "Rebuild from This Copy" runs
  `rebuild.command`, the same build without the pull). The build stamps
  `MABuildCommit`, `MABuildBranch`, `MABuildTreeHash` (`scripts/tree-hash.sh`:
  "clean", a hash of the uncommitted changes and the bytes of untracked files,
  or "unknown"; the app recomputes the same value) and `MABuildVersion`.
  **Reading a clone must never run a program the clone names** and a failure
  is never "clean": every git call (`SourceClone`, `scripts/tree-hash.sh`) turns
  off fsmonitor, hooks and attributes (`--attr-source` the empty tree), empties
  every filter and diff driver the clone defines, ignores the person's global
  and system configuration, runs with a minimal environment, and asks for
  untracked files whatever the settings say; settings go in as
  `GIT_CONFIG_COUNT`/`KEY`/`VALUE` pairs (a driver name may contain "="),
  submodules are never entered (`--ignore-submodules=dirty`; a clone with a
  submodule and uncommitted work is unknown), a partial clone never fetches
  (`GIT_NO_LAZY_FETCH`), a non-empty `.git/info/attributes` is unknown, and
  git failing makes the state "unknown". A downloaded app, or a Mac without the developer tools,
  runs no git at all (`GitTools`, so Apple's install dialog never appears) and
  shows Releases only. A development build is never named for the release:
  `BuildInfo.version` is the next patch, `-dev.<commits since the tag>`,
  `+<short commit>` and `.local` (or `.unknown`) for uncommitted changes, by
  semantic-versioning precedence (`2.69.2 < 2.69.3-dev.42 < 2.69.3`); Beta and
  This Copy decide "newer" by commit and fingerprint, never by that string.
  Nothing fetches into the person's clone and nothing installs by itself;
  `agent-runner --probe-channels` (including a hostile clone that writes a
  marker if anything runs) and `--probe-versions` prove it.
