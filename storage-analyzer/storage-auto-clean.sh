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
#   * node_modules is removed ONLY for STALE repos — no source file modified in
#     M days (--nm-age-days, default 14) AND a clean git working tree. A repo
#     with uncommitted changes or recent edits is left fully intact.
#
#   * Package-manager caches are pruned with the tools' own prune commands
#     (pnpm store prune / npm cache clean), which only drop UNREFERENCED data.
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
# Tunables: --cache-age-days N  --nm-age-days N  --snapshot-keep-days N
#           --roots "dir1 dir2"  (default: ~/Projects)
# Docker:   starts Docker Desktop only if it's not already running, prunes, then
#           quits it again ONLY if this script started it. Volumes never pruned
#           unless --docker-volumes. Needs the daemon reachable (Docker Desktop).
# ---------------------------------------------------------------------------

set -u
shopt -s nullglob

# ---------- defaults ----------
HOME_DIR="${HOME}"
MODE="daily"                 # daily | deep
DRY_RUN=1
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
[[ -f "${ANALYZERS_ROOT}/config.local.sh" ]] && source "${ANALYZERS_ROOT}/config.local.sh"
LOG_FILE="${LOG_DIR}/auto-clean.log"
LOCK_FILE="${LOG_DIR}/.auto-clean.lock"

BUILD_CACHE_NAMES=( .next .turbo dist build .vite .svelte-kit .nuxt .parcel-cache )

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
    --snapshot-keep-days) SNAPSHOT_KEEP_DAYS="${2:-5}"; shift ;;
    --roots)              ROOTS="${2:-}"; shift ;;
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
  echo "  3) Preview deep clean (+ node_modules of idle repos, package caches, TM)"
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
trap 'rm -f "$LOCK_FILE"' EXIT

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

# reclaim <path>  — size-aware, dry-run-aware, accumulates TOTAL_KB
reclaim() {
  local p="$1"
  [[ -e "$p" ]] || return 0
  local kb; kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
  TOTAL_KB=$((TOTAL_KB + kb))
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "  [DRY]     $(printf '%10s' "$(human "$kb")")  $p"
  else
    if rm -rf "$p" 2>/dev/null; then
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
        \( -name node_modules -o -name .git -o -name .next -o -name .turbo \
           -o -name dist -o -name build -o -name .vite -o -name .cache \
           -o -name .svelte-kit -o -name .nuxt -o -name .parcel-cache \) -prune \
        -o -type f -mtime "-${days}" -print -quit 2>/dev/null)
  [[ -z "$hit" ]]
}

# Docker prune. If the daemon isn't running, start Docker Desktop, prune, then
# quit it — but ONLY quit if WE started it (a Docker you left running stays up).
# Never touches volumes unless --docker-volumes (data-loss risk).
docker_maint() {
  command -v docker >/dev/null 2>&1 || { log "  docker CLI not found; skipping."; return 0; }
  if [[ "$DRY_RUN" -eq 1 ]]; then
    local extra=""
    [[ "$DOCKER_IMAGES" -eq 1 ]]  && extra="${extra} ; image prune -a -f"
    [[ "$DOCKER_VOLUMES" -eq 1 ]] && extra="${extra} ; volume prune -f (⚠ DATA)"
    if docker info >/dev/null 2>&1; then
      log "  [DRY] Docker running → would: docker system prune -f${extra}"
    elif [[ "$DOCKER_NO_START" -eq 1 ]]; then
      log "  [DRY] Docker stopped → would SKIP (running-only mode)"
    else
      log "  [DRY] Docker stopped → would: start it → docker system prune -f${extra} → shut it back down"
    fi
    return 0
  fi
  local started=0 i=0
  if ! docker info >/dev/null 2>&1; then
    if [[ "$DOCKER_NO_START" -eq 1 ]]; then
      log "  Docker not running — skipping (running-only mode; won't boot it)."; return 0
    fi
    log "  Docker not running — starting Docker Desktop…"
    open -a Docker 2>/dev/null || open -a "Docker Desktop" 2>/dev/null || { log "  couldn't launch Docker; skipping."; return 0; }
    started=1
    until docker info >/dev/null 2>&1; do
      sleep 3; i=$((i+1))
      if [[ $i -ge 40 ]]; then
        log "  Docker didn't become ready (~120s) — shutting it back down, skipping."
        osascript -e 'quit app "Docker"' 2>/dev/null || true
        return 0
      fi
    done
    log "  Docker ready (started by auto-clean)."
  else
    log "  Docker already running — pruning, will leave it running."
  fi
  log "  running: docker system prune -f"; docker system prune -f >>"$LOG_FILE" 2>&1 || true
  if [[ "$DOCKER_IMAGES" -eq 1 ]]; then
    log "  running: docker image prune -a -f (all unused images)"; docker image prune -a -f >>"$LOG_FILE" 2>&1 || true
  fi
  if [[ "$DOCKER_VOLUMES" -eq 1 ]]; then
    log "  running: docker volume prune -f  (⚠ removes unused volumes — DATA)"; docker volume prune -f >>"$LOG_FILE" 2>&1 || true
  fi
  if [[ "$started" -eq 1 ]]; then
    log "  shutting Docker back down (auto-clean started it)…"
    osascript -e 'quit app "Docker"' 2>/dev/null || pkill -f 'Docker Desktop' 2>/dev/null || true
  fi
}

