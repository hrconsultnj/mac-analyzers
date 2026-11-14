# memory-analyzer

RAM suite for macOS — the sibling of `../storage-analyzer`, but for memory.
Scripts and launchd labels are prefixed `memory-` (`com.mac-analyzers.*`) so
Login Items / background tasks in System Settings are identifiable at a
glance; the plists also set `AssociatedBundleIdentifiers` =
`com.mac-analyzers.app`, so with the Mac Analyzers menu-bar app installed the
agents group under the app's identity there.

| Tool | Role | Mutates? |
|------|------|----------|
| `analyze.sh` | "why is my RAM at N GB?" report | never |
| `memory-guard.sh` | always-on spike listener — alerts / kills runaway dev processes | kills (safelist only) |
| `memory-auto-clean.sh` | daily reaper — orphans, forgotten dev servers (scheduled, default 08:30) — plus the **dev pass** (`--dev`) the guard runs every 2 min: idle emulators/simulators, build daemons, dev servers | with `--apply` |
| `memory-reclaim.sh` | **manual "free my RAM now" button** — reboot effect, no reboot | with `--apply` |
| `memory-manage-agents.sh` | install / remove / status / pause the LaunchAgents | — |

Reports live in `~/mac-analyzers/reports/memory/<YYYY-MM-DD>/report-<HHMM>.md`, with
`latest.md` and the logs at `~/mac-analyzers/reports/memory/` root. (Storage suite
mirrors this at `~/mac-analyzers/reports/storage/`.)

Notifications (spikes, warnings, kills, clean summaries) go through
`../lib/notify.sh` — the Mac Analyzers menu-bar app's native path by default
(the `/Applications` install, repo copy as fallback), falling back to
`alerter` and then a plain banner on script-only setups; clicking one opens
the matching log. With the app installed, each log opens as a structured
screen — guard events behind filter chips, clean/reclaim runs as
status-filtered cards with a protected-session banner, forensics snapshots
as stat cards plus a top-process table — with "Open in TextEdit" for the raw
file. See the root README's Notifications section.

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
- **Nothing** → the daily agent (08:30 by default — editable in the app's
  Schedule pane) already runs `memory-auto-clean.sh --apply` automatically;
  the guard is always watching. Running `memory-auto-clean.sh` by hand is
  always a DRY RUN unless you add `--apply`.

A reboot clears swap + compressed memory only because it kills every process —
`memory-reclaim.sh --apply --apps` gets the same effect surgically. RAM cannot
be "cleaned" any other way: compressed/swap pages drain only when their owning
processes exit.

## memory-guard.sh — the spike listener

Polls kernel memory-pressure every 15s. Escalation ladder:

1. **Process spiking** (>400 MB growth/tick, ≥1 GB): notification, no action.
2. **Pressure WARNING** (level 2): notification naming top consumers.
3. **Hard cap** (single safelisted process >6 GB, any pressure): forensic
   snapshot to `~/mac-analyzers/reports/memory/<date>/guard-critical-*.log`, then
   SIGTERM→SIGKILL.
4. **Pressure CRITICAL** (level 4): forensic snapshot + kill the biggest
   safelisted offender (>500 MB only).
5. **Sustained CPU hog** (>150% for 3 ticks ≈ 45s): notification only — CPU is
   never a kill reason (a hot build looks identical to a runaway).
6. **Idle dev tooling** (every `GUARD_DEV_SWEEP_SECS`, default 120s): starts
   `memory-auto-clean.sh --apply --dev --quiet` in the background — see the
   dev pass below. It writes to `auto-clean.log` only when it stops something.

**Safelist (killable):** node/npm/npx/bun/tsx/deno, next/vite/webpack/esbuild,
vitest/jest, playwright + headless Chromium.
**Never killed:** Zoom, all browsers, VS Code, Docker, screen recording, anything
system — plus whatever ANALYZERS_PROTECT_EXTRA adds in config.local.sh — and **every
live coding session**: an agent in `lib/coding-agents.tsv` (Claude Code, Codex, Gemini
CLI, Copilot, OpenCode, …) and everything it started, its MCP servers and dev servers
included (`lib/live-sessions.sh`, the same list the app and the cleaners read). If that
list cannot be read the guard stops nothing and logs `KILL-SKIPPED`; it still alerts.
`memory-analyzer/tests/guard-exemption-test.sh` proves it for every agent in the list.

**What the app tells the guard:** `~/mac-analyzers/reports/memory/.guard-fallback.tsv`,
plain `key<TAB>value` lines the app writes whenever a setting changes (`hardCapMB`,
`hardCapStop`, `pressureStop`, `neverClosePath` once per path, `pause`) and the guard
re-reads every tick (`lib/guard-select.sh`, bash 3.2). A Never Close path is matched as
plain text with `index()`, never as a pattern. With no file, the guard uses the values it
always had.

**The rules engine (the app).** `rules/kinds.json`, `rules/plan.json` and
`rules/protected.json` describe what each kind of process may be asked, as data. In this
version the engine only WATCHES: once a minute, while the app runs, it writes what each
rule would have done to `reports/memory/rule-outcomes.jsonl` and stops nothing. The guard
script above does everything that is done. `agent-runner --check-rules`,
`--compare-legacy` and `--rules-once` check and show it.

