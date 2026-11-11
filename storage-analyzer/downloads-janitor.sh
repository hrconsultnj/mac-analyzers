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
  approved_list_has "$1"
}

# The reviewed list is read once (lib/approved-list.sh): a `grep` per item made a
# 6,000-item apply take minutes. A list that cannot be checked stops the run.
if [[ -n "${ONLY_PATHS}" ]]; then
  # look for the file first: under `set -e` a failed `source` ended the run with exit 1 and no words
  if [[ ! -f "${SUITE_DIR}/lib/approved-list.sh" ]] || ! source "${SUITE_DIR}/lib/approved-list.sh" 2>/dev/null; then
    echo "FATAL: lib/approved-list.sh is missing — refusing to run with a reviewed list it cannot check." >&2
    exit 78
  fi
  approved_list_load "${ONLY_PATHS}"
fi

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

# A file that exists only in iCloud (macOS keeps its name and size, not its content, on this Mac):
# prints its real size in KB; prints nothing for anything else. `du` says 0 for these, so a
# preview would call them empty; they are listed on a line of their own instead.
cloud_only_kb() {
  [[ -f "$1" && ! -L "$1" ]] || return 0
  local info
  info="$(stat -f '%Sf %z' "$1" 2>/dev/null)" || return 0
  case "${info%% *}" in
    *dataless*) echo $(( (${info##* } + 1023) / 1024 )) ;;
  esac
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

# A name in the Trash that nothing else has: the plain name, else
# <epoch>-<name>, else <epoch>-<n>-<name>, counting until it is free
# (the same rule temp-clean.sh uses).
trash_dest() {
  local name="$1" dest="${TRASH_DIR}/$1" stamp n=1
  if [[ -e "${dest}" || -L "${dest}" ]]; then
    stamp="$(date +%s)"
    dest="${TRASH_DIR}/${stamp}-${name}"
    while [[ -e "${dest}" || -L "${dest}" ]]; do
      n=$((n + 1))
      dest="${TRASH_DIR}/${stamp}-${n}-${name}"
    done
  fi
  printf '%s' "${dest}"
}

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
  local item name kb size dest moved _try cloud_kb
  while IFS= read -r -d '' item; do
    # A name with a line break cannot be written on one log line or named safely in a
    # reviewed list, so it is left alone and said so (it used to stop the whole run).
    case "${item}" in
      *$'\n'*) log "[SKIP] name contains a line break  ${item//$'\n'/ }"; continue ;;
    esac
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
      cloud_kb=""
      [[ "${kb}" -eq 0 ]] && cloud_kb="$(cloud_only_kb "${item}")"
      if [[ -n "${cloud_kb}" ]]; then
        # moving it frees nothing on this Mac; it removes the iCloud copy once the Trash is emptied
        log "[CLOUD] $(human "${cloud_kb}")  ${item}"
      else
        log "[DRY] ${size}  ${item}"
      fi
    else
      # Never onto something already in the Trash: `trash_dest` finds a free
      # name and `mv -n` refuses to replace anything, so two same-named items
      # moved in one second both stay. `mv -n` exits 0 even when it declined,
      # so the move is believed only when the source is gone and the
      # destination exists; otherwise the next free name is tried.
      moved=0
      for _try in 1 2 3 4 5; do
        dest="$(trash_dest "${name}")"
        # a name that has appeared since trash_dest looked (even as a folder, which
        # `mv` would move the item INTO) is not ours to use: next name
        [[ -e "${dest}" || -L "${dest}" ]] && continue
        mv -n -- "${item}" "${dest}" 2>/dev/null || true
        if [[ ! -e "${item}" && ! -L "${item}" && ( -e "${dest}" || -L "${dest}" ) ]]; then moved=1; break; fi
      done
      if [[ "${moved}" -ne 1 ]]; then
        log "[FAILED] ${size}  ${item}"
        continue
      fi
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
