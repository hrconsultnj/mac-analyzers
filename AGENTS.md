# AGENTS.md

<!-- [PORTABLE-OPERATIONAL] -->

Bash 5 / macOS shell suites (`memory-analyzer/`, `storage-analyzer/`, shared
`lib/notify.sh`) — no deps, no test framework: `bash -n` plus the script's own
dry-run is the verification loop. `app/` is the one compiled part: a SwiftUI
menu-bar app (SPM, Swift 6, macOS 26) assembled by `app/build.sh` without
Xcode — verify with `cd app && swift build`. `build.sh` signs with an Apple
Development identity when present (ad-hoc fallback; signing ≠ notarization)
and installs to `/Applications/MacAnalyzers.app` — the canonical run
location; the repo `app/` bundle is build artifact + fallback, and
`lib/notify.sh`, the launchd entry points, `upgrade.command`, and the login
item all prefer `/Applications`. Reports/logs write to
`reports/{memory,storage}/` inside the repo (gitignored).

Hard rules (from CONTRIBUTING.md, enforced in review):

1. Analyzers are read-only; cleaners are dry-run unless `--apply`/`--execute`.
2. Process-killing code: allowlist (dev tooling) minus protect list (always
   wins); never kill on CPU; never remove the live AI-session exemption.
3. No personal/machine data in tracked files — user-specific values belong in
   `config.local.sh` (gitignored), documented in `config.example.sh`.
4. launchd plists stay `__SUITE_DIR__`/`__HOME__`/`__RUNNER__` templates
   (labels `com.mac-analyzers.*`, `AbandonProcessGroup` +
   `AssociatedBundleIdentifiers` kept); the manage scripts hydrate them at
   install — entry point is the app bundle's compiled `agent-runner` (BTM
   attribution) with plain-script fallback, and user-customized schedules
   (the app's Schedule pane) are preserved across reinstalls.
5. The app's Settings own ONLY the marked managed block in `config.local.sh`;
   user content outside the markers is never touched.

App feature work: SPM targets — AnalyzersKit (shared kernel: paths, parsers,
config bridge, launchd/schedule control, update checker) · NotifierKit
(notifications) · MenuBarFeature / SettingsFeature (views) · UIComponents
(shared tiles/headers) · MacAnalyzersApp (thin shell) · NotifierCLI (`notify`
shim) · AgentRunner (compiled launchd doorway — execv's the engine script).
Every settings pane uses PaneScaffold (sidebar: brand card + CONFIGURE /
SCHEDULE / OBSERVE sections; every log is a structured pane, TextEdit as
escape hatch); menu rows live in MenuComponents.swift; the engine stays
bash — the app is a control surface, never a reimplementation. Verify
`cd app && swift build`, then `./app/build.sh` (rebuild + reinstall to
/Applications) and relaunch. UI traps (v2.7.1): pane header stays INSIDE the
Form; no `.scrollEdgeEffectStyle(.hard)` in the Settings window;
`.listSectionSpacing` is iOS-only.

Work from `development`; PRs target `development`; `main` is releases — ANY
commit/merge on main SHIPS (scripts/release.sh hook: push + tarball
`mac-analyzers-v<V>.tar.gz` + GitHub release from `VERSION`). Cut a release by
bumping VERSION on development, then merging development → main in the main
worktree (`.composure/workspaces/main`). Installed clones upgrade via
`./upgrade.command` (pull --ff-only, rebuild app, refresh agents, relaunch;
`config.local.sh` untouched).
