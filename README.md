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

Every script double-clicked in Finder opens an **interactive menu**
(preview → confirm). Flags skip the menu — that's how the launchd agents run.
Every run logs exactly how it was invoked.

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
git clone https://github.com/hrconsultnj/mac-analyzers.git ~/scripts/mac-analyzers
cd ~/scripts/mac-analyzers
cp config.example.sh config.local.sh        # fill in YOUR apps (optional but recommended)
./memory-analyzer/analyze.sh                # read-only — see your machine first
./memory-analyzer/memory-manage-agents.sh install    # guard + daily reaper
./storage-analyzer/storage-manage-agents.sh install  # scheduled disk hygiene
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
- Reports and logs live in `~/system-reports/{memory,storage}/<date>/` —
  every deletion and kill is written down.

## Configuration

Personal/machine values live in `config.local.sh` (gitignored) — copy
`config.example.sh` and fill in your never-kill apps, stale-app list,
deprecated-app leftovers, recordings dir, extra cache globs. Everything runs
with neutral defaults without it.

## License

**PolyForm Noncommercial 1.0.0** — see `LICENSE.md`. Free to use, modify, and
share for **noncommercial** purposes; the license text and the Required
Notice must stay with every copy. **Commercial use requires a separate
license** — open an issue or reach out via GitHub. Contributions are welcome
under the terms in [CONTRIBUTING.md](CONTRIBUTING.md).
