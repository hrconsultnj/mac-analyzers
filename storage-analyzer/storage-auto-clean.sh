#!/usr/bin/env bash
# auto-clean.sh — automation-SAFE storage maintenance (companion to analyze.sh / cleanup.sh)
# ---------------------------------------------------------------------------
# Purpose: be safe to run UNATTENDED on a schedule (launchd). Unlike cleanup.sh
# (which is an interactive, reviewed deep-clean), this script NEVER touches the
# code you are actively working on:
#
#   * Build caches (.next/.turbo/dist/build/.vite/.svelte-kit/.nuxt/.parcel-cache)
#     are removed ONLY if the cache dir itself hasn't been written in N days
#     (--cache-age-days, default 3). If a dev server/build ran recently, skip.
#
#   * Turborepo caches never evict themselves, and an active repo is never
#     idle long enough for the rule above — so each repo's .turbo/cache is
#     capped (ANALYZERS_TURBO_CACHE_MAX_GB, default 2): oldest entries beyond
#     the cap go on every run. Skipped while turbo is running.
#
#   * node_modules is removed ONLY for STALE repos — no source file modified in
#     M days (--nm-age-days / ANALYZERS_NM_AGE_DAYS, default 14) AND a clean
#     git working tree (ANALYZERS_NM_REQUIRE_CLEAN=0 drops that second test —
#     source files are never touched either way). A repo something live runs
#     from (a process, or a loaded LaunchAgent) is always left intact.
#
#   * Tool caches (ANALYZERS_TOOL_CACHES, opt-in per id): package managers,
#     every app's ~/Library/Caches folder, never-booted simulators, emulator
#     snapshots, downloaded aerial wallpapers. Rebuildable / re-downloadable
#     only — never sources, never state. The heavier ids run in deep mode.
#
#   * Package-manager caches: pnpm store prune drops UNREFERENCED data only,
#     but `npm cache clean --force` empties the ENTIRE npm cache (_cacache).
#
#   * Time Machine LOCAL SNAPSHOTS: by default just ALERTS you (macOS
#     notification) with the reclaimable amount. Pass --prune-snapshots to thin
#     snapshots older than --snapshot-keep-days. The actual TM backup on the
#     destination disk is NEVER touched.
#
# SAFE BY DEFAULT: dry-run unless --apply is passed. A macOS notification
# summarises every run.
#
# Usage:
#   ./storage-auto-clean.sh                      # dry run, mode=daily (build caches only)
#   ./storage-auto-clean.sh --apply              # act, daily
#   ./storage-auto-clean.sh --mode deep          # dry run, deep (caches + node_modules + TM)
#   ./storage-auto-clean.sh --mode deep --apply  # act, deep
#   ./storage-auto-clean.sh --mode deep --apply --prune-snapshots   # also thin TM snapshots (needs sudoers rule)
#   ./storage-auto-clean.sh --apply --docker                        # + prune Docker (start→prune→stop if it was off)
#   ./storage-auto-clean.sh --apply --docker-running-only           # + prune Docker ONLY if already running (daily job)
#   ./storage-auto-clean.sh --apply --docker-images                 # + remove ALL unused images (the big reclaim)
#   ./storage-auto-clean.sh --apply --docker-volumes                # + prune volumes — ⚠ DATA loss; manual only
#
# Tunables: --cache-age-days N  --nm-age-days N  --worktree-idle-days N  --snapshot-keep-days N
#           --roots "dir1 dir2"  (default: ~/Projects)
# Docker:   starts the container runtime (OrbStack or Docker Desktop, whichever
#           backs the docker CLI here) only if not already running, prunes, then
#           quits it again ONLY if this script started it. Volumes never pruned
#           unless --docker-volumes.
# ---------------------------------------------------------------------------

set -u
shopt -s nullglob

# ---------- defaults ----------
HOME_DIR="${HOME}"
MODE="daily"                 # daily | deep
DRY_RUN=1
ONLY_PATHS=""
PRUNE_SNAPSHOTS=0           # reclaim snapshot-pinned space via tmutil thinlocalsnapshots (needs sudoers rule)
DOCKER=0                    # prune Docker (start it if needed, shut back down if WE started it)
DOCKER_NO_START=0          # only prune if Docker is ALREADY running (don't boot it) — for the daily job
DOCKER_IMAGES=0            # also `docker image prune -a` (all unused images) — safe, re-pullable
DOCKER_VOLUMES=0           # also `docker volume prune` — ⚠ DATA loss; manual/opt-in only, never in the agents
CACHE_AGE_DAYS=3             # build cache untouched for >N days -> removable
NM_AGE_DAYS=14              # repo idle for >N days -> node_modules removable
SNAPSHOT_KEEP_DAYS=5        # keep TM local snapshots newer than N days
ROOTS="${HOME_DIR}/Projects"
LOG_DIR="${HOME_DIR}/mac-analyzers/reports/storage"

# optional per-machine config (gitignored) — see config.example.sh at repo root
ANALYZERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Settings live in the user folder. When the engine runs from inside the
# app bundle, that bundle is replaced wholesale on every update, so the
# user copy is the one that must win.
[[ -f "${ANALYZERS_ROOT}/config.local.sh" ]] && source "${ANALYZERS_ROOT}/config.local.sh"
[[ -f "$HOME/mac-analyzers/config.local.sh" && "${ANALYZERS_ROOT}" != "$HOME/mac-analyzers" ]] \
  && source "$HOME/mac-analyzers/config.local.sh"
LOG_FILE="${LOG_DIR}/auto-clean.log"
LOCK_FILE="${LOG_DIR}/.auto-clean.lock"

# Knobs the app writes into config.local.sh; the CLI flags below still win.
NM_AGE_DAYS="${ANALYZERS_NM_AGE_DAYS:-$NM_AGE_DAYS}"
NM_REQUIRE_CLEAN="${ANALYZERS_NM_REQUIRE_CLEAN:-1}"
TURBO_MAX_GB="${ANALYZERS_TURBO_CACHE_MAX_GB:-2}"

BUILD_CACHE_NAMES=( .next .turbo dist build .vite .svelte-kit .nuxt .parcel-cache )
# The same names as find operands (-name a -o -name b …), so the find
# expressions below cannot drift from this one list.
BUILD_CACHE_FIND=()
for cache_name in "${BUILD_CACHE_NAMES[@]}"; do
  [[ ${#BUILD_CACHE_FIND[@]} -gt 0 ]] && BUILD_CACHE_FIND+=( -o )
  BUILD_CACHE_FIND+=( -name "$cache_name" )
done
unset cache_name
# An empty list would make the find expressions below invalid, and a find that
# fails reads as "nothing recent here" — every project would look idle. Stop.
if [[ ${#BUILD_CACHE_FIND[@]} -eq 0 ]]; then
  echo "storage-auto-clean: the list of build-cache folder names is empty — refusing to run." >&2
  exit 78
fi

# ---------- args ----------
ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)               MODE="${2:-daily}"; shift ;;
    --apply)              DRY_RUN=0 ;;
    --dry-run)            DRY_RUN=1 ;;
    --prune-snapshots)    PRUNE_SNAPSHOTS=1 ;;
    --docker)             DOCKER=1 ;;
    --docker-running-only) DOCKER=1; DOCKER_NO_START=1 ;;
    --docker-images)      DOCKER=1; DOCKER_IMAGES=1 ;;
    --docker-volumes)     DOCKER=1; DOCKER_VOLUMES=1 ;;
    --cache-age-days)     CACHE_AGE_DAYS="${2:-3}"; shift ;;
    --nm-age-days)        NM_AGE_DAYS="${2:-14}"; shift ;;
    --worktree-idle-days) WT_IDLE_DAYS_FLAG="${2:-0}"; shift ;;
    --snapshot-keep-days) SNAPSHOT_KEEP_DAYS="${2:-5}"; shift ;;
    --roots)              ROOTS="${2:-}"; shift ;;
    --only-paths)         ONLY_PATHS="${2:-}"; shift ;;
    -h|--help)            sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$MODE" in daily|deep) ;; *) echo "--mode must be daily|deep" >&2; exit 2 ;; esac

