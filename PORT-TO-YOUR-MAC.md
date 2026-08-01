# For Claude: adapting this suite to a new Mac

You (Claude) have been handed this folder to set up for YOUR user. It was built
on the author's M2 Mac Studio (32 GB, macOS 26) — everything is designed to
port, but calibrate it, don't just install it.

## What this is

Two sibling suites (the engine) + shared plumbing + the native app (the face):
- `memory-analyzer/` — RAM report (`analyze.sh`), always-on spike guard, daily
  orphan reaper, manual "free RAM now" reclaim. See its README.
- `storage-analyzer/` — disk report, interactive deep clean, scheduled
  auto-clean, Time Machine local-snapshot reclaim. See its README.
- `lib/notify.sh` — the notifier every script sources: menu-bar app's CLI →
  `alerter` → plain `osascript` banner, whichever is present.
- `app/` — the "Mac Analyzers" SwiftUI menu-bar app, the suite's face (built
  in step 10). `extras/swiftbar-plugin/` is the fallback surface for
  script-only / headless setups.
- Reports and logs land inside the repo at `reports/{memory,storage}/`
  (gitignored).
- The suites' READMEs carry the operating principles (free RAM = wasted RAM;
  watch pressure+swap, never "free"; RAM is vacated, not cleaned). Measure
  this machine's own baselines with `analyze.sh` — never assume another
  machine's numbers.

## Port checklist (do these in order)

1. **Read both READMEs**, then run both `analyze.sh` scripts — read-only, and
   the reports teach you this machine before you change anything.
2. **Paths are already portable**: all shell scripts use `$HOME`; the launchd
   plists are `__SUITE_DIR__`/`__HOME__` templates that `*-manage-agents.sh
   install` hydrates for the current user+location at install time, and
   `sudoers-install` substitutes the current username. Install FROM wherever
   the folder lands (path-independent), but keep the folder somewhere
   permanent first — launchd will point at it. The author keeps it at
   `~/mac-analyzers`; reports/logs write into `reports/{memory,storage}/`
   inside the folder.
3. **Calibrate the guard** to this machine's RAM (defaults assume 32 GB):
   set `GUARD_HARD_CAP_MB` (default 6144 ≈ RAM/5) and the spike thresholds
   (`GUARD_SPIKE_MB`, `GUARD_SPIKE_MIN_MB`) in `config.local.sh` — the
   defaults live in `memory-guard.sh`, the overrides belong in config. On a
   16 GB machine, halve them. (The app's Settings → Memory pane edits the
   same values with sliders, if you build it.)
4. **Rebuild the protect list for YOUR user.** The base `PROTECT_RE` in
   memory-guard.sh, memory-auto-clean.sh, and memory-reclaim.sh covers meeting
   apps, browsers, editors, and container engines generically. Ask your user
   what else must never be killed (screen recorders, dictation tools,
   home-automation daemons) and append it via `ANALYZERS_PROTECT_EXTRA` in
   `config.local.sh` — one knob feeds all three scripts.
5. **Same for the reclaim app-quit list** (`ANALYZERS_RECLAIM_APPS`) and the
   curated stale-app list (`ANALYZERS_STALE_APPS`) — both in
   `config.local.sh`; the in-script defaults are the author's apps, not
   universal.
6. **Schedule times**: storage daily 08:00, memory daily 08:30 (defaults).
   Once the app is built (step 10), the Settings → Schedule pane edits these
   with time pickers and the installers preserve the customization across
   reinstalls and upgrades; on a script-only setup, adjust the plist
   templates before installing if they collide with your user's hours.
7. Dry-run everything once with your user watching (`auto-clean` scripts are
   dry-run by default; double-clicking any script opens an interactive menu),
   THEN `./memory-analyzer/memory-manage-agents.sh install` and
   `./storage-analyzer/storage-manage-agents.sh install`.
8. Optional: `./storage-analyzer/storage-manage-agents.sh sudoers-install`
   (real terminal; asks for password) enables passwordless Time Machine
   snapshot thinning — read the sudoers file first; it's scoped to one exact
   command.
9. All personal values live in `config.local.sh` (gitignored) — copy
   `config.example.sh` and fill it in for your user as part of steps 3–5.
   The launchd labels are the neutral `com.mac-analyzers.*` namespace.
10. **Build the menu-bar app** — `./app/build.sh && open
    /Applications/MacAnalyzers.app` (Command Line Tools only, no Xcode; needs
    macOS 26). The build signs with an Apple Development certificate when the
    keychain has one (free with any Apple ID; keeps the permission identity
    stable across rebuilds), falls back to ad-hoc, and **installs the app to
    `/Applications`** — the repo `app/` copy is just the build artifact.
    The build also copies `memory-analyzer/`, `storage-analyzer/`,
    `network-analyzer/` and `lib/` into `Contents/Resources/engine/`, so the
    installed app carries its own engine. A checkout at `~/mac-analyzers`
    still wins when present — that is the copy you edit — and settings and
    reports always live in `~/mac-analyzers/`, never inside the bundle,
    because the bundle is replaced wholesale on every update.
    This is the suite's face for your user: actionable native notifications
    (Open Log / Stop Process), a glance menu with Memory/Monitor/Storage
    tabs, live pressure, and per-process Stop/Quit, and a
    System-Settings-style Settings window — config panes that write a marked
    managed block into `config.local.sh` (hand-written values outside the
    markers are never touched), a Schedule pane for the clean times, an
    Update pane, and structured viewers for every log (TextEdit stays as the
    raw escape hatch). It self-registers as a login item, and the plists'
    `AssociatedBundleIdentifiers` attribute the agents to it in Login Items.
    After the first build, re-run both manage-agents installers once (or just
    run `upgrade.command`) so the plists switch to the app's compiled
    `agent-runner` entry point — that's what lets Login Items attribute the
    background agents properly. Skip this step only on a headless /
    script-only setup — the engine runs fine alone: `lib/notify.sh` falls
    back to `alerter` (if installed) or a plain `osascript` banner, and
    `extras/swiftbar-plugin/` gives a no-app menu-bar surface.
11. **Show your user `upgrade.command`** — from now on, updating is a Finder
    double-click on `upgrade.command` at the repo root (or
    `./upgrade.command` in a terminal): `git pull --ff-only`, rebuild +
    reinstall the app, re-run both manage-agents installers, relaunch the
    menu-bar app. It never touches `config.local.sh`, so everything you
    calibrated in steps 3–5 (and any schedule set in the app) survives every
    upgrade. Your user won't even need to remember it: the app checks for
    new releases at launch and every 6 hours, notifies once per version, and
    its Update pane / menu footer run `upgrade.command` on one click.

## Safety invariants — keep these when you customize

- Analyzers stay read-only. Cleaners stay dry-run-by-default.
- The guard kills DEV TOOLING ONLY (its `KILLABLE_RE`); protected apps always
  win; CPU hogs are notify-only, never killed.
- Any process sweep must exempt live AI-session descendants (already
  implemented in memory-reclaim.sh — don't remove it, it prevents killing the
  MCP servers of the very session running the sweep).
- Never auto-prune Docker volumes or Time Machine real backups. The sudoers
  rule must stay scoped to `tmutil thinlocalsnapshots` with exact args.
