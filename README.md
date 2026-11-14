# mac-analyzers

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
  abandoned background servers: things your tools recreate on their own. The
  scheduled cleans **never touch your documents**, photos, or projects.
- **Anything that touches your own files is opt-in and reviewed first** —
  old downloads and screenshots, apps you have not opened in months, old
  recordings. You start it, you see the list, you untick what you want to
  keep, and what you approve goes to the **Trash**, where the app's Undo
  screen (or Finder's Put Back) can bring it straight back. Files that live
  only in iCloud are never moved at all.
- **It tells you what happened** in a normal macOS notification — click it to
  see exactly what was done and why. **Every action is written down.**
- **The app is how you live with it**: a main window that shows where your
  memory and disk space go, what ran and what it did, and a menu-bar panel
  for a glance and a quick Stop or Quit — **no Terminal needed after
  setup**.
- **Everything runs locally.** No account, no telemetry — nothing about your
  machine ever leaves your machine.
- Anything that deletes is **dry-run by default**: it shows you the plan and
  does nothing until told to apply. In the app you can untick individual
  items before applying, and the cleaners enforce that list themselves —
  they re-derive their own findings and intersect, so the set can only ever
  shrink against what you approved.

Born from a real incident: a 32 GB Mac Studio living at 25–28 GB used, swap
87% full, freezing mid-meeting. Same machine, same day, after this toolkit:
17 GB working set, zero swap, pressure green — and it stays that way on
autopilot. The [examples/](examples/) folder shows the actual before/after
reports.

## Install

The scripts are the **engine**; the app is the **face**. Mac Analyzers needs
**macOS 26 or later** and is built on your Mac from source, which takes three
steps:

1. Install Apple's **free Command Line Tools** (no Xcode needed). In
   Terminal:

   ```bash
   xcode-select --install
   ```

2. Download the project into your home folder:

   ```bash
   git clone https://github.com/hrconsultnj/mac-analyzers.git ~/mac-analyzers
   ```

3. Open the `mac-analyzers` folder in your home folder in Finder and
   **double-click `upgrade.command`**. It builds the app, installs it to
   Applications, installs the background jobs (the memory guard, the daily
   cleanup and the scheduled disk cleanup) and starts the app. The build
   takes a minute or two; when Terminal says "Done", you can close it.

The project must live at `~/mac-analyzers`: that is where the app keeps your
settings, reports and records. The same double-click is how you update later
(see [Staying up to date](#staying-up-to-date)).

If your keychain holds an Apple Development certificate (free with any Apple
ID), the build signs with it automatically — a stable identity, so macOS
permissions survive rebuilds; without one it falls back to ad-hoc signing and
everything still works. Either way the app runs with macOS's **hardened
runtime**, so another program on your account cannot make it load code of its
own. On first launch it adds itself to Login Items (macOS notifies you it
did) and asks for notification permission. The **Setup** screen in the app
checks that every part is installed and running, and can start anything that
is not. The app lives at `/Applications/MacAnalyzers.app` like any Mac app
(the copy under `app/` is just the build output and the script-only
fallback); clicking its Dock icon opens the main window.

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

The engine runs standalone without the app. Skip `upgrade.command` and
install only the background jobs:

```bash
cd ~/mac-analyzers
./memory-analyzer/memory-manage-agents.sh install    # memory guard + daily cleanup
./storage-analyzer/storage-manage-agents.sh install  # scheduled disk cleanup
```

Notifications fall back to `alerter`
(`brew install vjeantet/tap/alerter` — banner with an "Open Log" button) or a
plain `osascript` banner, and `extras/swiftbar-plugin/` gives you a menu-bar
surface via [SwiftBar](https://swiftbar.app) instead of the app. Configure by
hand: `cp config.example.sh config.local.sh` and edit — the same knobs the
app's Settings manage.

### Distribution — where's the DMG?

A downloadable app is not offered yet, for two reasons:

- **A downloaded copy cannot yet set itself up or update itself.** The
  background jobs (the guard, the scheduled cleanups) and updates are
  installed from a clone today; a copy dragged in from a disk image would
  run, but without them.
- **It is not signed with an Apple Developer ID or notarized.** macOS
  refuses to open an app like that the first time you open it after
  downloading it. A copy you build yourself is never quarantined, so this
  does not apply to it.

Until both are solved, building from a clone (the three steps above) is the
supported way to install. Each release on the
[Releases page](https://github.com/hrconsultnj/mac-analyzers/releases) also
attaches the full source as a tarball (`mac-analyzers-v<version>.tar.gz`).

## Staying up to date

The app checks for a newer release on launch and every 6 hours (one public
request to GitHub's releases list — nothing about your machine is sent) and
notifies **once per new version**. The **Updates** screen and the menu-bar
panel show the version you have and the newest one, and **Install** opens
Terminal and runs `upgrade.command` for you. Nothing is ever installed by
itself.

You can also **double-click `upgrade.command` in Finder** at any time. It
pulls the latest version (`git pull --ff-only`), rebuilds the app (which
reinstalls it to Applications), refreshes the background jobs and restarts
the app — your settings in `config.local.sh` are **never touched**. Terminal
equivalent:

```bash
cd ~/mac-analyzers && ./upgrade.command
```

**Update channels.** On the Updates screen, a copy built from a clone can
follow one of three channels:

- **Releases** (the default) — finished releases only.
- **Beta** — the newest work being developed, before it is released. It is
  offered only when your clone is on the development branch; to switch,
  run `git -C ~/mac-analyzers checkout development` and then
  `upgrade.command`. Install pulls the newest development version and
  rebuilds.
- **This Copy** — your clone exactly as it is now, including changes you
  have not committed. "Rebuild from This Copy" runs `rebuild.command`, the
  same build without pulling anything.

Each channel says how far behind your installed copy is. Reading your clone
never runs anything the clone itself names, and nothing is fetched into it
without you pressing a button.

**Development versions.** A copy built from work that is not released yet
does not claim the last release's number. It is named for the release it is
heading toward plus a development number — for example `2.70.1-dev.12` in
the sidebar — and the Updates screen shows the full name, the commit it was
built from and whether it includes uncommitted changes. It is never offered
the release it is already past, and is offered the next real one when it
comes out.

Not using git? Unpack the source tarball from the
[Releases page](https://github.com/hrconsultnj/mac-analyzers/releases) in your
home folder, so it lands at `~/mac-analyzers`, and double-click
`rebuild.command` (`upgrade.command` needs a git clone to pull from). Such a
copy follows Releases only; to update it, unpack the next release over it
and run `rebuild.command` again.

## What's inside

| | Tool | What it does | Touches anything? |
|---|---|---|---|
| 🖥️ | `app/` — **Mac Analyzers** app | the product's face: a main window with Overview, Activity, Monitor, every storage cleanup as a reviewed preview, system audits, Trends and Undo; a menu-bar panel with per-app Stop/Quit; actionable native notifications; settings, editable schedules and update channels | writes only its own marked block in `config.local.sh` (+ schedule edits into its own launchd plists); cleanups act only on what you approve |
| 🔍 | `memory-analyzer/analyze.sh` | "Why is RAM at N GB?" — Activity-Monitor-style breakdown, compressor/swap truth, per-app rollup, CPU/energy, diagnosis with verdicts | never — read-only report |
| 🛡️ | `memory-analyzer/memory-guard.sh` | always-on listener: alerts on memory-pressure, kills a runaway dev process before the machine locks up. Meeting apps, browsers, editors are never touched | kills dev tooling only |
| 🧹 | `memory-analyzer/memory-auto-clean.sh` | daily reaper: orphaned MCP/agent servers, dev servers forgotten since yesterday, stale headless browsers | with `--apply` |
| 🔴 | `memory-analyzer/memory-reclaim.sh` | the "free my RAM **now**" button — reboot effect without rebooting; optionally ⌘Q's heavy apps gracefully | with `--apply` |
| 💾 | `storage-analyzer/analyze.sh` | categorized disk report: caches, node_modules, Docker, per-app footprints, apps-by-last-used | never — read-only report |
| 🗑️ | `storage-analyzer/cleanup.sh` + `storage-auto-clean.sh` | interactive deep clean + scheduled automation-safe sweep (protects active work) | dry-run default |
| ⏪ | `storage-analyzer/tm-reclaim.sh` | releases the Time Machine local snapshots that pin just-deleted blocks (the "I freed 40 GB but df didn't move" fix) | snapshots only |
| 🔎 | `storage-analyzer/login-items-audit.sh` | finds login items / launch agents whose app was uninstalled — mechanically verified, two confidence classes | dry-run default |
| 💡 | `storage-analyzer/spotlight-audit.sh` | Spotlight sanity: is the reindex expected or stuck, and which dev dirs (node_modules, build trees) is it wastefully indexing — fences them reversibly | dry-run default |
| 🧺 | `storage-analyzer/temp-clean.sh` | what's really in /tmp, /var and your AI agents' folders (Claude Code, Codex, npx MCP servers): mounted disk images told apart from real usage, live sessions and open files protected, history sized but never touched | dry-run default · Trash, permanent opt-in |

Every script double-clicked in Finder opens an **interactive menu**
(preview → confirm). Flags skip the menu — that's how the launchd agents run.
Every run logs exactly how it was invoked.

## Layout

```
~/mac-analyzers/
├── app/                       the "Mac Analyzers" app — the face (below)
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
- The single administrator touchpoint is a permission for **one exact
  command**: deleting Time Machine's local snapshots on this Mac. It is
  installed only if you choose "Allow…" on the Time Machine screen (macOS asks
  for an administrator password once), it cannot touch the backups on your
  Time Machine disk, and while it is in place any program on your account can
  run that one command without asking. "Remove Permission…" on that screen,
  or the Turn Off or Remove screen, takes it away; each account on the Mac
  has its own.
- Apps are only ever **asked** to quit, the way Command-Q asks. Stop asks a
  program politely first; Force Stop is a separate choice you confirm.
- Files that exist only in iCloud are **never moved** by any cleanup: moving
  one frees nothing on this Mac, and emptying the Trash would delete it from
  iCloud and your other devices.
- Everything a cleanup sends to the Trash is recorded, and Undo puts an item
  back only when it can tell it is still the same item.
- Reports and logs live in `~/mac-analyzers/reports/{memory,storage}/<date>/` —
  every deletion and kill is written down.

## Notifications

Every alert — guard kills, pressure warnings, auto-clean summaries — goes
through `lib/notify.sh`, which picks the best backend present:

1. **The app's bundled CLI**
   (`/Applications/MacAnalyzers.app/Contents/MacOS/notify`, falling back to
   the repo copy under `app/`) — posts over `DistributedNotificationCenter`
   to the persistent app, which shows a real native notification under the
   app's identity; clicking it opens that run's log **inside the app**.
2. **`alerter`** (`brew install vjeantet/tap/alerter`) — banner with an
   "Open Log" button.
3. **Plain `osascript` banner** — always available, no click action.

Knobs in `config.local.sh` (each one optional):
`ANALYZERS_NOTIFIER=native|alerter|osascript` forces a backend,
`ANALYZERS_LOG_VIEWER` picks the app that opens logs on the alerter path, and
`ANALYZERS_NOTIFY_TIMEOUT` is how many seconds an unclicked alerter alert
lives.

## The app

`app/` is **Mac Analyzers**, a native SwiftUI Mac app (SPM package, Swift 6,
macOS 26) — the face on the script engine. Every screen reads the same way:
the kinds of thing it shows are tabs with a count, rows are grouped under
the app, project or day they belong to with a total, and a group opens to
show what is in it.

- **The main window** — a sidebar you can hide, Back and Forward across
  every screen (Command-[ and Command-]), and a Go menu for the most-used
  screens:
  - **Overview** (a grid of boxes for memory, storage, the guard, the
    schedule and the week, with Needs Attention when something needs you),
    **Activity** (everything that ran, day by day, with what each run found
    or freed) and **Setup** (is every part installed and running).
  - **Memory** — **Monitor** (one table of every app and tool with its
    memory and processor use, what kind of thing it is, and why it cannot be
    stopped when it cannot; each row of "Where Your Memory Is" opens its own
    screen, from App Memory to Swap Used), **Memory Guard** (a day-by-day
    history of what the guard stopped or flagged, and why) and **Memory
    Cleanup** (a preview you tick before anything is closed).
  - **Storage** — **Disk** (capacity and how long the free space will last),
    **Caches & Builds**, **Downloads**, **Temp & Agents**, **Time Machine**
    (local snapshots), **Spotlight** (fence developer folders out of the
    index), **Unused Apps** (apps not opened for six months or more, with
    their files) and **Old Recordings**. Each is one screen: Preview, untick
    what to keep, Apply, and every earlier run under History. Each says
    whether what it clears goes to the Trash or is deleted for good.
  - **System** — **Network**, **Login & Startup Items** (apps that open at
    login, their background items, leftovers from removed apps, and what was
    added day by day) and **Reports** (memory and storage reports, opened as
    documents with sections you can fold).
  - **History** — **Trends** (memory and storage over a period, including
    what cleanups removed) and **Undo** (what cleanups moved to the Trash,
    by day and cleanup, to put back whole or one item at a time).
- **The menu-bar panel** — today's guard activity on the menu-bar icon; a
  Monitor tab listing what uses memory by app, heaviest first, with real app
  icons and the same Stop and Quit rules as the main window (it never forces
  a program; it offers to open Monitor instead); a Memory tab with a live
  memory-pressure graph and the same figures as Activity Monitor's memory
  footer; running jobs; and the installed version.
- **Settings** — Memory, Storage, Notifications and Schedule (editable clean
  times that survive reinstalls and upgrades). They write a clearly-marked
  managed block into `config.local.sh`; anything you wrote outside the
  markers is never touched, and saving memory settings restarts the guard so
  they take effect immediately. The guard's two stop switches (hard cap,
  critical pressure) can be set to **notify only**.
- **Every run is readable** — what a cleanup or check found or did is shown
  as rows in tabs and groups, never as a log. The exact text a run printed
  is one level down, inside the app ("Show Raw Output", with search and
  Copy); nothing opens another app to show it.
- **Updates** — the Updates screen shows installed vs newest, picks the
  update channel (Releases, Beta or This Copy, see
  [Staying up to date](#staying-up-to-date)) and runs `upgrade.command` in
  Terminal on Install.
- **Actionable notifications** — Open Mac Analyzers / Open Log right on the
  alert, plus **Stop Process** when the alert names a live process. Stop
  first checks that it is still the same program; if it has changed, or is
  part of a live coding session, Monitor opens on it and nothing is stopped.
- **Launchd attribution** — the installed plists launch the engine through
  the app's compiled `agent-runner` (inside the bundle, sharing its signing
  identity) and carry `AssociatedBundleIdentifiers` = `com.mac-analyzers.app`,
  so System Settings → Login Items & Extensions shows the background agents
  under the app's identity instead of anonymous script rows. The app
  registers itself as a login item (`SMAppService`) on first launch.
- **Built without Xcode** — `./app/build.sh` (Command Line Tools only) runs
  `swift build`, hand-assembles the bundle (including the `notify` CLI shim
  the scripts call and the `agent-runner` launchd entry point), signs it with
  your Apple Development certificate when one exists (ad-hoc fallback) with
  the hardened runtime, and installs it to `/Applications`. Icons regenerate with `app/make-icon.sh`
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

**Free and supporter builds.** Everything in this repository — the engine,
the app, every analyzer and cleaner — is free and builds from source as-is.
A small number of convenience features (things that summarize or automate
on top of what the app already shows you) live in a separate, private
package and appear only in supporter builds. Nothing in this repo is
crippled or time-limited by that: if a feature is here, it works, forever,
for everyone. The rule the project follows is simple — anything that
**explains or audits what runs on your Mac stays free**, because that is
the part you have to be able to trust and verify.

**What this means for the app** (`app/`, the same license): the source is
public so you can read exactly what runs on your Mac — audit it, build it
for yourself, patch it, learn from it. What the license does **not** grant
is commercial redistribution: selling the app, shipping it (or builds of
it) inside a paid product or service, or offering your own distribution of
it commercially. Official binaries and any commercial licensing come only
from this project. Source you can see is not source you can sell.
