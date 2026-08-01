# Storage Toolkit — command reference

The disk suite, in `~/mac-analyzers/storage-analyzer/`. **Everything that deletes files is dry-run / read-only by default** — nothing deletes until you add `--execute` (or `--apply`). (`tm-reclaim.sh` acts immediately because it touches no files — only ephemeral local snapshots.)

```bash
cd ~/mac-analyzers/storage-analyzer    # run the ./ commands below from here
```

| Script | Job | Default |
|--------|-----|---------|
| `analyze.sh` | Scan disk → timestamped Markdown report (incl. last-used "decision" tables) | read-only |
| `cleanup.sh` | Interactive deep-clean: caches, logs, **+ granular per-app uninstall** | dry-run |
| `storage-auto-clean.sh` | Automation-safe sweep for scheduling (protects active work) | dry-run |
| `login-items-audit.sh` | Find + remove login items/agents whose app was uninstalled | dry-run |
| `spotlight-audit.sh` | Spotlight status, stuck-vs-progressing verdict, dev-dir index fencing | dry-run |
| `tm-reclaim.sh` | Release snapshot-pinned space NOW + start a fresh TM backup | acts (no files touched) |
| `storage-manage-agents.sh` | Install / remove the scheduled LaunchAgents | — |

---

**Double-clicking a script in Finder opens an interactive menu** (numbered
options, preview first, confirm apply). Flags skip the menu — that is how the
scheduled agents run. Every run logs the input used.

## I want to…

### …see what's eating my disk
```bash
./analyze.sh                       # writes ~/mac-analyzers/reports/storage/<date>/report-<time>.md
open "$(ls -t ~/mac-analyzers/reports/storage/*/report-*.md | head -1)"
```
The report ends with the decision tables: **§24 Apps** (by last opened), **§25 Downloads**, **§26 Projects**, **§27 Documents/Desktop** — all oldest-first so dead weight floats to the top.

### …clean regenerable junk (caches, logs, trash, build dirs)
```bash
./cleanup.sh                       # DRY RUN — review the list
./cleanup.sh --execute             # actually delete
./cleanup.sh --execute --yes       # delete, no prompts
./cleanup.sh --skip-build-caches --execute   # caches/logs/trash ONLY — spare active .next/.turbo
```
> `cleanup.sh`'s headline total includes **active** `.next`/`.turbo` build caches that rebuild on
> next dev (deleting them = no net gain + slow rebuild). Use `--skip-build-caches` to clean only
> the regenerable app/browser/toolchain caches + logs, and let `storage-auto-clean.sh` handle build caches
> once they're idle >3 days.

### …remove a dead app + ALL its data (granular)
```bash
./cleanup.sh --list-app "Kodi"     # SHOW one app's full footprint, delete nothing
./cleanup.sh --stale-apps          # dry-run the curated stale-app list
./cleanup.sh --stale-apps --execute            # remove them — asks [y/N] per app
./cleanup.sh --app "Loom" --app "Framer" --execute   # target specific apps
```
Sweeps bundle + Application Support, Caches, Containers, HTTPStorages, WebKit,
Saved State, Preferences (+ByHost), Application Scripts, Group Containers,
Cookies, Logs. System-level leftovers (`/Library`, receipts) are **shown for
`sudo`, never auto-deleted**. Running apps are skipped. Edit the `STALE_APPS`
list near the top of `cleanup.sh` to add/remove candidates.

### …make a big cleanup actually free space, then re-protect with a backup
```bash
./tm-reclaim.sh              # thin+delete local TM snapshots, start fresh backup
./tm-reclaim.sh --wait       # same, but block until the backup finishes
./tm-reclaim.sh --no-backup  # reclaim only
./tm-reclaim.sh --dry-run    # inspect, change nothing
```
Run this **after** a `cleanup.sh --execute` session: local snapshots pin the
blocks you just deleted, so `df` doesn't move until they're released. The fresh
backup then captures the post-cleanup state, so the deletions never linger as
"pending" in snapshot history. Real backups on the TM disk are never touched;
OS-update snapshots are left alone. Passwordless with the sudoers rule below.

### …prune old dictation recordings (opt-in; set ANALYZERS_RECORDINGS_DIR)
```bash
./cleanup.sh --recordings-older-than 90            # dry run
./cleanup.sh --recordings-older-than 90 --execute  # delete recordings >90 days
```