# ---------- interactive menu (double-click / bare terminal run) ----------
# The scheduled agents pass flags (and have no TTY) — they never see this.
INTERACTIVE=0
INVOKED="flags: ${ORIG_ARGS:-(none — defaults)}"
if [[ -z "$ORIG_ARGS" ]] && { [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; }; then
  INTERACTIVE=1
  echo ""
  echo "  storage-auto-clean — disk space maintenance"
  echo "  -------------------------------------------"
  echo "  1) Preview daily clean (stale build caches)"
  echo "  2) Apply daily clean"
  echo "  3) Preview deep clean (+ node_modules of idle repos, idle worktrees — never main, package & app caches, TM)"
  echo "  4) Apply deep clean (+ thin TM snapshots, prune Docker images)"
  echo "  q) Quit"
  echo ""
  read -rp "  Choose [1]: " choice
  case "${choice:-1}" in
    1) ;;
    2) DRY_RUN=0 ;;
    3) MODE="deep" ;;
    4) MODE="deep"; DRY_RUN=0; PRUNE_SNAPSHOTS=1; DOCKER=1; DOCKER_IMAGES=1 ;;
    q|Q) exit 0 ;;
    *) echo "  Unknown choice '${choice}' — exiting."; exit 2 ;;
  esac
  INVOKED="interactive menu: choice ${choice:-1}"
fi

mkdir -p "$LOG_DIR"

# ---------- single-instance lock ----------
if [[ -e "$LOCK_FILE" ]]; then
  if kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "auto-clean already running (pid $(cat "$LOCK_FILE")); exiting." >&2
    exit 0
  fi
fi
echo "$$" > "$LOCK_FILE"
cleanup_tmp() {
  rm -f "$LOCK_FILE" ${RUNTIME_ROOTS_FILE:+"$RUNTIME_ROOTS_FILE"} \
        ${STALE_LIST:+"$STALE_LIST"} ${ACTIVE_LIST:+"$ACTIVE_LIST"} ${WT_LIST:+"$WT_LIST"}
}
trap cleanup_tmp EXIT

# ---------- helpers ----------
TOTAL_KB=0
TS_NOW="$(date '+%Y-%m-%d %H:%M:%S')"

human() {  # KB -> human
  awk -v kb="$1" 'BEGIN{
    if (kb>=1048576) printf "%.1f GB", kb/1048576;
    else if (kb>=1024) printf "%.0f MB", kb/1024;
    else printf "%d KB", kb }'
}

log() { echo "$*" | tee -a "$LOG_FILE"; }

# shared notifier — with alerter installed, clicking the notification opens
# this script's log (see lib/notify.sh); inline fallback keeps it standalone.
if [[ -f "${ANALYZERS_ROOT}/lib/notify.sh" ]]; then
  source "${ANALYZERS_ROOT}/lib/notify.sh"
else
  notify() {  # title, message  (no-op if osascript missing / headless)
    command -v osascript >/dev/null 2>&1 || return 0
    osascript -e "display notification \"${2//\"/\'}\" with title \"${1//\"/\'}\" sound name \"Glass\"" >/dev/null 2>&1 || true
  }
fi

group() { log ""; log "### $1"; }

# --only-paths <file>: act ONLY on paths listed in the file, one per line.
# The sweep still derives its own findings from scratch — an approved set can
# only ever SHRINK what gets touched. A list that went stale between the
# preview and the apply is therefore safe by construction.
approved() {
  [[ -z "${ONLY_PATHS}" ]] && return 0
  approved_list_has "$1"
}

# Commands that are not paths (a prune, a cleanup) are reviewed as rows too,
# keyed `prune:<id>` — a form that can never be mistaken for a path. With a
# reviewed list such a command runs only when its own key is in it; with no list
# (the schedule, a Terminal run) it runs as it always has.
command_approved() {
  [[ -z "${ONLY_PATHS}" ]] && return 0
  approved_list_has "$1"
}

# The reviewed list is read once (lib/approved-list.sh): a `grep` per item made a
# 6,000-item apply take minutes. A list that cannot be checked stops the run.
if [[ -n "${ONLY_PATHS}" ]]; then
  if ! source "${ANALYZERS_ROOT}/lib/approved-list.sh" 2>/dev/null; then
    echo "FATAL: lib/approved-list.sh is missing — refusing to run with a reviewed list it cannot check." >&2
    exit 78
  fi
  approved_list_load "${ONLY_PATHS}"
fi

# reclaim <path>  — size-aware, dry-run-aware, accumulates TOTAL_KB
reclaim() {
  local p="$1"
  [[ -e "$p" ]] || return 0
  if ! approved "$p"; then
    log "  [SKIP]    not in approved set  $p"
    return 0
  fi
  local kb; kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
  TOTAL_KB=$((TOTAL_KB + kb))
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "  [DRY]     $(printf '%10s' "$(human "$kb")")  $p"
  else
    # some tools write their caches read-only (dotslash, Go modules) — give
    # the owner write access back before the second attempt
    if rm -rf "$p" 2>/dev/null || { chmod -R u+w "$p" 2>/dev/null; rm -rf "$p" 2>/dev/null; }; then
      log "  [DELETED] $(printf '%10s' "$(human "$kb")")  $p"
    else
      log "  [FAILED]  $(printf '%10s' "$(human "$kb")")  $p"
    fi
  fi
}

