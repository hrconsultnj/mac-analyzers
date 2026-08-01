#!/usr/bin/env bash
# downloads-janitor.sh — age-based tidy for ~/Downloads and ~/Desktop/Screenshots.
# CLEANER contract: dry-run by default, --apply acts. NEVER deletes — apply
# moves items to the user's Trash, fully recoverable.
#
#   * Downloads: top-level items untouched for N days (default 30). Folders
#     move as units — a folder's mtime only tracks its direct children, so
#     review the dry run before applying.
#   * Screenshots: FILES only, any depth (default 14 days) — year/month
#     folders are never moved wholesale, so a stale-looking parent can never
#     drag fresh screenshots to the Trash.
#
# Knobs (config.local.sh):
#   JANITOR_DOWNLOADS_AGE_DAYS=30
#   JANITOR_SCREENSHOTS_AGE_DAYS=14
#   JANITOR_KEEP_PATTERNS="*.dmg:Tax *"     # colon-separated globs, never touched
#
# Usage:
#   ./downloads-janitor.sh              # dry run
#   ./downloads-janitor.sh --apply      # move to Trash
set -euo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
# Settings live in the user folder. When the engine runs from inside the
# app bundle, that bundle is replaced wholesale on every update, so the
# user copy is the one that must win.
[[ -f "${SUITE_DIR}/config.local.sh" ]] && source "${SUITE_DIR}/config.local.sh"
[[ -f "$HOME/mac-analyzers/config.local.sh" && "${SUITE_DIR}" != "$HOME/mac-analyzers" ]] \
  && source "$HOME/mac-analyzers/config.local.sh"

DRY_RUN=1
ONLY_PATHS=""
prev=""
for arg in "$@"; do
  case "$prev" in
    --only-paths) ONLY_PATHS="$arg" ;;
  esac
  case "$arg" in
    --apply)   DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;
  esac
  prev="$arg"
done

# --only-paths <file>: act ONLY on items whose path appears in the file, one
# per line. The sweep still finds everything from scratch — the approved set
# can only ever SHRINK what gets touched, never add to it. That way the list
# going stale between preview and apply is safe by construction.
if [[ -n "${ONLY_PATHS}" && ! -f "${ONLY_PATHS}" ]]; then
  echo "--only-paths file not found: ${ONLY_PATHS}" >&2
  exit 2
fi

approved() {
  [[ -z "${ONLY_PATHS}" ]] && return 0
  grep -qxF -- "$1" "${ONLY_PATHS}"
}

DL_AGE="${JANITOR_DOWNLOADS_AGE_DAYS:-30}"
SS_AGE="${JANITOR_SCREENSHOTS_AGE_DAYS:-14}"
KEEP="${JANITOR_KEEP_PATTERNS:-}"
OUT_DIR="${HOME}/mac-analyzers/reports/storage"
mkdir -p "${OUT_DIR}"
LOG_FILE="${OUT_DIR}/janitor.log"
LOCK_FILE="${OUT_DIR}/.janitor.lock"

# Single instance, like every other cleaner: two sweeps racing over the same
# Trash destinations is how a receipt ends up pointing at the wrong file.
if [[ -e "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
  echo "downloads janitor already running (pid $(cat "$LOCK_FILE")); exiting." >&2
  exit 0
fi
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT
TRASH_DIR="${HOME}/.Trash"

log() { echo "$*" | tee -a "${LOG_FILE}"; }

human() {
  awk -v k="$1" 'BEGIN {
    if (k >= 1048576)    printf "%.1f GB", k / 1048576
    else if (k >= 1024)  printf "%.1f MB", k / 1024
    else                 printf "%d KB", k
  }'
}

keep_match() {
  local name="$1"
  [[ -z "${KEEP}" ]] && return 1
  local IFS=':'
  local pat
  for pat in ${KEEP}; do
    # shellcheck disable=SC2053
    [[ "${name}" == ${pat} ]] && return 0
  done
  return 1
}

TOTAL_KB=0
COUNT=0

sweep() {
  local dir="$1" age="$2" title="$3" files_only="$4"
  [[ -d "${dir}" ]] || return 0
  log "### ${title} (untouched ${age}+ days)"
  local find_args=(-mindepth 1 -not -name '.*' -mtime +"${age}")
  if [[ "${files_only}" -eq 1 ]]; then
    find_args+=(-type f)
  else
    find_args+=(-maxdepth 1)
  fi
  local item name kb size dest
  while IFS= read -r -d '' item; do
    name="$(basename "${item}")"
    if keep_match "${name}"; then
      log "[SKIP] kept by pattern  ${item}"
      continue
    fi
    if ! approved "${item}"; then
      log "[SKIP] not in approved set  ${item}"
      continue
    fi
    # `|| true`: without it, set -e aborts the sweep mid-run — AFTER files are
    # already in the Trash but BEFORE their receipts are written, which is the
    # one failure that loses the ability to undo.
    kb="$(du -sk "${item}" 2>/dev/null | cut -f1 || true)"
    [[ -z "${kb}" ]] && kb=0
    size="$(human "${kb}")"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log "[DRY] ${size}  ${item}"
    else
      dest="${TRASH_DIR}/${name}"
      [[ -e "${dest}" ]] && dest="${TRASH_DIR}/$(date +%s)-${name}"
      mv "${item}" "${dest}"
      # Record WHERE it went, not just where it came from: on a name
      # collision the Trash copy is renamed, so reconstructing the path
      # from the basename can point at a different file the user trashed
      # themselves — and restoring would overwrite their file.
      log "[TRASHED] ${size}  ${item}  ->  ${dest}"
    fi
    TOTAL_KB=$((TOTAL_KB + kb))
    COUNT=$((COUNT + 1))
  done < <(find "${dir}" "${find_args[@]}" -print0 2>/dev/null)
}

{
  echo "================================================================"
  echo "$(date '+%Y-%m-%d %H:%M') | downloads janitor | $([[ ${DRY_RUN} -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY') | downloads>${DL_AGE}d screenshots>${SS_AGE}d"
} | tee -a "${LOG_FILE}"

sweep "${HOME}/Downloads" "${DL_AGE}" "Downloads" 0
sweep "${HOME}/Desktop/Screenshots" "${SS_AGE}" "Screenshots" 1

TOTAL_H="$(human "${TOTAL_KB}")"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  log "DRY RUN — would move ${COUNT} item(s), ${TOTAL_H}, to the Trash. Re-run with --apply."
else
  log "DONE — moved ${COUNT} item(s), ${TOTAL_H}, to the Trash (recoverable)."
fi