# ---------- header ----------
log "=================================================================="
log " storage-auto-clean.sh  |  mode=${MODE}  |  $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY')  |  ${TS_NOW}"
log " roots=${ROOTS}  cache>${CACHE_AGE_DAYS}d  nm>${NM_AGE_DAYS}d  snap-keep=${SNAPSHOT_KEEP_DAYS}d"
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
  done < <(find "$root" -type d \( \
      -name .next -o -name .turbo -o -name dist -o -name build -o -name .vite \
      -o -name .svelte-kit -o -name .nuxt -o -name .parcel-cache \
    \) -prune 2>/dev/null)
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

# ---------- 2. node_modules of stale repos (deep mode only) ----------
if [[ "$MODE" == "deep" ]]; then
  group "2. node_modules of repos idle >${NM_AGE_DAYS}d with a clean git tree"
  STALE_LIST="$(mktemp -t autoclean-stale)"
  ACTIVE_LIST="$(mktemp -t autoclean-active)"
  trap 'rm -f "$LOCK_FILE" "$STALE_LIST" "$ACTIVE_LIST"' EXIT

  for root in $ROOTS; do
    [[ -d "$root" ]] || continue
    while IFS= read -r nm; do
      rr="$(repo_root "$nm" || true)"
      [[ -n "$rr" ]] || rr="$(dirname "$nm")"   # no git? use parent dir
      # already classified?
      grep -qxF "$rr" "$STALE_LIST" 2>/dev/null && { reclaim "$nm"; continue; }
      grep -qxF "$rr" "$ACTIVE_LIST" 2>/dev/null && continue
      # classify this repo root once
      verdict="active"
      if is_idle "$rr" "$NM_AGE_DAYS"; then
        # idle by mtime — confirm clean git tree before trusting it
        if [[ -d "$rr/.git" ]]; then
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
    if [[ "$DRY_RUN" -eq 1 ]]; then log "  [DRY]     pnpm store prune"
    else log "  running: pnpm store prune"; pnpm store prune >>"$LOG_FILE" 2>&1 || true; fi
  fi
  if command -v npm >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then log "  [DRY]     npm cache clean --force"
    else log "  running: npm cache clean --force"; npm cache clean --force >>"$LOG_FILE" 2>&1 || true; fi
  fi
fi

# ---------- 3b. Tool caches — expansion pack (opt-in via config, either mode) ----------
# ANALYZERS_TOOL_CACHES: comma list of enabled ids (brew,pip,uv,cargo,gradle,deriveddata).
# Everything here is REDOWNLOADABLE/REBUILDABLE cache — never sources, never state.
TOOL_CACHES="${ANALYZERS_TOOL_CACHES:-}"
if [[ -n "$TOOL_CACHES" ]]; then
  group "3b. Tool caches (opt-in expansion pack)"
  tc_human() { awk -v k="$1" 'BEGIN{ if(k>=1048576) printf "%.1f GB",k/1048576; else if(k>=1024) printf "%.1f MB",k/1024; else printf "%d KB",k }'; }
  tool_cache() { # id  path  human-cmd-description  (apply command via eval of $4)
    local id="$1" path="$2" desc="$3" cmd="$4"
    [[ ",${TOOL_CACHES}," == *",${id},"* ]] || return 0
    [[ -e "$path" ]] || { log "  (${id}: no cache at ${path})"; return 0; }
    local kb; kb="$(du -sk "$path" 2>/dev/null | cut -f1)"; [[ -z "$kb" ]] && kb=0
    local size; size="$(tc_human "$kb")"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [DRY] ${size}  ${path}"
    else
      log "  running: ${desc}"
      eval "$cmd" >>"$LOG_FILE" 2>&1 || true
      log "  [DELETED] ${size}  ${path}"
    fi
  }
  BREW_CACHE="$(command -v brew >/dev/null 2>&1 && brew --cache 2>/dev/null || echo "${HOME}/Library/Caches/Homebrew")"
  tool_cache brew        "$BREW_CACHE"                                        "brew cleanup --prune=all" "brew cleanup --prune=all"
  tool_cache pip         "${HOME}/Library/Caches/pip"                         "pip3 cache purge"         "pip3 cache purge"
  tool_cache uv          "${HOME}/.cache/uv"                                  "uv cache prune"           "uv cache prune"
  tool_cache cargo       "${HOME}/.cargo/registry/cache"                      "remove cargo registry cache" "rm -rf '${HOME}/.cargo/registry/cache'"
  tool_cache gradle      "${HOME}/.gradle/caches"                             "remove gradle caches"     "rm -rf '${HOME}/.gradle/caches'"
  tool_cache deriveddata "${HOME}/Library/Developer/Xcode/DerivedData"        "empty Xcode DerivedData"  "rm -rf '${HOME}/Library/Developer/Xcode/DerivedData'"
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