# nearest ancestor dir containing .git  (echoes path, or empty)
repo_root() {
  local d="$1"
  while [[ "$d" != "/" && -n "$d" ]]; do
    [[ -d "$d/.git" || -f "$d/.git" ]] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

# is_idle <dir> <days>  -> exit 0 if NO meaningful file modified within <days>
# (ignores heavy regenerable dirs so a fresh build cache doesn't mark a repo active)
is_idle() {
  local dir="$1" days="$2" hit
  hit=$(find "$dir" \
        \( -name node_modules -o -name .git -o -name .cache -o "${BUILD_CACHE_FIND[@]}" \) -prune \
        -o -type f -mtime "-${days}" -print -quit 2>/dev/null)
  [[ -z "$hit" ]]
}

# cmd_reclaim <path> <kb> <command...> — reclaim() for things the owning tool
# must remove itself (read-only Go module cache, simulator runtimes): same
# approval check, same log lines, but runs <command> instead of rm -rf.
cmd_reclaim() {
  local p="$1" kb="$2"; shift 2
  if ! approved "$p"; then
    log "  [SKIP]    not in approved set  $p"
    return 0
  fi
  TOTAL_KB=$((TOTAL_KB + kb))
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "  [DRY]     $(printf '%10s' "$(human "$kb")")  $p"
  elif "$@" >>"$LOG_FILE" 2>&1; then
    log "  [DELETED] $(printf '%10s' "$(human "$kb")")  $p"
  else
    log "  [FAILED]  $(printf '%10s' "$(human "$kb")")  $p"
  fi
}

# protected <name> — the user's protect list (ANALYZERS_PROTECT_EXTRA, regex
# alternatives) always wins, here as in the memory guard.
protected() {
  [[ -n "${ANALYZERS_PROTECT_EXTRA:-}" ]] || return 1
  printf '%s\n' "$1" | grep -qiE -- "${ANALYZERS_PROTECT_EXTRA}"
}

# Repo roots something LIVE runs from — a running process whose command line
# names a path under the roots, or a LOADED LaunchAgent pointing there. The
# idle clock can't see these (a bridge or a backup job edits nothing), so
# their node_modules are never removed. Built once, on first use.
RUNTIME_ROOTS_FILE=""
is_runtime_root() {  # <dir> [fresh] — "fresh" rescans now instead of using the run's cached list
  if [[ "${2:-}" == "fresh" && -n "$RUNTIME_ROOTS_FILE" ]]; then rm -f "$RUNTIME_ROOTS_FILE"; RUNTIME_ROOTS_FILE=""; fi
  if [[ -z "$RUNTIME_ROOTS_FILE" ]]; then
    RUNTIME_ROOTS_FILE="$(mktemp -t autoclean-runtime)"
    local roots_re="" r loaded plist p rr
    for r in $ROOTS; do roots_re="${roots_re:+${roots_re}|}$(printf '%s' "$r" | sed 's/[.[\*^$+?(){}|]/\\&/g')"; done
    loaded="$(launchctl list 2>/dev/null | awk 'NR>1{print $3}')"
    {
      ps -axo command= 2>/dev/null
      # working directories too: a shell or agent session sitting in a
      # checkout names no path on its command line
      lsof -a -u "$(id -u)" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | sed 's#$#/#'
      for plist in "$HOME"/Library/LaunchAgents/*.plist; do
        printf '%s\n' "$loaded" | grep -qxF "$(basename "$plist" .plist)" && cat "$plist"
      done
    } | grep -oE "(${roots_re})/[^ <\"']+" | sort -u | while IFS= read -r p; do
      rr="$(repo_root "$p" || true)"; [[ -n "$rr" ]] && echo "$rr"
    done | sort -u > "$RUNTIME_ROOTS_FILE"
  fi
  grep -qxF -- "$1" "$RUNTIME_ROOTS_FILE"
}

# Docker prune. If the daemon isn't running, start Docker Desktop, prune, then
# quit it — but ONLY quit if WE started it (a Docker you left running stays up).
# Never touches volumes unless --docker-volumes (data-loss risk).
# Which container runtime backs the `docker` CLI on THIS Mac. OrbStack is a
# drop-in for the CLI but a different app — starting/quitting "Docker" would
# be wrong (and on an OrbStack-only Mac, impossible).
container_app() {
  local ctx
  ctx="$(docker context show 2>/dev/null || true)"
  if [[ "$ctx" == *orbstack* ]] || [[ -d "/Applications/OrbStack.app" && ! -d "/Applications/Docker.app" ]]; then
    echo "OrbStack"
  else
    echo "Docker"
  fi
}

docker_maint() {
  command -v docker >/dev/null 2>&1 || { log "  docker CLI not found; skipping."; return 0; }
  local RUNTIME_APP; RUNTIME_APP="$(container_app)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    local extra=""
    [[ "$DOCKER_IMAGES" -eq 1 ]]  && extra="${extra} ; image prune -a -f"
    [[ "$DOCKER_VOLUMES" -eq 1 ]] && extra="${extra} ; volume prune -f (⚠ DATA)"
    if docker info >/dev/null 2>&1; then
      log "  [DRY] prune:docker  Docker is running: unused containers, networks and images are removed${extra} (size not known until it runs)"
    elif [[ "$DOCKER_NO_START" -eq 1 ]]; then
      log "  [DRY] Docker stopped → would SKIP (running-only mode)"
    else
      log "  [DRY] prune:docker  Docker is stopped: it is started, pruned${extra} and shut down again (size not known until it runs)"
    fi
    return 0
  fi
  command_approved prune:docker || { log "  [SKIP]    prune:docker  not in the reviewed list"; return 0; }
  local started=0 i=0
  if ! docker info >/dev/null 2>&1; then
    if [[ "$DOCKER_NO_START" -eq 1 ]]; then
      log "  Docker not running — skipping (running-only mode; won't boot it)."; return 0
    fi
    log "  container runtime not running — starting ${RUNTIME_APP}…"
    open -a "${RUNTIME_APP}" 2>/dev/null || open -a "Docker Desktop" 2>/dev/null || { log "  couldn't launch ${RUNTIME_APP}; skipping."; return 0; }
    started=1
    until docker info >/dev/null 2>&1; do
      sleep 3; i=$((i+1))
      if [[ $i -ge 40 ]]; then
        log "  ${RUNTIME_APP} didn't become ready (~120s) — shutting it back down, skipping."
        osascript -e "quit app \"${RUNTIME_APP}\"" 2>/dev/null || true
        return 0
      fi
    done
    log "  ${RUNTIME_APP} ready (started by auto-clean)."
  else
    log "  ${RUNTIME_APP} already running — pruning, will leave it running."
  fi
  log "  running: docker system prune -f"; docker system prune -f >>"$LOG_FILE" 2>&1 || true
  if [[ "$DOCKER_IMAGES" -eq 1 ]]; then
    log "  running: docker image prune -a -f (all unused images)"; docker image prune -a -f >>"$LOG_FILE" 2>&1 || true
  fi
  if [[ "$DOCKER_VOLUMES" -eq 1 ]]; then
    log "  running: docker volume prune -f  (⚠ removes unused volumes — DATA)"; docker volume prune -f >>"$LOG_FILE" 2>&1 || true
  fi
  if [[ "$started" -eq 1 ]]; then
    log "  shutting ${RUNTIME_APP} back down (auto-clean started it)…"
    osascript -e "quit app \"${RUNTIME_APP}\"" 2>/dev/null || pkill -f "${RUNTIME_APP}" 2>/dev/null || true
  fi
}

# ---------- header ----------
log "=================================================================="
log " storage-auto-clean.sh  |  mode=${MODE}  |  $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY')  |  ${TS_NOW}"
log " roots=${ROOTS}  cache>${CACHE_AGE_DAYS}d  nm>${NM_AGE_DAYS}d$([[ "$NM_REQUIRE_CLEAN" == "1" ]] && echo '(clean)' || echo '(any)')  turbo<=${TURBO_MAX_GB}GB  snap-keep=${SNAPSHOT_KEEP_DAYS}d"
log " input: ${INVOKED}"
log "=================================================================="

# ---------- 1. Build caches (both modes) ----------
group "1. Build caches not written in >${CACHE_AGE_DAYS} days (regenerable)"
for root in $ROOTS; do
  [[ -d "$root" ]] || continue
  # process substitution (not a pipe) so reclaim() updates TOTAL_KB in THIS shell
  while IFS= read -r d; do
    case "$d" in */node_modules/*) continue ;; esac
    # only if the cache dir itself is older than the threshold (no recent build)
    if [[ -z "$(find "$d" -prune -mtime "-${CACHE_AGE_DAYS}" -print 2>/dev/null)" ]]; then
      reclaim "$d"
    fi
  done < <(find "$root" -type d \( "${BUILD_CACHE_FIND[@]}" \) -prune 2>/dev/null)
done

# ---------- 1.2 Turborepo cache cap (both modes) ----------
# turbo never evicts its local cache: every build adds a tarball of the task's
# outputs, and a Next.js app whose turbo.json doesn't exclude .next/dev adds
# GBs per build. A deleted entry is only a cache miss on the next build.
TURBO_MAX_KB=$(( TURBO_MAX_GB * 1048576 ))
group "1.2 Turborepo cache entries beyond ${TURBO_MAX_GB} GB per repo"
# A running turbo is tied to its repo by the node_modules path it runs from;
# one we can't place (a global install) pauses the cap everywhere.
TURBO_PS="$(ps -axo command= 2>/dev/null | grep -E '(^|/)turbo (run|build|watch|daemon)' || true)"
turbo_busy() {
  [[ -n "$TURBO_PS" ]] || return 1
  printf '%s\n' "$TURBO_PS" | grep -qF -- "$1/" && return 0
  printf '%s\n' "$TURBO_PS" | grep -qv "/node_modules/"
}
for root in $ROOTS; do
  [[ -d "$root" ]] || continue
  while IFS= read -r cdir; do
    case "$cdir" in */node_modules/*) continue ;; esac
    trepo="$(repo_root "$cdir" || dirname "$(dirname "$cdir")")"
    if turbo_busy "$trepo"; then log "  (turbo is running in ${trepo} — its cache left alone this run)"; continue; fi
    entries=( "$cdir"/*.tar.zst "$cdir"/*.tar.gz )
    [[ ${#entries[@]} -gt 0 ]] || continue   # never hand ls an empty list
    kept=0
    # newest first: keep entries until the cap, reclaim the rest
    while IFS= read -r entry; do
      kb=$(du -sk "$entry" 2>/dev/null | cut -f1); kb="${kb:-0}"
      if (( kept + kb <= TURBO_MAX_KB )); then kept=$((kept + kb)); continue; fi
      reclaim "$entry"
      [[ "$DRY_RUN" -eq 0 && ! -e "$entry" ]] && rm -f "${entry%.tar.*}-meta.json"
    done < <(ls -t "${entries[@]}")
  done < <(find "$root" -type d -path "*/.turbo/cache" -prune 2>/dev/null)
done

# ---------- 1.5 Extra cache globs from config (both modes) ----------
# App-generated per-project caches outside ~/Projects (set
# ANALYZERS_EXTRA_CACHE_GLOBS in config.local.sh). Same age window as above.
EXTRA_CACHE_AGE_DAYS=7
group "1.5 Extra cache globs (config) not written in >${EXTRA_CACHE_AGE_DAYS} days"
if [[ -n "${ANALYZERS_EXTRA_CACHE_GLOBS+x}" ]]; then
  for g in "${ANALYZERS_EXTRA_CACHE_GLOBS[@]}"; do
    for d in $g; do
      [[ -d "$d" ]] || continue
      if [[ -z "$(find "$d" -prune -mtime "-${EXTRA_CACHE_AGE_DAYS}" -print 2>/dev/null)" ]]; then
        reclaim "$d"
      fi
    done
  done
else
  log "  (none configured)"
fi

# ---------- 1.8 Git worktrees (deep mode, opt-in) ----------
# A worktree is a second checkout of a repo — coding agents create them by
# the dozen (.composure/workspaces, .claude/worktrees, …). Once one has been
# idle N days (ANALYZERS_WORKTREE_IDLE_DAYS; 0 or unset = this section is
# off) it can go, merged or not, because nothing in it is lost:
#   * its commits stay on its branch — `git worktree add <path> <branch>`
#     brings the checkout back (a detached checkout goes only when a branch
#     or tag already holds its commit);
#   * uncommitted and untracked changes are parked as a commit pinned under
#     refs/parked/<worktree>-<time> (built with commit-tree, so the repo's
#     shared stash list is never written to and gc never expires them);
#   * ignored files that aren't build output (.env, local databases, keys,
#     planning notes) are copied to reports/storage/parked-worktrees/ first.
# Every removal lands in reports/storage/worktree-removals.md with the exact
# commands that undo it. Never removed: anything on `main` (the branch, or a
# worktree folder named main), the primary checkout, locked worktrees, ones
# with submodules, and anything a process or a terminal/agent session runs
# from or sits in.
WT_IDLE_DAYS="${WT_IDLE_DAYS_FLAG:-${ANALYZERS_WORKTREE_IDLE_DAYS:-0}}"
WT_PARK_MAX_MB="${ANALYZERS_WORKTREE_PARK_MAX_MB:-1024}"
WT_LIST=""
if [[ "$MODE" == "deep" && "$WT_IDLE_DAYS" -gt 0 ]]; then
  group "1.8 Git worktrees idle >${WT_IDLE_DAYS}d — main is never removed"
  WT_LIST="$(mktemp -t autoclean-wt)"
  WT_PARK_ROOT="${LOG_DIR}/parked-worktrees/$(date +%Y-%m-%d)"
  WT_MANIFEST="${LOG_DIR}/worktree-removals.md"
  wt_kept=0; wt_main=0; wt_stale=0
  # Where a worktree's commits already live — reported, not required: the
  # branch keeps them either way. Merged into what the primary checkout has
  # checked out, or any base branch (development, develop, main, master;
  # local or origin), squash and rebase merges included.
  wt_targets() {  # <repo> -> merge targets, one per line
    local b r
    echo "HEAD"
    for b in development develop main master; do
      for r in "refs/heads/$b" "refs/remotes/origin/$b"; do
        git -C "$1" rev-parse -q --verify "$r" >/dev/null 2>&1 && echo "$r"
      done
    done
  }
  wt_label() {  # <repo> <target>
    if [[ "$2" == "HEAD" ]]; then
      echo "the current checkout ($(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null))"
    else
      echo "${2#refs/*/}"
    fi
  }
  wt_merged_into() {  # <repo> <sha> -> label of the first target that has it
    local t tree
    for t in $(wt_targets "$1"); do
      git -C "$1" merge-base --is-ancestor "$2" "$t" 2>/dev/null \
        && { wt_label "$1" "$t"; return 0; }
    done
    # Squash and rebase merges leave no ancestry. Trial-merge instead (nothing
    # is written to any branch): if merging the worktree's commit into the
    # target yields the target's own tree, its changes are already in.
    for t in $(wt_targets "$1"); do
      tree="$(git -C "$1" merge-tree --write-tree "$t" "$2" 2>/dev/null | head -1)"
      [[ -n "$tree" && "$tree" == "$(git -C "$1" rev-parse "$t^{tree}" 2>/dev/null)" ]] \
        && { echo "$(wt_label "$1" "$t") (squash or rebase merge)"; return 0; }
    done
    return 1
  }
  # Ignored files are invisible to `status --porcelain`, but `worktree remove`
  # deletes them — and an .env, a local database or a key is on no branch and
  # no remote. Build output is regenerated; everything else is copied aside.
  WT_REBUILDABLE='node_modules|\.next|\.turbo|dist|build|out|\.output|\.vite|\.svelte-kit|\.nuxt|\.parcel-cache|\.cache|coverage|\.nyc_output|\.venv|venv|__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.tox|target|\.expo|\.gradle|Pods|DerivedData|\.build|\.swiftpm|\.pnpm-store|\.eslintcache|\.DS_Store|next-env\.d\.ts|.*\.tsbuildinfo|.*\.pyc|.*\.log|\.wrangler|test-results|playwright-report'
  # whole relative paths that are rebuildable or per-session noise
  WT_REBUILDABLE_PATH='(.*/)?\.moon/cache|\.composure/(graph|current-task\.json|last-health-check|orient-shown|task-sync-debug\.jsonl)'
  wt_precious_ignored() {  # <worktree> -> ignored paths (relative) that are NOT rebuildable
    git -C "$1" status --porcelain -z --ignored=matching 2>/dev/null | tr '\0' '\n' \
      | sed -n 's/^!! //p' \
      | while IFS= read -r p; do
          p="${p%/}"
          printf '%s\n' "${p##*/}" | grep -qxE -- "$WT_REBUILDABLE" && continue
          printf '%s\n' "$p" | grep -qxE -- "$WT_REBUILDABLE_PATH" && continue
          echo "$p"
        done
  }
  wt_manifest() {  # <markdown table row>
    if [[ ! -f "$WT_MANIFEST" ]]; then
      printf '%s\n' "# Worktrees removed by storage auto-clean" "" \
        "Each row says how to bring a worktree back exactly as it was: re-create the checkout on its branch, re-apply its parked changes, copy its local-only files back." "" \
        "| When | Worktree | Branch | Parked changes | Local-only files | Restore |" \
        "|---|---|---|---|---|---|" > "$WT_MANIFEST"
    fi
    printf '%s\n' "$1" >> "$WT_MANIFEST"
  }
  wt_consider() {  # <repo> <worktree> <head-sha> <branch|""> <locked 0|1>
    local repo="$1" wt="$2" sha="$3" br="$4" locked="$5"
    local name why merged kb dirty precious pkb=0 ukb=0 park="" pcommit="" pin="" rel restore note tmpidx ptree
    [[ -d "$wt" ]] || return 0
    # linked worktrees carry a .git FILE; a .git directory is a primary checkout
    [[ -f "$wt/.git" ]] || return 0
    name="${wt##*/}"
    # main is never removed — the branch, or a worktree folder named main
    if [[ "$br" == "main" || "$name" == "main" ]]; then wt_main=$((wt_main+1)); return 0; fi
    [[ "$locked" == "1" ]] && { wt_kept=$((wt_kept+1)); return 0; }
    is_runtime_root "$wt" && { wt_kept=$((wt_kept+1)); return 0; }
    is_idle "$wt" "$WT_IDLE_DAYS" || { wt_kept=$((wt_kept+1)); return 0; }
    if [[ -n "$(git -C "$wt" submodule status 2>/dev/null)" ]]; then
      wt_kept=$((wt_kept+1)); log "  (kept ${wt} — it has submodules; remove it by hand)"; return 0
    fi
    if [[ -n "$br" ]]; then
      if merged="$(wt_merged_into "$repo" "$sha")"; then why="${br} — merged into ${merged}"
      else why="${br} — not merged yet; the branch keeps its commits"; fi
    else
      if [[ -z "$(git -C "$repo" for-each-ref --contains "$sha" --count=1 2>/dev/null)" ]]; then
        wt_kept=$((wt_kept+1)); log "  (kept ${wt} — detached at a commit no branch or tag holds)"; return 0
      fi
      why="detached — its commit is already on a branch"
    fi
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | grep -c . || true)"
    precious="$(wt_precious_ignored "$wt")"
    if [[ -n "$precious" ]]; then
      pkb="$(cd "$wt" && printf '%s\n' "$precious" | tr '\n' '\0' | xargs -0 du -sk 2>/dev/null | awk '{t += $1} END {print t + 0}')"
      if (( pkb > WT_PARK_MAX_MB * 1024 )); then
        wt_kept=$((wt_kept+1))
        log "  (kept ${wt} — $(human "$pkb") of local-only files is over the ${WT_PARK_MAX_MB} MB parking limit)"
        return 0
      fi
    fi
    # untracked files are parked in the pinned commit too, so they get the same size cap
    if [[ -n "$(git -C "$wt" ls-files -o --exclude-standard 2>/dev/null | head -1)" ]]; then
      ukb="$(cd "$wt" && git ls-files -o --exclude-standard -z 2>/dev/null | xargs -0 du -sk 2>/dev/null | awk '{t += $1} END {print t + 0}')"
      if (( ukb > WT_PARK_MAX_MB * 1024 )); then
        wt_kept=$((wt_kept+1))
        log "  (kept ${wt} — $(human "$ukb") of untracked files is over the ${WT_PARK_MAX_MB} MB parking limit)"
        return 0
      fi
    fi
    echo "$wt" >> "$WT_LIST"
    kb=$(du -sk "$wt" 2>/dev/null | cut -f1); kb="${kb:-0}"
    if ! approved "$wt"; then log "  [SKIP]    not in approved set  $wt"; return 0; fi
    TOTAL_KB=$((TOTAL_KB + kb))
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [DRY]     $(printf '%10s' "$(human "$kb")")  $wt"
      log "              ↳ ${why}"
      [[ "$dirty" -gt 0 ]] && log "              ↳ ${dirty} uncommitted change(s) — parked as a pinned commit first (not in the shared stash)"
      [[ -n "$precious" ]] && log "              ↳ $(printf '%s\n' "$precious" | grep -c .) local-only file(s), $(human "$pkb") — copied aside first: $(printf '%s\n' "$precious" | head -3 | tr '\n' ' ')"
      return 0
    fi
    # 1. copy local-only files aside
    if [[ -n "$precious" ]]; then
      # mirror the repo's path under $HOME, so two repos named alike never share a folder
      park="${WT_PARK_ROOT}/${repo#"$HOME"/}/${name}"
      while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        if ! { mkdir -p "$park/$(dirname "$rel")" && ditto "$wt/$rel" "$park/$rel"; } 2>>"$LOG_FILE"; then
          log "  [FAILED]  $(printf '%10s' "$(human "$kb")")  $wt"
          log "              ↳ couldn't copy ${rel} aside — left as it was"
          return 0
        fi
      done <<< "$precious"
    fi
    # 2. park uncommitted + untracked changes as a commit pinned under refs/parked/. It is built in a
    #    throwaway index with commit-tree, so the repo's stash list (shared by every session and worktree,
    #    where a bare `git stash pop` elsewhere would apply it, and where another session's entry could be
    #    mistaken for ours) is never written to, and gc cannot expire it.
    if [[ "$dirty" -gt 0 ]]; then
      pin="refs/parked/$(printf '%s' "$name" | tr -c 'A-Za-z0-9_-' '-')-$(date +%Y%m%d-%H%M%S)"
      tmpidx="$(mktemp -t wt-park-idx)"; rm -f "$tmpidx"
      ptree="$(GIT_INDEX_FILE="$tmpidx" git -C "$wt" add -A >>"$LOG_FILE" 2>&1 \
               && GIT_INDEX_FILE="$tmpidx" git -C "$wt" write-tree 2>>"$LOG_FILE")"
      rm -f "$tmpidx"
      pcommit=""
      if [[ -n "$ptree" ]]; then
        pcommit="$(printf 'auto-clean %s: uncommitted and untracked changes of %s (%s)\n' "$(date +%F)" "$name" "${br:-detached}" \
                   | GIT_AUTHOR_NAME="mac-analyzers" GIT_AUTHOR_EMAIL="mac-analyzers@localhost" \
                     GIT_COMMITTER_NAME="mac-analyzers" GIT_COMMITTER_EMAIL="mac-analyzers@localhost" \
                     git -C "$wt" commit-tree "$ptree" -p HEAD 2>>"$LOG_FILE")"
      fi
      if [[ -z "$pcommit" ]] || ! git -C "$repo" update-ref "$pin" "$pcommit" >>"$LOG_FILE" 2>&1 \
         || [[ "$(git -C "$repo" rev-parse -q --verify "${pin}^{commit}" 2>/dev/null)" != "$pcommit" ]]; then
        log "  [FAILED]  $(printf '%10s' "$(human "$kb")")  $wt"
        log "              ↳ couldn't park its uncommitted changes — nothing was changed, left as it was"
        return 0
      fi
      # The live-use list was built once at the start of the run. A session or process may have started in this
      # checkout since: look again, right before anything is cleared, and leave it alone if so (the pin is a
      # harmless extra copy of what is still in the folder).
      if is_runtime_root "$wt" fresh; then
        log "  [SKIP]    $(printf '%10s' "$(human "$kb")")  $wt"
        log "              ↳ something started running in it just now — left as it was (its changes are also pinned as ${pin})"
        return 0
      fi
      # the changes are pinned; now clear the checkout so git will remove it without --force
      if ! git -C "$wt" reset -q --hard HEAD >>"$LOG_FILE" 2>&1; then
        log "  [FAILED]  $(printf '%10s' "$(human "$kb")")  $wt"
        log "              ↳ git reset failed: its changes are still in the folder AND pinned as ${pin} — left as it was"
        return 0
      fi
      if ! git -C "$wt" clean -fdq >>"$LOG_FILE" 2>&1 || [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
        log "  [FAILED]  $(printf '%10s' "$(human "$kb")")  $wt"
        log "              ↳ the folder was reset to its branch tip, so its tracked edits now live ONLY in ${pin}; some untracked files could not be removed and stay in the folder — checkout kept. Put them back (edits, deletions and untracked files, all unstaged) with: git -C '${wt}' restore --source=${pin} --staged --worktree -- . && git -C '${wt}' reset -q"
        return 0
      fi
    fi
    # a clean checkout has nothing to clear, but the same late look applies before it is removed
    if [[ "$dirty" -eq 0 ]] && is_runtime_root "$wt" fresh; then
      log "  [SKIP]    $(printf '%10s' "$(human "$kb")")  $wt"
      log "              ↳ something started running in it just now — left as it was"
      return 0
    fi
    # 3. remove the checkout; the branch is never touched
    if git -C "$repo" worktree remove "$wt" >>"$LOG_FILE" 2>&1; then
      log "  [DELETED] $(printf '%10s' "$(human "$kb")")  $wt"
      log "              ↳ ${why}"
      [[ -n "$pcommit" ]] && log "              ↳ uncommitted and untracked changes parked as a commit, pinned as ${pin}"
      [[ -n "$park" ]] && log "              ↳ local-only files copied to ${park}"
      restore="\`git -C '${repo}' worktree add '${wt}' ${br:-$sha}\`"
      [[ -n "$pcommit" ]] && restore="${restore}, then \`git -C '${wt}' cherry-pick --no-commit ${pin} && git -C '${wt}' reset -q\`"
      [[ -n "$park" ]] && restore="${restore}, then \`ditto '${park}' '${wt}'\`"
      wt_manifest "| $(date '+%Y-%m-%d %H:%M') | \`${wt}\` | ${br:-detached ${sha:0:10}} | ${pcommit:+\`${pin}\`} | ${park:+\`${park}\`} | ${restore} |"
    else
      # put the work back exactly as it was (apply the pinned commit by SHA: no stash list involved)
      note=""
      if [[ -n "$pcommit" ]]; then
        if git -C "$wt" cherry-pick --no-commit "$pcommit" >>"$LOG_FILE" 2>&1 && git -C "$wt" reset -q >>"$LOG_FILE" 2>&1; then
          git -C "$repo" update-ref -d "$pin" >>"$LOG_FILE" 2>&1
        else
          note=" — its changes could not be put back automatically and stay pinned as ${pin} (git -C '${wt}' cherry-pick --no-commit ${pin})"
        fi
      fi
      log "  [FAILED]  $(printf '%10s' "$(human "$kb")")  $wt"
      log "              ↳ git refused to remove it — left as it was${note}"
    fi
  }
  for root in $ROOTS; do
    [[ -d "$root" ]] || continue
    while IFS= read -r gitdir; do
      repo="$(dirname "$gitdir")"
      first=1; wt=""; sha=""; br=""; locked=0; stale=0
      while IFS= read -r line; do
        case "$line" in
          "worktree "*) wt="${line#worktree }"; sha=""; br=""; locked=0; stale=0 ;;
          "HEAD "*)     sha="${line#HEAD }" ;;
          "branch "*)   br="${line#branch refs/heads/}" ;;
          locked*)      locked=1 ;;
          prunable*)    stale=1 ;;
          "")           if [[ $first -eq 0 && -n "$wt" ]]; then
                          if [[ $stale -eq 1 ]]; then
                            wt_stale=$((wt_stale+1))
                            log "  (stale record: ${wt} — its folder is gone; git worktree prune clears it)"
                          else
                            wt_consider "$repo" "$wt" "$sha" "$br" "$locked"
                          fi
                        fi
                        first=0; wt="" ;;
        esac
      done < <(git -C "$repo" worktree list --porcelain 2>/dev/null; echo "")
      [[ "$DRY_RUN" -eq 0 ]] && git -C "$repo" worktree prune 2>/dev/null
    done < <(find "$root" \( -name node_modules -o -name .composure -o -name .claude \) -prune \
               -o -type d -name .git -prune -print 2>/dev/null)
  done
  log "  (kept ${wt_kept} worktree(s) — recent, live, locked, submodules, or too much local-only data; ${wt_main} on main, never removed)"