Pause during a heavy legit build: `./memory-manage-agents.sh pause` / `resume`,
or the Pause/Resume button in the menu-bar app. The app's Settings → Memory
pane edits the guard tunables (hard cap, spike thresholds) in
`config.local.sh` and restarts the guard so they apply immediately.

## memory-auto-clean.sh — the daily reaper (default 08:30)

| § | Target | Default action |
|---|--------|----------------|
| 1 | Orphaned MCP servers (parent session died, PPID=1) | **kill** |
| 2 | Orphaned dev tooling — a tool tree whose parent is gone (tsc/vitest/esbuild workers, npx/pnpm wrappers) | **kill once idle 3 min**; busy ones reported (`--orphans-all` kills those too) |
| 3 | Dev servers older than 24h (`--dev-age-hours`) | **kill** |
| 4 | Playwright / headless Chromium >2h | **kill** |
| 5 | MCP sets under LIVE sessions | report only |
| 6 | VS Code helpers >250 MB up >2d | report only — "Developer: Reload Window" |
| 7 | Emulators & simulators nobody drives (no build, test, adb/simctl/xcodebuild/expo run/maestro, Metro activity or window focus) for 20 min | **shut down** gracefully — device data and quick-boot snapshot kept |
| 8 | Gradle / Kotlin daemons idle 5 min — only while **no Gradle build runs anywhere**, so another project's build is never hit | **stop** |
| 9 | Leftovers of finished/failed native builds — Xcode build helpers, emulator plumbing — whose parent is gone | **kill once idle** |
| 10 | Dev servers (Metro, next, vite, storybook…) with no client connected and no activity — 30 min while their project is open in a session or terminal (or they run in an active agent session's scratch folder), 3 min once not | **kill** (with the wrappers that would respawn them) |
| 11 | Docker / Supabase stacks whose project has had **no live claude/codex session or interactive terminal in it** for 30 min (`ANALYZERS_STACK_IDLE_MIN`) — **opt-in** (`ANALYZERS_DEV_STOP_IDLE_STACKS=1`), dev pass only | **`docker stop`**, one container at a time — containers, volumes, images and Docker itself are never touched; a stack that maps to no project is reported and kept |

### The dev pass (`--dev`: sections 1, 2, 7–11)

Judges what each process is **doing**, not who started it. A client connected
to its ports or growing CPU time keeps it (CPU only ever keeps something alive
— never a kill reason); the first idle sighting is remembered in
`reports/memory/.dev-idle-state`, and it goes once idle past its grace. Live
AI sessions keep their exemption; `ANALYZERS_DEV_REAP_SESSION_SERVERS=1` lets
an idle dev server such a session left in the background go too.

- **Automatic:** the guard runs it every 2 min (`GUARD_DEV_SWEEP_SECS`).
- **After a failed native build:** `./memory-auto-clean.sh --apply --dev --now`
  — no idle wait for build daemons and build leftovers (still never while a
  build runs). Build scripts can call this from their failure path.
- **Idle stacks (§11):** with `ANALYZERS_DEV_STOP_IDLE_STACKS=1` the pass also stops the
  Docker/Supabase stacks of projects nobody is working on. A project is live while a
  claude/codex session or an interactive terminal shell sits in its repo (a linked git worktree counts as the repo, resolved
  through the git common dir). A stack is mapped to its project by its Supabase `project_id`
  (the `supabase/config.toml` of a live session's repo, then of the repos under
  `ANALYZERS_STACK_REPO_ROOTS`), by its Compose `working_dir`, or by `ANALYZERS_STACK_OWNER_MAP`
  (`glob=project`, from `config.local.sh`). A stack can have several owners — the repo found
  automatically and every owner-map project — and it is kept while **any** of them has a live
  session. The first time
  a stack is seen with no live session it is remembered in `reports/memory/.stack-idle-state`;
  it is stopped once that lasts `ANALYZERS_STACK_IDLE_MIN` (default 30). Unmapped stacks
  (OrbStack's own Kubernetes containers included) are only reported.
  **Liveness is the process's working directory.** A session rooted in repo A that drives
  repo B's stack by absolute path leaves B looking idle and its stack is stopped after the
  grace: map B to A in `ANALYZERS_STACK_OWNER_MAP` (`B-stack=A`), or put B in
  `ANALYZERS_STACK_PROTECT`. Containers stop one at a time (`docker stop -t 20`), with a
  3-minute budget per stack per pass — the rest wait for the next pass — and a dry run never
  starts the grace clock (only a real run records the first sighting). `ANALYZERS_STACK_PROTECT`
  always wins. If a live session's working directory cannot be read, nothing is stopped that
  pass. The dry run lists every stack with its project, mapping, live-session yes/no,
  orphaned-since and the keep / would-stop reason; `docker stop` is never batched and nothing
  is removed. Start a stopped stack again the usual way (`supabase start`, `docker compose up`).
- **Tune:** the `ANALYZERS_DEV_*` knobs in `config.example.sh`. Something you
  start with `nohup` that must stay up belongs in `ANALYZERS_PROTECT_EXTRA`.

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
