# CLAUDE.md — mac-analyzers

Shell-script toolkit (bash 5, macOS-only, no dependencies) plus one compiled
part: the SwiftUI menu-bar app in `app/` (SPM, Swift 6, macOS 26).
Read `CONTRIBUTING.md` first — its **safety invariants are hard rules**:
analyzers read-only, cleaners dry-run by default, guard kills dev-tooling only,
protect list always wins, live AI-session exemption stays, personal values go
through `config.local.sh` (never hardcoded).

## Conventions

- Repo root is `~/mac-analyzers`; run reports live inside it at `reports/`.
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
- Verify changes: `bash -n` every touched script + run its dry-run and read the
  output. There is no test suite; the dry-run IS the test. For the app:
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
- Every settings pane renders inside `PaneScaffold`
  (`SettingsFeature/PaneScaffold.swift`); the sidebar is a brand card +
  CONFIGURE / SCHEDULE / OBSERVE sections + About/Update; every log gets a
  STRUCTURED pane (chips/cards/tables — see `GuardLogView`, `LoginItemsView`,
  `StorageCleanView`, `ReapLogView`, `ForensicsDetailView`) with
  "Open in TextEdit" as the raw escape hatch; menu rows/components live in
  `MenuBarFeature/MenuComponents.swift`. The engine stays bash — the app is a
  control surface over the scripts + launchd, never a reimplementation.
- Verify: `cd app && swift build`, then `./app/build.sh` (rebuild + reinstall
  to /Applications) and relaunch the app to see it live.
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
  GitHub release. Same-version merges no-op (tag already exists).
- Cut a release: bump `VERSION` (single source of truth) on `development`,
  then merge development → main **in the main worktree**
  (`.composure/workspaces/main`) — never by switching the root checkout.
- Installed clones update via `./upgrade.command` (Finder double-clickable):
  `git pull --ff-only` → `app/build.sh` (reinstalls to /Applications) → both
  `*-manage-agents.sh install` → relaunch the app (prefers the /Applications
  copy). It never touches `config.local.sh`.
- The app self-checks for releases (launch + every 6 h, `UpdateChecker`) and
  notifies once per new version; the Update pane and menu footer show
  installed vs latest and run `upgrade.command` on Install.