fi

# ---------- 2. node_modules of stale repos (deep mode only) ----------
if [[ "$MODE" == "deep" ]]; then
  if [[ "$NM_REQUIRE_CLEAN" == "1" ]]; then
    group "2. node_modules of repos idle >${NM_AGE_DAYS}d with a clean git tree"
  else
    group "2. node_modules of repos idle >${NM_AGE_DAYS}d (uncommitted changes allowed)"
  fi
  STALE_LIST="$(mktemp -t autoclean-stale)"
  ACTIVE_LIST="$(mktemp -t autoclean-active)"

  for root in $ROOTS; do
    [[ -d "$root" ]] || continue
    while IFS= read -r nm; do
      # already counted with its whole worktree in 1.8
      if [[ -n "$WT_LIST" ]]; then
        in_wt=0
        while IFS= read -r w; do case "$nm" in "$w"/*) in_wt=1; break ;; esac; done < "$WT_LIST"
        [[ $in_wt -eq 1 ]] && continue
      fi
      rr="$(repo_root "$nm" || true)"
      [[ -n "$rr" ]] || rr="$(dirname "$nm")"   # no git? use parent dir
      # already classified?
      grep -qxF "$rr" "$STALE_LIST" 2>/dev/null && { reclaim "$nm"; continue; }
      grep -qxF "$rr" "$ACTIVE_LIST" 2>/dev/null && continue
      # classify this repo root once
      verdict="active"
      if is_runtime_root "$rr"; then
        :   # something live runs from this repo — never idle, whatever mtime says
      elif is_idle "$rr" "$NM_AGE_DAYS"; then
        # idle by mtime — confirm clean git tree before trusting it (unless
        # the user opted out: node_modules never holds their work)
        if [[ "$NM_REQUIRE_CLEAN" == "1" && -d "$rr/.git" ]]; then
          if [[ -z "$(git -C "$rr" status --porcelain 2>/dev/null)" ]]; then
            verdict="stale"
          fi
        else
          verdict="stale"
        fi
      fi
      if [[ "$verdict" == "stale" ]]; then
        echo "$rr" >> "$STALE_LIST"; reclaim "$nm"
      else
        echo "$rr" >> "$ACTIVE_LIST"
      fi
    done < <(find "$root" -type d -name node_modules -prune 2>/dev/null)
  done
  log "  (kept node_modules for $(grep -c . "$ACTIVE_LIST" 2>/dev/null || echo 0) active repos)"
fi

# ---------- 3. Package-manager caches (deep mode only; uses tool prune) ----------
if [[ "$MODE" == "deep" ]]; then
  group "3. Package-manager caches (prune unreferenced only)"
  if command -v pnpm >/dev/null 2>&1; then
    # launchd starts us with cwd=/ (read-only system volume); pnpm writes a temp
    # file into the cwd and dies with EROFS, so prune from $HOME.
    if [[ "$DRY_RUN" -eq 1 ]]; then log "  [DRY]     prune:pnpm  Unused packages in the pnpm store (size not known until it runs)"
    elif ! command_approved prune:pnpm; then log "  [SKIP]    prune:pnpm  not in the reviewed list"
    else log "  running: pnpm store prune"; (cd "$HOME" && pnpm store prune) >>"$LOG_FILE" 2>&1 || true; fi
  fi
  if command -v npm >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then log "  [DRY]     prune:npm  The whole npm cache, which downloads again when needed (size not known until it runs)"
    elif ! command_approved prune:npm; then log "  [SKIP]    prune:npm  not in the reviewed list"
    else log "  running: npm cache clean --force"; npm cache clean --force >>"$LOG_FILE" 2>&1 || true; fi
  fi
fi

# ---------- 3b. Tool caches — expansion pack (opt-in via config, either mode) ----------
# ANALYZERS_TOOL_CACHES: comma list of enabled ids —
#   either mode: brew,pip,uv,cargo,gradle,deriveddata,bun,cipd
#   deep only:   appcaches,gomod,simulators,avd,aerials
# Everything here is REDOWNLOADABLE/REBUILDABLE cache — never sources, never state.
TOOL_CACHES="${ANALYZERS_TOOL_CACHES:-}"
if [[ -n "$TOOL_CACHES" ]]; then
  group "3b. Tool caches (opt-in expansion pack)"
  enabled() { [[ ",${TOOL_CACHES}," == *",$1,"* ]]; }
  tc_human() { awk -v k="$1" 'BEGIN{ if(k>=1048576) printf "%.1f GB",k/1048576; else if(k>=1024) printf "%.1f MB",k/1024; else printf "%d KB",k }'; }
  tool_cache() { # id  path  human-cmd-description  (apply command via eval of $4)
    local id="$1" path="$2" desc="$3" cmd="$4"
    enabled "$id" || return 0
    [[ -e "$path" ]] || { log "  (${id}: no cache at ${path})"; return 0; }
    approved "$path" || { log "  [SKIP]    not in approved set  $path"; return 0; }
    local kb; kb="$(du -sk "$path" 2>/dev/null | cut -f1)"; [[ -z "$kb" ]] && kb=0
    local size; size="$(tc_human "$kb")"
    TOTAL_KB=$((TOTAL_KB + kb))
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [DRY] ${size}  ${path}"
    else
      log "  running: ${desc}"
      eval "$cmd" >>"$LOG_FILE" 2>&1 || true
      log "  [DELETED] ${size}  ${path}"
    fi
  }
  tool_cache pip         "${HOME}/Library/Caches/pip"                         "pip3 cache purge"         "pip3 cache purge"
  tool_cache uv          "${HOME}/.cache/uv"                                  "uv cache prune"           "uv cache prune"
  tool_cache cargo       "${HOME}/.cargo/registry/cache"                      "remove cargo registry cache" "rm -rf '${HOME}/.cargo/registry/cache'"
  tool_cache gradle      "${HOME}/.gradle/caches"                             "remove gradle caches"     "rm -rf '${HOME}/.gradle/caches'"
  tool_cache deriveddata "${HOME}/Library/Developer/Xcode/DerivedData"        "empty Xcode DerivedData"  "rm -rf '${HOME}/Library/Developer/Xcode/DerivedData'"
  enabled cargo && reclaim "${HOME}/.cargo/registry/src"
  enabled bun   && reclaim "${HOME}/.bun/install/cache"
  enabled cipd  && reclaim "${HOME}/.cipd-cache-dir"

  # Homebrew keeps old versions in the Cellar long after an upgrade, and
  # HOMEBREW_CACHE may not exist at all — so cleanup runs either way.
  if enabled brew && command -v brew >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      est="$(HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup -n --prune=all -s 2>/dev/null | grep -i 'would free' | tail -1)"
      log "  [DRY]     prune:brew  Old Homebrew versions and downloads — ${est:-nothing to remove}"
    elif ! command_approved prune:brew; then
      log "  [SKIP]    prune:brew  not in the reviewed list"
    else
      log "  running: brew cleanup --prune=all -s"
      HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup --prune=all -s >>"$LOG_FILE" 2>&1 || true
    fi
  fi

  if [[ "$MODE" == "deep" ]]; then
    # Every app's cache folder. Skipped: macOS's own (com.apple.*, privacy-
    # protected), the Claude app hosting live sessions, Playwright's browsers
    # (tests break until reinstalled), the ids above, the protect list, extra
    # names in ANALYZERS_APPCACHE_KEEP (regex alternatives), and anything
    # written in the last hour — that app is using it right now.
    if enabled appcaches; then
      # dotslash: its downloaded executables carry macOS provenance
      # protection — another process can't delete them, so don't try nightly
      keep='com\.apple\..*|Claude.*|com\.anthropic\..*|claude-cli-nodejs|ms-playwright|CloudKit|FamilyCircle|familycircled|GeoServices|Homebrew|pip|dotslash'
      [[ -n "${ANALYZERS_APPCACHE_KEEP:-}" ]] && keep="${keep}|${ANALYZERS_APPCACHE_KEEP}"
      keep_re="^(${keep})\$"
      for p in "$HOME"/Library/Caches/*; do
        name="$(basename "$p")"
        [[ "$name" =~ $keep_re ]] && continue
        protected "$name" && continue
        ls "$p" >/dev/null 2>&1 || continue                      # privacy-protected
        [[ -n "$(find "$p" -mmin -60 -print -quit 2>/dev/null)" ]] && continue
        reclaim "$p"
      done
    fi

    if enabled gomod && command -v go >/dev/null 2>&1; then
      gm="$(go env GOMODCACHE 2>/dev/null)"
      if [[ -n "$gm" && -d "$gm" ]]; then
        kb=$(du -sk "$gm" 2>/dev/null | cut -f1)
        cmd_reclaim "$gm" "${kb:-0}" go clean -modcache   # module files are read-only
      fi
    fi

    # Simulator runtimes never booted (no lastUsedAt) and installed 7+ days
    # ago, removed through simctl — they live in system asset storage.
    if enabled simulators && command -v xcrun >/dev/null 2>&1; then
      rt_json="$(xcrun simctl runtime list -j 2>/dev/null)"
      if [[ -n "$rt_json" ]]; then
        while IFS='|' read -r uuid bytes path; do
          [[ -n "$uuid" && -e "$path" ]] || continue
          [[ -n "$(find "$path" -prune -mtime -7 -print 2>/dev/null)" ]] && continue
          cmd_reclaim "$path" "$(( ${bytes:-0} / 1024 ))" xcrun simctl runtime delete "$uuid"
        done < <(osascript -l JavaScript -e '
          function run(argv) {
            var o = JSON.parse(argv[0]), out = [];
            for (var k in o) { var r = o[k];
              if (r.lastUsedAt || r.deletable === false) continue;
              out.push([r.identifier, r.sizeBytes || 0, r.path || ""].join("|")); }
            return out.join("\n"); }' "$rt_json" 2>/dev/null)
      fi
      # simulators whose runtime is gone; listed in the preview, and — being one
      # command, not paths — never run as part of a narrowed (reviewed) apply
      n_unavail="$(xcrun simctl list devices unavailable 2>/dev/null | grep -c '(unavailable' || true)"
      if [[ "${n_unavail:-0}" -gt 0 ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log "  [DRY]     prune:simulators  ${n_unavail} simulator(s) whose runtime is gone (size not known until it runs)"
        elif ! command_approved prune:simulators; then
          log "  [SKIP]    prune:simulators  not in the reviewed list"
        else
          log "  running: xcrun simctl delete unavailable"
          xcrun simctl delete unavailable >>"$LOG_FILE" 2>&1 || true
        fi
      fi
    fi

    # Android emulator quick-boot snapshots — only while no emulator runs;
    # the next boot is a cold boot. The AVD itself (apps, data) stays.
    if enabled avd; then
      if pgrep -f "qemu-system|emulator64-|/emulator/emulator" >/dev/null 2>&1; then
        log "  (avd: an emulator is running — snapshots kept)"
      else
        # default_boot only: snapshots the user saved by name are state, not cache
        for s in "$HOME"/.android/avd/*.avd/snapshots/default_boot; do reclaim "$s"; done
      fi
    fi

    # Aerial wallpaper videos not shown in 14 days; macOS re-downloads the
    # one in use, so only rotation leftovers go.
    if enabled aerials; then
      av="$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos"
      while IFS= read -r f; do reclaim "$f"; done \
        < <(find "$av" -type f -name '*.mov' -atime +14 2>/dev/null)
    fi
  fi
fi

# ---------- 3.5 Docker maintenance (when --docker; either mode) ----------
if [[ "$DOCKER" -eq 1 ]]; then
  group "3.5 Docker prune"
  docker_maint
fi

# ---------- 4. Time Machine local snapshots ----------
# Fresh hourly snapshots PIN the blocks we just freed, so deleting files doesn't
# move df until a snapshot is thinned. With --prune-snapshots we run the one
# whitelisted command (sudoers.d/tmutil-thin) to realize the space immediately.
SNAP_NOTE=""
if [[ "$MODE" == "deep" ]]; then
  group "4. Time Machine local snapshots"
  if command -v tmutil >/dev/null 2>&1; then
    snaps="$(tmutil listlocalsnapshots / 2>/dev/null | grep 'com.apple.TimeMachine' || true)"
    snap_count="$(printf '%s\n' "$snaps" | grep -c . )"
    if [[ "$snap_count" -eq 0 ]]; then
      log "  No local snapshots present. Nothing to do."
    elif [[ "$PRUNE_SNAPSHOTS" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
      # ONLY the exact whitelisted command runs here — cannot delete real backups.
      # shellcheck disable=SC2024  # the log is the user's own file; only tmutil needs root
      if sudo -n /usr/bin/tmutil thinlocalsnapshots / 999999999999 4 >>"$LOG_FILE" 2>&1; then
        log "  thinned ${snap_count} local snapshot(s) — freed space now realized in df."
      else
        SNAP_NOTE="snapshot thin needs the tmutil-thin sudoers rule (see README) — space stays purgeable until macOS auto-frees it."
        log "  ⚠ ${SNAP_NOTE}"
      fi
    else
      SNAP_NOTE="${snap_count} TM snapshot(s) pin freed space. Reclaim now: sudo tmutil thinlocalsnapshots / 999999999999 4"
      log "  ${snap_count} local snapshot(s) present (pinning freed space)."
      log "  ALERT: ${SNAP_NOTE}"
    fi
  else
    log "  tmutil not available."
  fi
fi

# ---------- summary ----------
RUN_FREED_KB="$TOTAL_KB"

log ""
log "=================================================================="
if [[ "$DRY_RUN" -eq 1 ]]; then
  log " DRY RUN — identified ~$(human "$RUN_FREED_KB") reclaimable. Re-run with --apply."
  notify "Storage auto-clean (dry run)" "Would free ~$(human "$RUN_FREED_KB") [${MODE}]. ${SNAP_NOTE}"
else
  log " DONE — freed ~$(human "$RUN_FREED_KB") [mode=${MODE}]."
  notify "Storage auto-clean" "Freed ~$(human "$RUN_FREED_KB") [${MODE}]. ${SNAP_NOTE}"
fi
log " Free space now: $(df -h /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4" avail ("$5" used)"}')"
log "=================================================================="

# ---------- interactive follow-through ----------
if [[ "$INTERACTIVE" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 && "$RUN_FREED_KB" -gt 0 ]]; then
    echo ""
    read -rp "  Apply this now? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
      if [[ "$MODE" == "deep" ]]; then
        "$0" --mode deep --apply --prune-snapshots --docker-images
      else
        "$0" --apply
      fi
    fi
  fi
  echo ""
  read -rp "  Done — press Enter to close this window… " _
fi
