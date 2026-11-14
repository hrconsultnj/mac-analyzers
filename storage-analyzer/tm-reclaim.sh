#!/usr/bin/env bash
# Time Machine local-snapshot reclaim — companion to cleanup.sh / auto-clean.sh
# ---------------------------------------------------------------------------
# Releases the APFS LOCAL snapshots that pin just-deleted blocks (the "I freed
# 40GB but df didn't move" problem), then starts a FRESH Time Machine backup so
# the post-cleanup state is what gets protected.
#
# This script deletes NO files. Local snapshots are ephemeral (regenerate
# hourly, auto-purged under pressure) and the real backup on your TM disk is
# never touched. Like every cleaner it LOOKS first: with no flag it lists the
# snapshots and the free space and changes nothing; --apply acts.
#
#   ./tm-reclaim.sh --dry-run    # (the default) list snapshots + show df, change nothing
#   ./tm-reclaim.sh --apply      # thin local snapshots, start a backup
#   ./tm-reclaim.sh --apply --wait       # same, but block until the backup finishes
#   ./tm-reclaim.sh --apply --no-backup  # reclaim space only, skip the backup
#
# Every run writes a block to reports/storage/tm-reclaim.log: a standard banner
# (tm-reclaim | DRY RUN or APPLY | backup=on or off | date) between rules, one
# SNAPSHOT line per local snapshot, FREE_BEFORE and FREE_AFTER, and a DONE trailer.
#
# Passwordless operation: install the scoped sudoers rule once —
#   ./storage-manage-agents.sh sudoers-install      (the app's "Allow…" button does this)
# Without it, an --apply from a terminal asks for your password; an --apply
# with no terminal (the app) says what is missing and exits 3.
# ---------------------------------------------------------------------------

set -u

DRY_RUN=1
DO_BACKUP=1
WAIT_BACKUP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --apply)     DRY_RUN=0 ;;
    --no-backup) DO_BACKUP=0 ;;
    --wait)      WAIT_BACKUP=1 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
  shift
done

OUT_DIR="${HOME}/mac-analyzers/reports/storage"
mkdir -p "${OUT_DIR}"
LOG_FILE="${OUT_DIR}/tm-reclaim.log"
log() { echo "$*" | tee -a "${LOG_FILE}"; }

df_avail() { df -h /System/Volumes/Data | awk 'NR==2{print $4}'; }

log "=================================================================="
log "tm-reclaim | $([[ "$DRY_RUN" -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY') | backup=$([[ "$DO_BACKUP" -eq 1 ]] && echo on || echo off) | $(date '+%Y-%m-%d %H:%M:%S')"
log "=================================================================="
FREE_BEFORE="$(df_avail)"
log "FREE_BEFORE ${FREE_BEFORE}"
log ""

# ---------- 1. inventory ----------
ALL_SNAPS=$(tmutil listlocalsnapshots / 2>/dev/null || true)
TM_SNAPS=$(printf '%s\n' "$ALL_SNAPS" | grep 'com.apple.TimeMachine' || true)
OS_SNAPS=$(printf '%s\n' "$ALL_SNAPS" | grep 'com.apple.os.update' || true)

if [[ -n "$TM_SNAPS" ]]; then
  log "Local TM snapshots (these pin deleted blocks):"
  printf '%s\n' "$TM_SNAPS" | sed 's/com\.apple\.TimeMachine\.//; s/\.local$//' | while read -r d; do
    [[ -n "$d" ]] && log "SNAPSHOT ${d}"
  done
else
  log "No local TM snapshots present."
fi
if [[ -n "$OS_SNAPS" ]]; then
  printf '%s\n' "$OS_SNAPS" | while read -r d; do [[ -n "$d" ]] && log "OSSNAPSHOT ${d}"; done
  log "(OS-update snapshots exist too — system-managed, left alone.)"
fi
log ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN — nothing changed. Re-run with --apply to reclaim."
  exit 0
fi

# ---------- 2. thin (the whitelisted command — releases purgeable space) ----------
STATUS=0
log "Thinning local snapshots…"
if sudo -n /usr/bin/tmutil thinlocalsnapshots / 999999999999 4 >/dev/null 2>&1; then
  log "  done (passwordless via sudoers rule)."
elif [[ -t 0 ]]; then
  log "  sudoers rule not installed — asking for your password."
  log "  (install once with: ./storage-manage-agents.sh sudoers-install)"
  sudo /usr/bin/tmutil thinlocalsnapshots / 999999999999 4 && log "  done." || STATUS=3
else
  log "  ✗ needs permission: no sudoers rule and no terminal, so nothing could be thinned. Allow thinning once (the app's Allow… button, or ./storage-manage-agents.sh sudoers-install)."
  STATUS=3
fi

# ---------- 3. delete any TM snapshots that survived thinning (terminal only) ----------
REMAINING=$(tmutil listlocalsnapshots / 2>/dev/null | grep 'com.apple.TimeMachine' || true)
if [[ -n "$REMAINING" && -t 0 && "$STATUS" -eq 0 ]]; then
  log ""
  log "Deleting remaining TM local snapshots…"
  printf '%s\n' "$REMAINING" | sed 's/com\.apple\.TimeMachine\.//; s/\.local$//' | while read -r d; do
    [[ -n "$d" ]] || continue
    sudo tmutil deletelocalsnapshots "$d" >/dev/null 2>&1 \
      && log "  deleted ${d}" \
      || log "  could not delete ${d} (will roll off on its own)"
  done
fi

log ""
FREE_AFTER="$(df_avail)"
log "FREE_AFTER ${FREE_AFTER}"

# ---------- 4. fresh backup ----------
if [[ "$DO_BACKUP" -eq 1 && "$STATUS" -eq 0 ]]; then
  log ""
  if [[ "$WAIT_BACKUP" -eq 1 ]]; then
    log "Starting Time Machine backup (blocking until done)…"
    tmutil startbackup --block && log "Backup finished."
  else
    log "Starting Time Machine backup (runs in background — check the TM menu)…"
    tmutil startbackup
  fi
  log ""
  log "Note: the backup creates ONE new local snapshot of the post-cleanup"
  log "state — that's normal and it no longer references the deleted files."
fi

log ""
log "=================================================================="
if [[ "$STATUS" -eq 0 ]]; then
  log "DONE — local snapshots thinned. Free space ${FREE_BEFORE} -> ${FREE_AFTER}."
else
  log "NOT DONE — thinning was not allowed (exit ${STATUS}). Free space still ${FREE_AFTER}."
fi
log "=================================================================="
exit "$STATUS"
