# CLAUDE.md — mac-analyzers

Shell-script toolkit (bash 5, macOS-only, no build system, no dependencies).
Read `CONTRIBUTING.md` first — its **safety invariants are hard rules**:
analyzers read-only, cleaners dry-run by default, guard kills dev-tooling only,
protect list always wins, live AI-session exemption stays, personal values go
through `config.local.sh` (never hardcoded).

## Conventions

- `$HOME`-based paths everywhere; launchd plists are `__SUITE_DIR__`/`__HOME__`
  templates hydrated by `*-manage-agents.sh install`; labels `com.mac-analyzers.*`.
- Every user-facing script: interactive menu when run bare in a TTY
  (`FORCE_INTERACTIVE=1` to test), flags for automation, run-input logged.
- Reports → `~/system-reports/{memory,storage}/<YYYY-MM-DD>/`; `latest.md`
  symlink at suite root; logs at suite root.
- Verify changes: `bash -n` every touched script + run its dry-run and read the
  output. There is no test suite; the dry-run IS the test.

## Branches

`development` is the working branch and PR target; `main` is the release line.
Both are protected (code-owner review required for PRs; owner pushes directly).
