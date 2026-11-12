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
- Every form screen renders inside `PaneScaffold`
  (`SettingsFeature/Shared/PaneScaffold.swift`). The main window is
  `SettingsFeature/Shell/`: `MainWindowView` over one `Navigator` (selection,
  a path per section, ONE back/forward history recorded only in its four
  mutators `select` / `push` / `setPath` / `open`); the sidebar is a plain
  `List` built from `SettingsFeature/Groups/<Group>Group.swift` — each group
  file owns its `SectionID`s, rows, screens, route payloads and deep-link
  aliases, and `Shell/SectionRegistry.swift` only fixes the group order, so
  parallel work edits one group file each. Screens navigate through the
  `Navigator` in the environment (`push(.memory(.dossier(…)))`,
  `open(target: "log:guardLog")`), never by posting a notification.
  `Shell/DeepLinkRouter.swift` resolves every target string (the URL scheme,
  `--pane` and the in-process `com.mac-analyzers.open-pane` notification all
  land there). Every log gets a
  STRUCTURED pane (chips/cards/tables — see `GuardLogView`, `LoginItemsView`,
  `ReapLogView`, `ForensicsDetailView`) with
  "Open in TextEdit" as the raw escape hatch; menu rows/components live in
  `MenuBarFeature/MenuComponents.swift`. The engine stays bash — the app is a
  control surface over the scripts + launchd, never a reimplementation.
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
  target into a PNG, in a window placed outside every display — it never
  activates, never shows in the Dock, never moves focus. Built by `swift
  build`, never bundled into the app. Use it while building a screen and
  before calling it done (the blueprint's screen acceptance bar requires
  it); the owner's screen is not a test fixture. It cannot click: anything
  interactive (a running job, a confirmation, the menu-bar panel) still
  needs an on-screen check, and those are asked for first.
  `agent-runner --probe-setup` prints the Setup checklist as text.
  `agent-runner --probe-memory [--all]` prints the Monitor pane's memory
  census as text (where memory is + every process group with its total).
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
