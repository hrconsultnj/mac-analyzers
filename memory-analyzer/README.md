# memory-analyzer

RAM suite for macOS — the sibling of `../storage-analyzer`, but for memory.
Scripts and launchd labels are prefixed `memory-` so Login Items / background
tasks in System Settings are identifiable at a glance.

| Tool | Role | Mutates? |
|------|------|----------|
| `analyze.sh` | "why is my RAM at N GB?" report | never |
| `memory-guard.sh` | always-on spike listener — alerts / kills runaway dev processes | kills (safelist only) |
| `memory-auto-clean.sh` | daily reaper — orphans, forgotten dev servers (scheduled 08:30) | with `--apply` |
| `memory-reclaim.sh` | **manual "free my RAM now" button** — reboot effect, no reboot | with `--apply` |
| `memory-manage-agents.sh` | install / remove / status / pause the LaunchAgents | — |

Reports live in `~/system-reports/memory/<YYYY-MM-DD>/report-<HHMM>.md`, with
`latest.md` and the logs at `~/system-reports/memory/` root. (Storage suite
mirrors this at `~/system-reports/storage/`.)

## Which one do I run?

**Double-clicking any script in Finder opens an interactive menu** — pick a
numbered option, preview first, confirm apply. Flags skip the menu (that is
how the launchd agents and Claude run them). Every report/log records the
input used (`input: interactive menu: choice N` or the flags).

- **"Why is RAM high?"** → `./analyze.sh`, read `latest.md`. Read-only, always safe.
- **"Free memory NOW without rebooting"** → `./memory-reclaim.sh` (shows plan),
  then `./memory-reclaim.sh --apply`, or `--apply --apps` to also gracefully
  quit Opera/Chrome/VS Code/ChatGPT/Docker (⌘Q-style — save dialogs still
  appear; Zoom never touched). Reopen what you need after.
- **Nothing** → the daily 08:30 agent already runs `memory-auto-clean.sh --apply`
  automatically; the guard is always watching. Running `memory-auto-clean.sh`
  by hand is always a DRY RUN unless you add `--apply`.

A reboot clears swap + compressed memory only because it kills every process —
`memory-reclaim.sh --apply --apps` gets the same effect surgically. RAM cannot
be "cleaned" any other way: compressed/swap pages drain only when their owning
processes exit.

## memory-guard.sh — the spike listener

Polls kernel memory-pressure every 15s. Escalation ladder:

1. **Process spiking** (>400 MB growth/tick, ≥1 GB): notification, no action.
2. **Pressure WARNING** (level 2): notification naming top consumers.
3. **Hard cap** (single safelisted process >6 GB, any pressure): forensic
   snapshot to `~/system-reports/memory/<date>/guard-critical-*.log`, then
   SIGTERM→SIGKILL.
4. **Pressure CRITICAL** (level 4): forensic snapshot + kill the biggest
   safelisted offender (>500 MB only).
5. **Sustained CPU hog** (>150% for 3 ticks ≈ 45s): notification only — CPU is
   never a kill reason (a hot build looks identical to a runaway).

**Safelist (killable):** node/npm/npx/bun/tsx/deno, next/vite/webpack/esbuild,
vitest/jest, playwright + headless Chromium.
**Never killed:** Zoom, all browsers, VS Code, Docker, Claude sessions, screen
recording, anything system — plus whatever ANALYZERS_PROTECT_EXTRA adds in config.local.sh.

Pause during a heavy legit build: `./memory-manage-agents.sh pause` / `resume`.

## memory-auto-clean.sh — the daily reaper (08:30)

| § | Target | Default action |
|---|--------|----------------|
| 1 | Orphaned MCP servers (parent session died, PPID=1) | **kill** |
| 2 | Other orphaned node/dev processes | report (`--orphans-all` to kill) |
| 3 | Dev servers older than 24h (`--dev-age-hours`) | **kill** |
| 4 | Playwright / headless Chromium >2h | **kill** |
| 5 | MCP sets under LIVE sessions | report only |
| 6 | VS Code helpers >250 MB up >2d | report only — "Developer: Reload Window" |

## memory-reclaim.sh — the big red button

Same targets as the reaper but **no age thresholds**, plus optional graceful
app quits. **Live-session safe**: it finds every open Claude Code session (any
terminal) and ChatGPT/Codex in the process table and exempts them AND all
their descendants — MCP servers included — no matter how it's invoked
(terminal, Finder double-click, launchd). Only servers of *closed* sessions
are swept, so open sessions never lose their tools mid-conversation.

## Why MCP servers "multiply"

Every Claude Code session spawns its own private copy of each configured MCP
server (user scope + project `.mcp.json` + plugin-bundled); Codex (ChatGPT
app) spawns its own set too (`~/.codex/config.toml`). N sessions = N sets —
normal, and they exit with their session. Only crashed sessions leak orphans
(§1 above reaps those). If you see the SAME server twice per session, it's
registered in two layers — dedupe with `claude mcp remove` at the redundant
scope.
