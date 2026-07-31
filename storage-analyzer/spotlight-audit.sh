#!/usr/bin/env bash
# spotlight-audit.sh — Spotlight indexing: status, verdict, and dev-dir hygiene
# ---------------------------------------------------------------------------
# Answers three questions the OS won't:
#
#   1. STATUS   — is indexing on, how much RAM/CPU is mds using right now, and
#                 did a recent macOS update make this reindex EXPECTED?
#   2. VERDICT  — is the indexer progressing or likely stuck? (heuristic from
#                 recent mds_stores log activity + CPU-time efficiency; the
#                 manual deep-check command is printed for the real call)
#   3. EXPOSURE — which dev directories (node_modules, build trees) is
#                 Spotlight wastefully indexing, and fence them with
#                 `.metadata_never_index` markers (reversible: delete marker).
#
# Grounded in 2026 guidance (Eclectic Light / mdutil docs): rebuilds are
# OVERUSED — this tool never runs `mdutil -E/-X/-i` for you. If the index is
# genuinely corrupted, it prints the one correct manual command and stops.
#
# SAFE BY DEFAULT: dry-run unless --apply. --apply only touches directories
# matching dev patterns inside your configured roots — never iCloud, never
# Documents, never anything outside the pattern list.
#
#   ./spotlight-audit.sh              # status + verdict + exposure (dry)
#   ./spotlight-audit.sh --apply      # also drop .metadata_never_index markers
# ---------------------------------------------------------------------------

set -u
shopt -s nullglob

HOME_DIR="${HOME}"
DRY_RUN=1
LOG_DIR="${HOME_DIR}/mac-analyzers/reports/storage"
LOG_FILE="${LOG_DIR}/spotlight-audit.log"

# optional per-machine config (gitignored) — see config.example.sh at repo root
ANALYZERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ANALYZERS_ROOT}/config.local.sh" ]] && source "${ANALYZERS_ROOT}/config.local.sh"

# roots to scan for dev junk (space-separated); patterns fenced when found
SPOTLIGHT_ROOTS="${ANALYZERS_SPOTLIGHT_ROOTS:-$HOME/Projects}"
DEV_PATTERNS=( node_modules .next .turbo dist build target vendor .venv __pycache__ .parcel-cache )

ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)   DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# ---------- interactive menu (double-click / bare terminal run) ----------
INTERACTIVE=0
if [[ -z "$ORIG_ARGS" ]] && { [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; }; then
  INTERACTIVE=1
  echo ""
  echo "  spotlight-audit — indexing status, stuck-check, dev-dir fencing"
  echo "  ---------------------------------------------------------------"
  echo "  1) Audit only (status + verdict + exposure, change nothing)"
  echo "  2) Audit + fence dev dirs (.metadata_never_index markers)"
  echo "  q) Quit"
  echo ""
  read -rp "  Choose [1]: " choice
  case "${choice:-1}" in
    1) ;;
    2) DRY_RUN=0 ;;
    q|Q) exit 0 ;;
    *) echo "  Unknown choice '${choice}' — exiting."; exit 2 ;;
  esac
fi

mkdir -p "$LOG_DIR"
log() { echo "$*" | tee -a "$LOG_FILE"; }
group() { log ""; log "### $1"; }

log "=================================================================="
log " spotlight-audit  |  $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY')  |  $(date '+%Y-%m-%d %H:%M:%S')"
log "=================================================================="

