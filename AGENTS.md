# AGENTS.md

<!-- [PORTABLE-OPERATIONAL] -->

Bash 5 / macOS shell-script toolkit. No build, no deps, no test framework —
`bash -n` plus the script's own dry-run is the verification loop.

Hard rules (from CONTRIBUTING.md, enforced in review):

1. Analyzers are read-only; cleaners are dry-run unless `--apply`/`--execute`.
2. Process-killing code: allowlist (dev tooling) minus protect list (always
   wins); never kill on CPU; never remove the live AI-session exemption.
3. No personal/machine data in tracked files — user-specific values belong in
   `config.local.sh` (gitignored), documented in `config.example.sh`.
4. launchd plists stay `__SUITE_DIR__`/`__HOME__` templates; the manage
   scripts hydrate them at install.

Work from `development`; PRs target `development`; `main` is releases.
