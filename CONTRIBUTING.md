# Contributing

Thanks for wanting to improve mac-analyzers. Ground rules keep it small:

## Licensing of contributions

The project is licensed **PolyForm Noncommercial 1.0.0** (see `LICENSE.md`),
and the author retains exclusive commercial-licensing rights. By submitting a
contribution you agree it is licensed under the project's license, and you
grant the author the right to include it in commercially-licensed copies.
If that's not acceptable, please open an issue instead of a PR — ideas are
welcome either way.

## Safety invariants (PRs that break these are declined)

1. Analyzers stay **read-only**. Cleaners stay **dry-run by default** —
   `--apply` / `--execute` is always an explicit opt-in.
2. The guard kills **dev tooling only** (its `KILLABLE_RE`); the protect list
   always wins; CPU is never a kill reason.
3. Process sweeps must keep the **live AI-session exemption** (descendants of
   running claude/codex processes are never touched).
4. Nothing auto-deletes user content: no volumes, no Time Machine backups,
   no documents. The sudoers rule stays scoped to one exact command.
5. Anything personal/machine-specific goes through `config.local.sh`
   (gitignored) — never hardcoded. `config.example.sh` documents new knobs.

## Practical checklist

- `bash -n` passes on every changed script.
- Run the changed script's dry-run and paste the (redacted) output in the PR.
- Interactive menu still works (`FORCE_INTERACTIVE=1 printf 'q\n' | ./script`).
- No usernames, hostnames, project names, or personal app lists in tracked
  files — `git grep -i` yourself before pushing.
- Match the existing style: `$HOME`-based paths, `section`/`group` helpers,
  markdown report output, launchd labels under `com.mac-analyzers.*`.

## Workflow

Branch from `development`, PR into `development`. `main` is the release line.
