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
- `$HOME`-based paths everywhere; launchd plists are `__SUITE_DIR__`/`__HOME__`
  templates hydrated by `*-manage-agents.sh install`; labels `com.mac-analyzers.*`;
  plists keep `AbandonProcessGroup` + `AssociatedBundleIdentifiers=com.mac-analyzers.app`.
- Every user-facing script: interactive menu when run bare in a TTY
  (`FORCE_INTERACTIVE=1` to test), flags for automation, run-input logged.
- Reports → `~/mac-analyzers/reports/{memory,storage}/<YYYY-MM-DD>/`; `latest.md`
  symlink at suite root; logs at suite root. All gitignored.
- Notifications go through `lib/notify.sh`: app CLI
  (`app/MacAnalyzers.app/Contents/MacOS/notify`) → `alerter` → `osascript`;
  knobs `ANALYZERS_NOTIFIER` / `ANALYZERS_LOG_VIEWER` / `ANALYZERS_NOTIFY_TIMEOUT`.
- The app's Settings write ONLY the marked managed block in `config.local.sh`
  (user content outside markers untouched); memory saves kickstart the guard.
- Verify changes: `bash -n` every touched script + run its dry-run and read the
  output. There is no test suite; the dry-run IS the test. For the app:
  `cd app && swift build` (bundle assembly is `./app/build.sh` — no Xcode).

## Branches

`development` is the working branch and PR target; `main` is the release line.
Both are protected (code-owner review required for PRs; owner pushes directly).
