# AGENTS.md

<!-- [PORTABLE-OPERATIONAL] -->

Bash 5 / macOS shell suites (`memory-analyzer/`, `storage-analyzer/`, shared
`lib/notify.sh`) — no deps, no test framework: `bash -n` plus the script's own
dry-run is the verification loop. `app/` is the one compiled part: a SwiftUI
menu-bar app (SPM, Swift 6, macOS 26) assembled by `app/build.sh` without
Xcode — verify with `cd app && swift build`. Reports/logs write to
`reports/{memory,storage}/` inside the repo (gitignored).

Hard rules (from CONTRIBUTING.md, enforced in review):

1. Analyzers are read-only; cleaners are dry-run unless `--apply`/`--execute`.
2. Process-killing code: allowlist (dev tooling) minus protect list (always
   wins); never kill on CPU; never remove the live AI-session exemption.
3. No personal/machine data in tracked files — user-specific values belong in
   `config.local.sh` (gitignored), documented in `config.example.sh`.
4. launchd plists stay `__SUITE_DIR__`/`__HOME__` templates (labels
   `com.mac-analyzers.*`, `AbandonProcessGroup` + `AssociatedBundleIdentifiers`
   kept); the manage scripts hydrate them at install.
5. The app's Settings own ONLY the marked managed block in `config.local.sh`;
   user content outside the markers is never touched.

Work from `development`; PRs target `development`; `main` is releases.
