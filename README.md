# mac-analyzers

[![ci](https://github.com/hrconsultnj/mac-analyzers/actions/workflows/ci.yml/badge.svg?branch=development)](https://github.com/hrconsultnj/mac-analyzers/actions/workflows/ci.yml)

**Your Mac's RAM and disk, explained and defended.** A self-maintaining
toolkit for macOS that tells you *why* Activity Monitor says 23 GB, kills the
runaway dev process before your Zoom call freezes, reaps the orphaned servers
your tools left behind, and finds the login items of apps you deleted years
ago — with receipts for every action.

## Why your Mac slows down — and what this does about it

You don't have to be a developer to have this problem. If you use AI apps,
coding assistants, or heavyweight creative tools, your Mac quietly collects
background processes during the day — helpers some tool started and forgot
about. Memory fills up, the machine starts compressing and swapping, and by
mid-afternoon everything feels sticky. Mac Analyzers watches for exactly that
and handles it on autopilot:

- **It stops runaway processes before they freeze your Mac** — and it will
  **never touch your real apps**. It only ever acts on development tooling
  from a narrow allowlist, and a protected list (video calls, browsers,
  editors, anything you add) **always wins**.
- **It cleans rebuildable junk on a schedule** — caches, build leftovers,
  abandoned background servers: things your tools recreate on their own. It
  **never touches your documents**, photos, or projects.
- **It tells you what happened** in a normal macOS notification — click it to
  see exactly what was done and why. **Every action is written down.**
- **The menu-bar app is how you live with it**: glance at the chip icon to
  see if anything was stopped today, pause it during heavy work, and change
  the limits with sliders — **no terminal needed after setup**.
- **Everything runs locally.** No account, no telemetry — nothing about your
  machine ever leaves your machine.
- Anything that deletes is **dry-run by default**: it shows you the plan and
  does nothing until told to apply.

Born from a real incident: a 32 GB Mac Studio living at 25–28 GB used, swap
87% full, freezing mid-meeting. Same machine, same day, after this toolkit:
17 GB working set, zero swap, pressure green — and it stays that way on
autopilot. The [examples/](examples/) folder shows the actual before/after
reports.

## Install

The scripts are the **engine**; the menu-bar app is the **face**. The full
experience is one copy-paste:

```bash
git clone https://github.com/hrconsultnj/mac-analyzers.git ~/mac-analyzers
cd ~/mac-analyzers
./memory-analyzer/memory-manage-agents.sh install    # RAM guard + daily reaper
./storage-analyzer/storage-manage-agents.sh install  # scheduled disk hygiene
./app/build.sh && open app/MacAnalyzers.app          # build + launch the app
```

The app builds from source in a couple of minutes and needs only Apple's
**free Command Line Tools** (`xcode-select --install`) — no Xcode. On first
launch it adds itself to Login Items (macOS notifies you it did) and asks for
notification permission; from then on the chip icon in the menu bar is the
whole interface — status at a glance, sliders for the limits, click a
notification to open the log behind it. The built app lives at
`app/MacAnalyzers.app`: open it from Finder, and keep it in the Dock if you
like — clicking the Dock icon launches it when it's stopped and opens
Settings when it's running.

Want to see your machine before installing anything? `./memory-analyzer/analyze.sh`
and `./storage-analyzer/analyze.sh` are read-only reports — always safe.

**Using Claude Code (or another agent)?** Point it at `PORT-TO-YOUR-MAC.md` —
it's written as instructions for an AI to calibrate thresholds, protect lists,
and schedules to your machine before installing.

The launchd plists are templates hydrated at install time (paths + username),
under the identifiable `com.mac-analyzers.*` namespace and attributed to the
app's identity, so System Settings → Login Items never shows you a mystery
entry from this toolkit.

### Script-only (advanced / headless)

The engine runs standalone: install the agents as above and skip
`./app/build.sh`. Notifications fall back to `alerter`
(`brew install vjeantet/tap/alerter` — banner with an "Open Log" button) or a
plain `osascript` banner, and `extras/swiftbar-plugin/` gives you a menu-bar
surface via [SwiftBar](https://swiftbar.app) instead of the app. Configure by
hand: `cp config.example.sh config.local.sh` and edit — the same knobs the
app's Settings manage.

### Distribution — where's the DMG?

There deliberately isn't one. A downloaded unsigned app gets quarantined by
Gatekeeper ("cannot be opened"), while building locally from source carries
no quarantine at all and takes two commands. If demand appears, a notarized
DMG (Apple Developer ID) is the future path. Releases ship a source tarball
(`mac-analyzers-v<version>.tar.gz`) —
see [Releases](https://github.com/hrconsultnj/mac-analyzers/releases).

## Staying up to date

Already cloned? **Double-click `upgrade.command` in Finder.** It pulls the
latest release (`git pull --ff-only`), rebuilds the app, refreshes the
launchd agents, and relaunches the menu-bar app — your `config.local.sh` is
**never touched**. Terminal equivalent:

```bash
cd ~/mac-analyzers && ./upgrade.command
```

Not using git? Every release on the
[Releases page](https://github.com/hrconsultnj/mac-analyzers/releases) ships
the full source as a tarball — download, unpack, and run the Install steps
from the new folder.

## What's inside

| | Tool | What it does | Touches anything? |
|---|---|---|---|
| 🖥️ | `app/` — **Mac Analyzers** menu-bar app | the product's face: Memory/Monitor/Storage glance menu with per-process Stop/Quit, actionable native notifications, System-Settings-style Settings window for the tunables | writes only its own marked block in `config.local.sh` |
| 🔍 | `memory-analyzer/analyze.sh` | "Why is RAM at N GB?" — Activity-Monitor-style breakdown, compressor/swap truth, per-app rollup, CPU/energy, diagnosis with verdicts | never — read-only report |
| 🛡️ | `memory-analyzer/memory-guard.sh` | always-on listener: alerts on memory-pressure, kills a runaway dev process before the machine locks up. Meeting apps, browsers, editors are never touched | kills dev tooling only |
| 🧹 | `memory-analyzer/memory-auto-clean.sh` | daily reaper: orphaned MCP/agent servers, dev servers forgotten since yesterday, stale headless browsers | with `--apply` |
| 🔴 | `memory-analyzer/memory-reclaim.sh` | the "free my RAM **now**" button — reboot effect without rebooting; optionally ⌘Q's heavy apps gracefully | with `--apply` |
| 💾 | `storage-analyzer/analyze.sh` | categorized disk report: caches, node_modules, Docker, per-app footprints, apps-by-last-used | never — read-only report |
| 🗑️ | `storage-analyzer/cleanup.sh` + `storage-auto-clean.sh` | interactive deep clean + scheduled automation-safe sweep (protects active work) | dry-run default |
| ⏪ | `storage-analyzer/tm-reclaim.sh` | releases the Time Machine local snapshots that pin just-deleted blocks (the "I freed 40 GB but df didn't move" fix) | snapshots only |
| 🔎 | `storage-analyzer/login-items-audit.sh` | finds login items / launch agents whose app was uninstalled — mechanically verified, two confidence classes | dry-run default |
| 💡 | `storage-analyzer/spotlight-audit.sh` | Spotlight sanity: is the reindex expected or stuck, and which dev dirs (node_modules, build trees) is it wastefully indexing — fences them reversibly | dry-run default |

Every script double-clicked in Finder opens an **interactive menu**
(preview → confirm). Flags skip the menu — that's how the launchd agents run.
Every run logs exactly how it was invoked.

## Layout

```
~/mac-analyzers/
├── app/                       "Mac Analyzers" menu-bar app — the face (below)
├── memory-analyzer/           RAM suite + its launchd templates (own README)
├── storage-analyzer/          disk suite + its launchd templates (own README)
├── lib/notify.sh              shared notifier every script sources (below)
├── extras/swiftbar-plugin/    SwiftBar surface for script-only setups
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

Knobs in `config.local.sh` (each one optional):
`ANALYZERS_NOTIFIER=native|alerter|osascript` forces a backend,
`ANALYZERS_LOG_VIEWER` picks the app that opens logs on the alerter path, and
`ANALYZERS_NOTIFY_TIMEOUT` is how many seconds an unclicked alerter alert
lives.

## The menu-bar app

`app/` is **Mac Analyzers**, a native SwiftUI menu-bar app (SPM package,
Swift 6, macOS 26) — the face on the script engine:

- **Glance + control** — today's kill count on the menu-bar icon; the
  dropdown has **Memory | Monitor | Storage** tabs: live pressure and recent
  guard events, an Activity-Monitor-style process list with per-row
  **Stop/Quit**, storage/auto-clean status, pause/resume guard, one-click
  log access.
- **Settings** — a System-Settings-style window (sidebar panes: Memory,
  Storage, Notifications, Activity, Logs, About) that writes a clearly-marked
  managed block into `config.local.sh`; anything you wrote outside the
  markers is never touched, and saving memory tunables restarts the guard
  agent so they take effect immediately. The guard's two kill switches
  (hard-cap, critical-pressure) can be flipped to **notify-only**. Clicking
  the app's Dock icon opens Settings.
- **Actionable notifications** — Open Mac Analyzers / Open Log right on the
  alert, plus **Stop Process** when the alert names a live process.
- **Launchd attribution** — every plist carries
  `AssociatedBundleIdentifiers` = `com.mac-analyzers.app`, so System Settings →
  Login Items & Extensions shows the background agents under the app's
  identity instead of anonymous script rows. The app registers itself as a
  login item (`SMAppService`) on first launch.
- **Built without Xcode** — `./app/build.sh` (Command Line Tools only) runs
  `swift build` and hand-assembles the ad-hoc-signed bundle, including the
  `notify` CLI shim the scripts call. Icons regenerate with `app/make-icon.sh`
  (colored .icns) and `app/make-menubar-icon.sh` (monochrome template PNG).

Running script-only? `extras/swiftbar-plugin/` ships a
[SwiftBar](https://swiftbar.app) plugin with the same glance data — kills
today, recent events, click-to-open logs.

## Configuration

Personal/machine values live in `config.local.sh` (gitignored). The app's
Settings manage their own clearly-marked block in that file; everything else —
never-kill apps, stale-app list, deprecated-app leftovers, recordings dir,
extra cache globs — comes from copying `config.example.sh` and filling it in
by hand. The two coexist: the app never touches what you wrote outside its
markers. Everything runs with neutral defaults without any of it.

Developing this repo? `CONTRIBUTING.md` and `AGENTS.md` carry the hard rules;
`.composure/` is local state for the Composure dev plugin used while building
it (gitignored, not part of the product).

## License

**PolyForm Noncommercial 1.0.0** — see `LICENSE.md`. Free to use, modify, and
share for **noncommercial** purposes; the license text and the Required
Notice must stay with every copy. **Commercial use requires a separate
license** — open an issue or reach out via GitHub. Contributions are welcome
under the terms in [CONTRIBUTING.md](CONTRIBUTING.md).