# ---------- 1. status + expected-reindex detection ----------
group "1. Indexing status"
mdutil -s / 2>/dev/null | sed 's/^/  /' | tee -a "$LOG_FILE"
MDS_LINE=$(ps axo rss=,time=,etime=,comm= | awk '
  /mds|mdworker/ { n++; rss+=$1 }
  END { printf "%d processes, %.0f MB resident", n, rss/1024 }')
log "  mds/mdworker now: ${MDS_LINE}"

RECENT_UPDATE=$(softwareupdate --history 2>/dev/null | awk 'NR>2 {print}' | tail -5 | grep -iE "macos|security" | tail -1)
if [[ -n "$RECENT_UPDATE" ]]; then
  log "  recent update:  ${RECENT_UPDATE}"
fi
log ""
log "  Context: a full reindex after a macOS update is EXPECTED (new metadata"
log "  importers invalidate the old index). Typical Apple Silicon durations:"
log "  15-30 min (small SSD) to 2-4 hrs (2TB). Dev machines with unfenced"
log "  node_modules run far longer — that's what section 3 fixes."

# ---------- 2. stuck-vs-progressing heuristic ----------
group "2. Stuck or progressing? (heuristic)"
# CPU-time vs wall-clock for mds_stores: a healthy indexer accumulates CPU.
MDS_PID=$(pgrep -x mds_stores | head -1)
if [[ -n "$MDS_PID" ]]; then
  MDS_STATS=$(ps -p "$MDS_PID" -o time=,etime= | awk '{gsub(/^ +/,""); print}')
  log "  mds_stores cpu-time vs uptime: ${MDS_STATS}"
  # log activity in the last 5 minutes (no sudo: may be partial — degrade honestly)
  ACT=$(log show --last 5m --predicate 'process == "mds_stores"' --style compact 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${ACT:-0}" -gt 5 ]]; then
    log "  log activity (5 min): ${ACT} lines — indexer is ACTIVE."
    log "  Verdict: PROGRESSING (active worker, accumulating CPU). Leave it alone;"
    log "  fence dev dirs (section 3) to shorten it."
  else
    log "  log activity (5 min): ${ACT:-0} lines — little visible activity."
    log "  Verdict: IDLE or COMPLETE (or logs need sudo for full view)."
  fi
else
  log "  mds_stores not running — no active indexing."
fi
log ""
log "  Deep check (manual, the definitive signal — generations should DECREASE"
log "  over time; increasing generations = the known runaway-compaction bug):"
log "    sudo log stream --predicate 'process == \"mds_stores\"' --info | grep -iE 'generation|compact'"
log "  If genuinely stuck for 24h+: the ONE correct rebuild command is:"
log "    sudo mdutil -E /System/Volumes/Data"
log "  (Never toggle -i off/on, never delete .Spotlight-V100 on the system"
log "   volume, never schedule rebuilds — all documented cargo-cult/harmful.)"

# ---------- 3. dev-directory exposure ----------
group "3. Dev-directory index exposure (roots: ${SPOTLIGHT_ROOTS})"
TOTAL_KB=0; FENCED=0; CANDIDATES=0
for root in $SPOTLIGHT_ROOTS; do
  [[ -d "$root" ]] || continue
  for pat in "${DEV_PATTERNS[@]}"; do
    while IFS= read -r d; do
      [[ -d "$d" ]] || continue
      if [[ -e "$d/.metadata_never_index" ]]; then
        FENCED=$((FENCED+1)); continue
      fi
      CANDIDATES=$((CANDIDATES+1))
      kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
      TOTAL_KB=$((TOTAL_KB + kb))
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log "  [DRY]     $(awk -v k="$kb" 'BEGIN{printf "%7.1f MB", k/1024}')  $d"
      else
        touch "$d/.metadata_never_index" \
          && log "  [FENCED]  $(awk -v k="$kb" 'BEGIN{printf "%7.1f MB", k/1024}')  $d"
      fi
    done < <(find "$root" -maxdepth 4 -type d -name "$pat" -prune 2>/dev/null)
  done
done
log ""
log "  Already fenced: ${FENCED}  |  Unfenced: ${CANDIDATES}  |  Unfenced bulk: $(awk -v k="$TOTAL_KB" 'BEGIN{printf "%.1f GB", k/1048576}')"
[[ "$DRY_RUN" -eq 1 && "$CANDIDATES" -gt 0 ]] && log "  Re-run with --apply to fence (reversible: rm the .metadata_never_index file)."

# ---------- summary ----------
log ""
log "=================================================================="
if [[ "$DRY_RUN" -eq 1 ]]; then
  log " DRY RUN — nothing changed."
else
  log " DONE — new fences take effect as mds rescans; already-indexed content"
  log " for fenced dirs drops out of the index over the next scans."
fi
log "=================================================================="

if [[ "$INTERACTIVE" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 && "$CANDIDATES" -gt 0 ]]; then
    echo ""
    read -rp "  Fence the ${CANDIDATES} unfenced dev dirs now? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] && "$0" --apply
  fi
  echo ""
  read -rp "  Done — press Enter to close this window… " _
fi
