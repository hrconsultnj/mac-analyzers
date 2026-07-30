# For Claude: adapting this suite to a new Mac

You (Claude) have been handed this folder to set up for YOUR user. It was built
on the author's M2 Mac Studio (32 GB, macOS 26) — everything is designed to
port, but calibrate it, don't just install it.

## What this is

Two sibling suites + a principles doc:
- `memory-analyzer/` — RAM report (`analyze.sh`), always-on spike guard, daily
  orphan reaper, manual "free RAM now" reclaim. See its README.
- `storage-analyzer/` — disk report, interactive deep clean, scheduled
  auto-clean, Time Machine local-snapshot reclaim. See its README.
- The suites' READMEs carry the operating principles (free RAM = wasted RAM;
  watch pressure+swap, never "free"; RAM is vacated, not cleaned). Measure
  this machine's own baselines with `analyze.sh` — never assume another
  machine's numbers.

## Port checklist (do these in order)

1. **Read both READMEs**, then run both `analyze.sh` scripts — read-only, and
   the reports teach you this machine before you change anything.
2. **Paths are already portable**: all shell scripts use `$HOME`; the launchd
   plists contain the author's absolute paths, but `*-manage-agents.sh install`
   rewrites them for the current user+location at install time, and
   `sudoers-install` substitutes the current username. Install FROM wherever
   the folder lands (path-independent), but keep the folder somewhere
   permanent first — launchd will point at it.
3. **Calibrate the guard** to this machine's RAM (defaults assume 32 GB):
   `GUARD_HARD_CAP_MB` (default 6144 ≈ RAM/5) and the spike thresholds in
   `memory-guard.sh`. On a 16 GB machine, halve them.
4. **Rebuild the protect list for YOUR user.** `PROTECT_RE` in memory-guard.sh,
   memory-auto-clean.sh, and memory-reclaim.sh names the author's meeting/
   recording/daemon apps (meeting apps, dictation tools, home-automation daemons, container engines).
   Ask your user what must never be killed (meeting apps, screen recorders,
   home-automation daemons, their container engine) and edit all three.
5. **Same for the reclaim app-quit list** (`APPS_LIST` in memory-reclaim.sh)
   and the curated `STALE_APPS` list in storage-analyzer/cleanup.sh — those
   are the author's apps, not universal defaults.
6. **Schedule times**: storage daily 08:00, memory daily 08:30 — adjust in the
   plists if they collide with your user's hours.
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

## Safety invariants — keep these when you customize

- Analyzers stay read-only. Cleaners stay dry-run-by-default.
- The guard kills DEV TOOLING ONLY (its `KILLABLE_RE`); protected apps always
  win; CPU hogs are notify-only, never killed.
- Any process sweep must exempt live AI-session descendants (already
  implemented in memory-reclaim.sh — don't remove it, it prevents killing the
  MCP servers of the very session running the sweep).
- Never auto-prune Docker volumes or Time Machine real backups. The sudoers
  rule must stay scoped to `tmutil thinlocalsnapshots` with exact args.
