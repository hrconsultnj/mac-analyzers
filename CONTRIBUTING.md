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
   running claude/codex processes are never touched). One narrow, opt-in
   exception: with `ANALYZERS_DEV_REAP_SESSION_SERVERS=1` the dev pass may
   stop a dev server such a session left running in the background once
   nothing has used it for `ANALYZERS_DEV_SERVER_IDLE_MIN` — never its MCP
   servers, never a command the session is waiting on.
   One more opt-in, container-level use of the live-session criterion: with
   `ANALYZERS_DEV_STOP_IDLE_STACKS=1` the dev pass may `docker stop` (never
   remove; never volumes, images or networks) the containers of a stack whose
   owning project has had no live AI session or interactive terminal in it for
   `ANALYZERS_STACK_IDLE_MIN`. Unmapped stacks and `ANALYZERS_STACK_PROTECT` are never stopped, and it
   never starts or signals Docker.
4. Nothing auto-deletes user content: no volumes, no Time Machine backups,
   no documents. The sudoers rule stays scoped to one exact command.
5. Anything personal/machine-specific goes through `config.local.sh`
   (gitignored) — never hardcoded. `config.example.sh` documents new knobs.

## Practical checklist

- `bash -n` passes on every changed script — and so does `/bin/bash -n`.
  macOS ships bash 3.2: run the dry-run under `/bin/bash` too. Anything that
  needs bash 4+ goes behind a version check that falls back gracefully.
- Run the changed script's dry-run and paste the (redacted) output in the PR.
- Interactive menu still works (`FORCE_INTERACTIVE=1 printf 'q\n' | ./script`).
- No usernames, hostnames, project names, or personal app lists in tracked
  files — `git grep -i` yourself before pushing.
- Match the existing style: `$HOME`-based paths, `section`/`group` helpers,
  markdown report output, launchd labels under `com.mac-analyzers.*`.

## Workflow

**Fork the repo, branch from `development`, and open your PR against
`development`** — never `main`. `main` is the release line: any commit that
lands on it ships a release (a git hook builds the tarball and publishes it),
so nothing goes there except release merges, and those are made by
`scripts/cut-release.sh`, which will not ship a version that has no What's New
entry in `CHANGELOG.md`. If your change is something a user would notice, add
a line to the top entry there — in plain sentences, for someone who has never
seen the code. Both branches are protected;
code-owner review is required before merge.

- **App/UI PRs** (`app/`): describe what changed visually — a screenshot of
  the affected menu tab or settings pane beats a paragraph — and confirm
  `cd app && swift build` is green.
- **Engine PRs** (scripts): the safety invariants above are the review bar,
  and the practical checklist applies (dry-run output in the PR body).