---

## Scheduled auto-clean

Two LaunchAgents (installed & loaded; times are defaults — the Mac Analyzers
app's Settings → Schedule pane edits them, and the edits survive reinstalls
and upgrades):
- **daily 08:00** → `--mode daily --apply --docker-running-only` — build caches idle >3 days (incl. any ANALYZERS_EXTRA_CACHE_GLOBS from config.local.sh), + a quick Docker prune **only if Docker is already running** (never boots it)
- **every 3 days** → `--mode deep --apply --docker-images --prune-snapshots` — caches + node_modules of *idle, git-clean* repos; removes **all unused Docker images** (boots Docker if off, then shuts it back down); **thins TM snapshots** so freed space lands immediately

```bash
./storage-manage-agents.sh status          # are they loaded? next run?
./storage-manage-agents.sh install         # (re)install + load
./storage-manage-agents.sh uninstall       # stop + remove
```

Labels are `com.mac-analyzers.storage-autoclean.{daily,deep}`; the plists set
`AbandonProcessGroup` (notification click-handlers survive the run) and
`AssociatedBundleIdentifiers` = `com.mac-analyzers.app`, and with the app
installed they launch the engine through its compiled `agent-runner`, so
Login Items & Extensions attributes the agents to the Mac Analyzers app.

### Make freed space land immediately (one-time setup)
The deep agent's `--prune-snapshots` needs a **scoped, passwordless** sudo rule for
*only* `tmutil thinlocalsnapshots`. Without it, freed space stays "purgeable" until
macOS auto-frees it. Install once (asks for your password, validates via `visudo`):
```bash
./storage-manage-agents.sh sudoers-install      # installs /etc/sudoers.d/tmutil-thin
./storage-manage-agents.sh sudoers-uninstall    # remove it
```
The rule **cannot** delete real backups or run anything but that one command.

### Run auto-clean by hand
```bash
./storage-auto-clean.sh                    # DRY RUN, daily scope (caches only)
./storage-auto-clean.sh --apply            # act, daily
./storage-auto-clean.sh --mode deep --apply --prune-snapshots    # deep + reclaim snapshot space
./storage-auto-clean.sh --apply --docker            # prune Docker (boots+stops it if off)
./storage-auto-clean.sh --apply --docker-running-only   # prune Docker only if already up
./storage-auto-clean.sh --apply --docker-images     # + remove ALL unused images (big reclaim)
./storage-auto-clean.sh --apply --docker-volumes    # + prune volumes — ⚠ DATA loss, manual only
```
Tunables: `--cache-age-days N` (default 3) · `--nm-age-days N` (default 14).
Logs to `~/mac-analyzers/reports/storage/auto-clean.log`. Fires a macOS
notification each run via `../lib/notify.sh` (menu-bar app → alerter →
osascript — see the root README's Notifications section; clicking one opens
the log). With the app installed, the storage log opens as a structured
pane — runs grouped by project, sorted by reclaimable size — and the
login-items audit as verdict cards with per-row copyable `sudo` commands;
"Open in TextEdit" keeps the raw file a click away.

**Docker lifecycle:** prunes if running; if stopped, the deep job starts Docker
Desktop, prunes, then quits it again — but **only quits if the script started it**
(a Docker you left open stays open). Volumes are never pruned unless `--docker-volumes`.

---

## ⚠️ Gotcha: deleted GBs but free space didn't move?

A **Time Machine local snapshot** is pinning the freed blocks (shows as
"purgeable"). macOS auto-purges under pressure; the deep agent now thins them
automatically (once the sudoers rule is installed). To force it by hand:
```bash
./tm-reclaim.sh                # release now + fresh backup (preferred)
sudo tmutil thinlocalsnapshots / 999999999999 4     # raw one-liner equivalent
```

## Biggest non-script levers (manual)
- **Docker volumes / file shrink** — `--docker-images` reclaims unused images; to also
  remove unused *volumes* run `docker volume prune` yourself (it can delete dev DB data).
  To shrink the `Docker.raw` file itself: Docker Desktop → Troubleshoot → "Clean / Purge data".

---
_Report output: `~/mac-analyzers/reports/storage/` · scripts: `~/mac-analyzers/storage-analyzer/`_
