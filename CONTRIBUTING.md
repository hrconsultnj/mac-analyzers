# Contributing

Thanks for wanting to improve Sparehold. Ground rules keep it small:

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
   no documents. The one exception is Time Machine's **local** snapshots on
   this Mac: the scheduled deep clean may thin them, and only after the person
   explicitly gave the permission (Setup, Time Machine, "Allow…"); the backup
   disk is never touched. The sudoers rule stays scoped to one exact command.
   Recordings are moved to the Trash only on request, from a reviewed list, and
   never from a folder that syncs to the cloud or that another app indexes.
5. Anything personal/machine-specific goes through `config.local.sh`
   (gitignored) — never hardcoded. `config.example.sh` documents new knobs.

## Practical checklist

- `bash -n` passes on every changed script — and so does `/bin/bash -n`.
  macOS ships bash 3.2: run the dry-run under `/bin/bash` too. Anything that
  needs bash 4+ goes behind a version check that falls back gracefully.
- No compiler or shellcheck warnings in what you change — the build and
  `scripts/check.sh` fail on one. A warning is a defect: fix its cause from
  the current documentation rather than suppressing it, and say why if a
  suppression really is the right design.
- `scripts/check.sh` passes (syntax, shellcheck, secrets sweep, release-notes
  format, tests; `scripts/install-git-hooks.sh` runs it before every push).
  Pull requests run the same script on GitHub: a Linux machine runs the
  checks that do not need a Mac, and a Mac runs the engine tests and the app
  build when your change touches a script, a test or the app. Running
  `scripts/check.sh` on your own Mac first tells you the same thing sooner.
- Run the changed script's dry-run and paste the (redacted) output in the PR.
- Interactive menu still works (`FORCE_INTERACTIVE=1 printf 'q\n' | ./script`).
- No usernames, hostnames, project names, or personal app lists in tracked
  files — `git grep -i` yourself before pushing.
- Match the existing style: `$HOME`-based paths, `section`/`group` helpers,
  markdown report output, launchd labels under `com.sparehold.*`.
  An existing `~/mac-analyzers` checkout remains the data and the engine
  until the person moves it. Do not move or delete that folder.

## How a contribution flows

1. **Fork** the repository and **branch from `development`**.
2. Make the change, then run `scripts/check.sh` on your Mac. It is the same
   script the pull request runs, so a green run here is a green run there.
3. Open a **pull request to `development`**. A pull request aimed at `main`
   fails its first check and needs its base branch changed.
4. **Checks run on GitHub.** The shell, lint and secrets checks run on Linux;
   the engine tests and the app build run on a Mac when you touch a script,
   a test or the app. A pull request that changes what people see also needs
   its line under `## Next` in `CHANGELOG.md`, and the PR template says how it
   is written. If nobody using the app would notice the change, a maintainer
   adds the `no-changelog` label.
5. **Review.** A maintainer reviews it against the safety rules below.
6. **It lands in the next release.** Merging into `development` does not
   publish anything: releases and betas are cut by the maintainer, on their
   own Mac, with `scripts/cut-release.sh`. No GitHub workflow publishes a
   release.

## Workflow

**Fork the repo, branch from `development`, and open your PR against
`development`** — never `main`. `main` is the release line: any commit that
lands on it ships a release (a git hook builds the tarball and publishes it),
so nothing goes there except release merges, and those are made by
`scripts/cut-release.sh`, which will not ship a version that has no What's New
entry in `CHANGELOG.md`. If your change is something a user would notice, add
a line under `## Next` at the top of that file — in plain sentences, for someone who has never
seen the code. Both branches are protected;
code-owner review is required before merge.

**Two channels, two scripts.** People follow the public release or a beta, as
in TestFlight. `scripts/cut-release.sh` publishes a release (`vN.N.N`, from
`main`). `scripts/cut-beta.sh` publishes a beta: it tags the current commit of
`development` `vX.Y.Z-beta.N` (X.Y.Z is the next version after the latest
release; N counts up) and creates a GitHub pre-release with the `## Next`
notes. It never touches `main` or `VERSION`, and GitHub never offers a
pre-release as the latest release, so only the Beta channel sees it. Rehearse
with `scripts/cut-beta.sh --dry-run`. A beta tag is never counted as a release
(`app/release-tag.sh` ignores every tag with a `-`).

- **App/UI PRs** (`app/`): describe what changed visually — a screenshot of
  the affected menu tab or settings pane beats a paragraph — and confirm
  `cd app && swift build` is green.
- **Engine PRs** (scripts): the safety invariants above are the review bar,
  and the practical checklist applies (dry-run output in the PR body).
