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
  `StorageCleanView`, `ReapLogView`, `ForensicsDetailView`) with
  "Open in TextEdit" as the raw escape hatch; menu rows/components live in
  `MenuBarFeature/MenuComponents.swift`. The engine stays bash — the app is a
  control surface over the scripts + launchd, never a reimplementation.
- Verify: `cd app && swift build`, then `./app/build.sh` (rebuild + reinstall
  to /Applications) and relaunch the app to see it live. Drive navigation with
  `open -g "macanalyzers://pane/<target>"` — the URL scheme reaches a RUNNING
  app, unlike `--args --pane`, which macOS only delivers at launch. Nav cost is
  measured from `log show --predicate 'category == "nav"'`.
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
