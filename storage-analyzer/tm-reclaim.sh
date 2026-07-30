#!/usr/bin/env bash
# Time Machine local-snapshot reclaim — companion to cleanup.sh / auto-clean.sh
# ---------------------------------------------------------------------------
# Releases the APFS LOCAL snapshots that pin just-deleted blocks (the "I freed
# 40GB but df didn't move" problem), then starts a FRESH Time Machine backup so
# the post-cleanup state is what gets protected.
#
# This script deletes NO files. Local snapshots are ephemeral (regenerate
# hourly, auto-purged under pressure) and the real backup on your TM disk is
# never touched — which is why, unlike cleanup.sh, it ACTS immediately.
#
#   ./tm-reclaim.sh              # thin+delete local snapshots, start backup
#   ./tm-reclaim.sh --wait       # same, but block until the backup finishes
#   ./tm-reclaim.sh --no-backup  # reclaim space only, skip the backup
#   ./tm-reclaim.sh --dry-run    # just list snapshots + show df, change nothing
#
# Passwordless operation: install the scoped sudoers rule once —
#   ./storage-manage-agents.sh sudoers-install
# Without it, this script asks for your password (fine interactively; the
# scheduled agents use auto-clean.sh --prune-snapshots instead).
# ---------------------------------------------------------------------------

set -u

DRY_RUN=0
DO_BACKUP=1
WAIT_BACKUP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --no-backup) DO_BACKUP=0 ;;
    --wait)      WAIT_BACKUP=1 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
  shift
done

df_avail() { df -h /System/Volumes/Data | awk 'NR==2{print $4}'; }

echo "=================================================================="
echo " Time Machine local-snapshot reclaim"
echo "=================================================================="
echo ""
echo "Free space before: $(df_avail)"
echo ""

# ---------- 1. inventory ----------
TM_SNAPS=$(tmutil listlocalsnapshots / 2>/dev/null | grep 'com.apple.TimeMachine' || true)
OS_SNAPS=$(tmutil listlocalsnapshots / 2>/dev/null | grep 'com.apple.os.update' || true)

if [[ -n "$TM_SNAPS" ]]; then
  echo "Local TM snapshots (these pin deleted blocks):"
  echo "$TM_SNAPS" | sed 's/^/  /'
else
  echo "No local TM snapshots present."
fi
[[ -n "$OS_SNAPS" ]] && echo "(OS-update snapshots exist too — system-managed, left alone.)"
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN — nothing changed. Re-run without --dry-run to reclaim."
  exit 0
fi

# ---------- 2. thin (the whitelisted command — releases purgeable space) ----------
echo "Thinning local snapshots…"
if sudo -n /usr/bin/tmutil thinlocalsnapshots / 999999999999 4 2>/dev/null; then
  echo "  done (passwordless via sudoers rule)."
elif [[ -t 0 ]]; then
  echo "  sudoers rule not installed — asking for your password."
  echo "  (install once with: ./storage-manage-agents.sh sudoers-install)"
  sudo /usr/bin/tmutil thinlocalsnapshots / 999999999999 4 && echo "  done."
else
  echo "  ✗ no TTY and no sudoers rule — cannot thin. Run: ./storage-manage-agents.sh sudoers-install"
fi

# ---------- 3. delete any TM snapshots that survived thinning ----------
REMAINING=$(tmutil listlocalsnapshots / 2>/dev/null | grep 'com.apple.TimeMachine' || true)
if [[ -n "$REMAINING" && -t 0 ]]; then
  echo ""
  echo "Deleting remaining TM local snapshots…"
  echo "$REMAINING" | sed 's/com\.apple\.TimeMachine\.//; s/\.local$//' | while read -r d; do
    [[ -n "$d" ]] || continue
    sudo tmutil deletelocalsnapshots "$d" >/dev/null 2>&1 \
      && echo "  deleted ${d}" \
      || echo "  could not delete ${d} (will roll off on its own)"
  done
fi

echo ""
echo "Free space after reclaim: $(df_avail)"

# ---------- 4. fresh backup ----------
if [[ "$DO_BACKUP" -eq 1 ]]; then
  echo ""
  if [[ "$WAIT_BACKUP" -eq 1 ]]; then
    echo "Starting Time Machine backup (blocking until done)…"
    tmutil startbackup --block && echo "Backup finished."
  else
    echo "Starting Time Machine backup (runs in background — check the TM menu)…"
    tmutil startbackup
  fi
  echo ""
  echo "Note: the backup creates ONE new local snapshot of the post-cleanup"
  echo "state — that's normal and it no longer references the deleted files."
fi

echo ""
echo "=================================================================="
echo " Done. Free space now: $(df_avail)"
echo "=================================================================="
