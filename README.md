# mac-analyzers

[![ci](https://github.com/hrconsultnj/mac-analyzers/actions/workflows/ci.yml/badge.svg?branch=development)](https://github.com/hrconsultnj/mac-analyzers/actions/workflows/ci.yml)

**Your Mac's RAM and disk, explained and defended.** A self-maintaining
toolkit for macOS that tells you *why* Activity Monitor says 23 GB, kills the
runaway dev process before your Zoom call freezes, reaps the orphaned servers
your tools left behind, and finds the login items of apps you deleted years
ago — with receipts for every action.

Born from a real incident: a 32 GB Mac Studio living at 25–28 GB used, swap
87% full, freezing mid-meeting. Same machine, same day, after this toolkit:
17 GB working set, zero swap, pressure green — and it stays that way on
autopilot. The [examples/](examples/) folder shows the actual before/after
reports.

## What's inside

| | Tool | What it does | Touches anything? |
|---|---|---|---|
| 🔍 | `memory-analyzer/analyze.sh` | "Why is RAM at N GB?" — Activity-Monitor-style breakdown, compressor/swap truth, per-app rollup, CPU/energy, diagnosis with verdicts | never — read-only report |
| 🛡️ | `memory-analyzer/memory-guard.sh` | always-on listener: alerts on memory-pressure, kills a runaway dev process before the machine locks up. Meeting apps, browsers, editors are never touched | kills dev tooling only |
| 🧹 | `memory-analyzer/memory-auto-clean.sh` | daily reaper: orphaned MCP/agent servers, dev servers forgotten since yesterday, stale headless browsers | with `--apply` |
| 🔴 | `memory-analyzer/memory-reclaim.sh` | the "free my RAM **now**" button — reboot effect without rebooting; optionally ⌘Q's heavy apps gracefully | with `--apply` |
| 💾 | `storage-analyzer/analyze.sh` | categorized disk report: caches, node_modules, Docker, per-app footprints, apps-by-last-used | never — read-only report |
| 🗑️ | `storage-analyzer/cleanup.sh` + `storage-auto-clean.sh` | interactive deep clean + scheduled automation-safe sweep (protects active work) | dry-run default |
| ⏪ | `storage-analyzer/tm-reclaim.sh` | releases the Time Machine local snapshots that pin just-deleted blocks (the "I freed 40 GB but df didn't move" fix) | snapshots only |
| 🔎 | `storage-analyzer/login-items-audit.sh` | finds login items / launch agents whose app was uninstalled — mechanically verified, two confidence classes | dry-run default |
| 💡 | `storage-analyzer/spotlight-audit.sh` | Spotlight sanity: is the reindex expected or stuck, and which dev dirs (node_modules, build trees) is it wastefully indexing — fences them reversibly | dry-run default |
| 🖥️ | `app/` — **Mac Analyzers** menu-bar app | optional native face for the suite: glance menu, real notifications with click-to-open-log, Settings for the tunables | writes only its own marked block in `config.local.sh` |

Every script double-clicked in Finder opens an **interactive menu**
(preview → confirm). Flags skip the menu — that's how the launchd agents run.
Every run logs exactly how it was invoked.

## Layout

```
~/mac-analyzers/
├── memory-analyzer/           RAM suite + its launchd templates (own README)
├── storage-analyzer/          disk suite + its launchd templates (own README)
├── lib/notify.sh              shared notifier every script sources (below)
├── app/                       "Mac Analyzers" menu-bar app — optional (below)
├── extras/swiftbar-plugin/    SwiftBar surface for script-only setups — optional
├── config.example.sh          → copy to config.local.sh (gitignored)
└── reports/{memory,storage}/  every report + log the suite writes (gitignored)
```

Reports and logs live **inside the repo** at
`~/mac-analyzers/reports/{memory,storage}/` — dated report folders, a
`latest.md` symlink, and the run logs, all gitignored. (The repo formerly
lived at `~/scripts` with reports at `~/system-reports`; those paths are
retired.)

## See it work

From [`examples/login-items-audit.md`](examples/login-items-audit.md) — real output:

```
[ORPHAN·sudo]  com.teamviewer.desktop
               target: /Applications/TeamViewer.app/.../TeamViewer_Desktop_Proxy  (MISSING)
[LEFTOVER?]    com.teamviewer.Helper — target exists but NO app from vendor
               'com.teamviewer' is installed. Review; if unwanted: ...
```

TeamViewer had been gone for years; its launchers were still registered at
every login. More: [the sick-machine report](examples/memory-report-sick.md) ·
[the healthy report](examples/memory-report.md) ·
[the reclaim preview](examples/memory-reclaim-dry-run.md).

## Install

```bash
git clone https://github.com/hrconsultnj/mac-analyzers.git ~/mac-analyzers
cd ~/mac-analyzers
cp config.example.sh config.local.sh        # fill in YOUR apps (optional but recommended)
./memory-analyzer/analyze.sh                # read-only — see your machine first
./memory-analyzer/memory-manage-agents.sh install    # guard + daily reaper
./storage-analyzer/storage-manage-agents.sh install  # scheduled disk hygiene
./app/build.sh                              # optional — menu-bar app (CLT only, no Xcode)
```

**Using Claude Code (or another agent)?** Point it at `PORT-TO-YOUR-MAC.md` —
it's written as instructions for an AI to calibrate thresholds, protect lists,
and schedules to your machine before installing.

The launchd plists are templates hydrated at install time (paths + username),
under the identifiable `com.mac-analyzers.*` namespace, so System Settings →
Login Items never shows you a mystery entry from this toolkit.

## Safety design

- **Analyzers are read-only. Cleaners are dry-run until you say `--apply`.**
- The guard's kill authority is a **narrow allowlist** (node/npx/bun,
  bundlers, test runners, headless browsers) minus a **protect list that
  always wins** (meeting apps, browsers, editors, containers, screen
  recording, your `config.local.sh` additions). CPU spikes are notify-only —
  a hot build looks identical to a runaway.
- Process sweeps **exempt live AI coding sessions** (claude/codex) and all
  their descendants — your session's MCP servers survive any sweep, however
  it's invoked.
- The single sudo touchpoint is a sudoers rule scoped to **one exact command**
  (Time Machine local-snapshot thinning) — installed only if you opt in, and
  it cannot touch real backups.
- Reports and logs live in `~/mac-analyzers/reports/{memory,storage}/<date>/` —
  every deletion and kill is written down.

## Notifications

Every alert — guard kills, pressure warnings, auto-clean summaries — goes
through `lib/notify.sh`, which picks the best backend present:

1. **The menu-bar app's bundled CLI**
   (`app/MacAnalyzers.app/Contents/MacOS/notify`) — posts over
   `DistributedNotificationCenter` to the persistent app, which shows a real
   native notification under the app's identity; clicking it opens that run's
   log.
2. **`alerter`** (`brew install vjeantet/tap/alerter`) — banner with an
   "Open Log" button.
3. **Plain `osascript` banner** — always available, no click action.

Knobs in `config.local.sh` (all optional):
`ANALYZERS_NOTIFIER=native|alerter|osascript` forces a backend,
`ANALYZERS_LOG_VIEWER` picks the app that opens logs on the alerter path, and
`ANALYZERS_NOTIFY_TIMEOUT` is how many seconds an unclicked alerter alert
lives.

## The menu-bar app (optional)

`app/` is **Mac Analyzers**, a native SwiftUI menu-bar app (SPM package,
Swift 6, macOS 26) that gives the suite a face. The scripts run standalone
without it — with it you get:

- **Glance + control** — today's kill count on the menu-bar icon, recent guard
  events, auto-clean status, pause/resume guard, one-click log access.
- **Settings** (Memory / Storage / Notifications tabs) that write a
  clearly-marked managed block into `config.local.sh`; anything you wrote
  outside the markers is never touched, and saving memory tunables restarts
  the guard agent so they take effect immediately.
- **Launchd attribution** — every plist carries
  `AssociatedBundleIdentifiers` = `com.mac-analyzers.app`, so System Settings →
  Login Items & Extensions shows the background agents under the app's
  identity instead of anonymous script rows. The app registers itself as a
  login item (`SMAppService`) on first launch.
- **Built without Xcode** — `./app/build.sh` (Command Line Tools only) runs
  `swift build` and hand-assembles the ad-hoc-signed bundle, including the
  `notify` CLI shim the scripts call. Icons regenerate with `app/make-icon.sh`
  (colored .icns) and `app/make-menubar-icon.sh` (monochrome template PNG).

No app, no Xcode, still want a menu-bar surface? `extras/swiftbar-plugin/`
ships a [SwiftBar](https://swiftbar.app) plugin with the same glance data —
kills today, recent events, click-to-open logs.

## Configuration

Personal/machine values live in `config.local.sh` (gitignored) — copy
`config.example.sh` and fill in your never-kill apps, stale-app list,
deprecated-app leftovers, recordings dir, extra cache globs. Everything runs
with neutral defaults without it. If you use the menu-bar app, its Settings
own only the marked managed block in that file — your hand-written config
coexists untouched.

Developing this repo? `CONTRIBUTING.md` and `AGENTS.md` carry the hard rules;
`.composure/` is local state for the Composure dev plugin used while building
it (gitignored, not part of the product).

## License

**PolyForm Noncommercial 1.0.0** — see `LICENSE.md`. Free to use, modify, and
share for **noncommercial** purposes; the license text and the Required
Notice must stay with every copy. **Commercial use requires a separate
license** — open an issue or reach out via GitHub. Contributions are welcome
under the terms in [CONTRIBUTING.md](CONTRIBUTING.md).
