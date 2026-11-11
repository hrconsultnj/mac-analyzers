#!/usr/bin/env bash
# Storage cleanup — companion to analyze.sh
# ---------------------------------------------------------------------------
# SAFE BY DEFAULT: this script is a DRY RUN unless you pass --execute.
# In dry-run it only PRINTS what it would remove (path + size + running total)
# and deletes NOTHING.
#
#   ./cleanup.sh              # dry run — review what would be freed
#   ./cleanup.sh --execute    # actually delete (asks for confirmation once)
#   ./cleanup.sh --execute --yes   # delete without the confirmation prompt
#
# Recordings mode (opt-in; isolated — the cache/log groups are skipped),
# prune old recording folders:
#   ./cleanup.sh --recordings-older-than 90            # dry run
#   ./cleanup.sh --recordings-older-than 90 --execute  # move to the Trash
#
# GRANULAR per-app removal (opt-in; isolated from the cache/log groups above).
# Sweeps an app's WHOLE footprint: bundle + Application Support, Caches,
# Containers, HTTPStorages, WebKit, Saved State, Preferences (+ByHost),
# Application Scripts, Group Containers, Cookies, Logs — and surfaces
# system-level leftovers that need sudo. Dry-run + per-app [y/N] confirm.
#   ./cleanup.sh --list-app "Kodi"                       # SHOW one app's full footprint, delete nothing
#   ./cleanup.sh --stale-apps                            # dry-run the curated stale list
#   ./cleanup.sh --stale-apps --execute                 # remove them (asks per app)
#   ./cleanup.sh --app "Loom" --app "Framer" --execute  # target specific apps
#
# REVIEWED LIST (the app's Unused Apps and Recordings screens): --only-paths FILE
# acts only on the items whose exact path is a whole line of FILE. For apps the
# key is the app bundle's path (its whole footprint goes with it); for
# recordings it is the folder's path. The script still finds everything itself,
# so a list can only shrink what is touched; an empty list touches nothing.
#   ./cleanup.sh --stale-apps --execute --yes --only-paths /tmp/approved.txt
# App and recordings runs write their blocks to reports/storage/cleanup-apps.log
# and cleanup-recordings.log.
#
# With no list configured in config.local.sh (ANALYZERS_STALE_APPS), --stale-apps LOOKS for
# unused apps itself: apps in /Applications and ~/Applications (ANALYZERS_APP_DIRS: other
# folders, colon-separated) that Spotlight says were last opened ANALYZERS_STALE_APP_DAYS days
# ago (default 180) or more. Found by a date is not chosen by a person, so:
#   * they are only LISTED. Removing them needs a reviewed list (--only-paths, which the Mac
#     Analyzers app writes from what you tick); `--stale-apps --execute` without one refuses
#     (exit 78). Name apps yourself with --app, or list them in ANALYZERS_STALE_APPS, to
#     remove them from Terminal;
#   * an app that cannot be judged is kept and shown as such, never removed: one that is
#     running, that runs on its own (login item, launch agent or daemon, helper tool, system
#     extension, menu-bar or background-only app), that has other apps inside it, that is not a
#     plain folder in an install folder, or that macOS has no usable record for (no index
#     entry, indexing off).
# Removed apps and their files, and removed recordings, go to the Trash, with a receipt Undo can read.
#
# Everything in the main groups is either a regenerable build/cache artifact
# or a path YOU configured as deprecated in config.local.sh. Nothing here is
# irreplaceable content.
# ---------------------------------------------------------------------------

set -u
shopt -s nullglob

DRY_RUN=1
ASSUME_YES=0
REC_DAYS=""
DO_STALE_APPS=0
LIST_APP=""
APP_TARGETS=()
SKIP_BUILD=0
ONLY_PATHS=""

# optional per-machine config (gitignored) — see config.example.sh at repo root
ANALYZERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Settings live in the user folder. When the engine runs from inside the
# app bundle, that bundle is replaced wholesale on every update, so the
# user copy is the one that must win.
[[ -f "${ANALYZERS_ROOT}/config.local.sh" ]] && source "${ANALYZERS_ROOT}/config.local.sh"
[[ -f "$HOME/mac-analyzers/config.local.sh" && "${ANALYZERS_ROOT}" != "$HOME/mac-analyzers" ]] \
  && source "$HOME/mac-analyzers/config.local.sh"

# the launch inventory shared with the login items audit (only discovery needs it)
LAUNCH_LIB="${ANALYZERS_ROOT}/lib/launch-items.sh"

# Curated "stale apps" come from config.local.sh (ANALYZERS_STALE_APPS) — run
# analyze.sh §24 (apps by last-opened) to build your list. Only acts with
# --stale-apps, and even then it's a dry run until --execute.
STALE_APPS=()
STALE_DISCOVERED=0     # 1 when the list was FOUND by a date, not written by the person
PURGE_DISCOVERED=0     # 1 while purge_app works on a found app
PURGE_KEEPCHECK=0      # 1 while purge_app works on an app that is being reviewed: the safety checks apply
[[ -n "${ANALYZERS_STALE_APPS+x}" ]] && STALE_APPS=( "${ANALYZERS_STALE_APPS[@]}" )

ORIG_ARGS="$*"
ORIG_ARR=( "$@" )
while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) DRY_RUN=0 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --recordings-older-than) REC_DAYS="${2:-}"; shift ;;
    --app) APP_TARGETS+=( "${2:-}" ); shift ;;
    --stale-apps) DO_STALE_APPS=1 ;;
    --list-app) LIST_APP="${2:-}"; shift ;;
    --skip-build-caches) SKIP_BUILD=1 ;;
    --only-paths) ONLY_PATHS="${2:-}"; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
  shift
done

# --only-paths <file>: act ONLY on items whose path is a whole line of the file. Looked for
# before `source`, so a missing file or library says why and stops (exit 78) instead of dying silently.
if [[ -n "${ONLY_PATHS}" ]]; then
  if [[ ! -f "${ONLY_PATHS}" ]]; then
    echo "FATAL: --only-paths file not found: ${ONLY_PATHS}" >&2
    exit 78
  fi
  if [[ ! -f "${ANALYZERS_ROOT}/lib/approved-list.sh" ]] || ! source "${ANALYZERS_ROOT}/lib/approved-list.sh" 2>/dev/null; then
    echo "FATAL: lib/approved-list.sh is missing — refusing to run with a reviewed list it cannot check." >&2
    exit 78
  fi
  approved_list_load "${ONLY_PATHS}"
fi
approved() {  # approved <key>: in the reviewed list, or there is none
  [[ -z "${ONLY_PATHS}" ]] && return 0
  approved_list_has "$1"
}

# App and recordings runs are kept in a log of their own, so History and Activity can find them.
# The run starts again with its output piped through `tee`, which keeps the exit status and means
# the log is complete when this process ends.
RUN_KIND=""
if [[ -n "$LIST_APP" || ${#APP_TARGETS[@]} -gt 0 || "$DO_STALE_APPS" -eq 1 ]]; then RUN_KIND="apps"
elif [[ -n "$REC_DAYS" ]]; then RUN_KIND="recordings"; fi
if [[ -n "$RUN_KIND" && -z "${CLEANUP_SCRIPT_TEED:-}" ]]; then
  CLEANUP_LOG_DIR="${HOME}/mac-analyzers/reports/storage"
  mkdir -p "$CLEANUP_LOG_DIR"
  CLEANUP_SCRIPT_TEED=1 "${BASH:-bash}" "$0" "${ORIG_ARR[@]}" 2>&1 | tee -a "${CLEANUP_LOG_DIR}/cleanup-${RUN_KIND}.log"
  exit "${PIPESTATUS[0]}"
fi
if [[ -n "$RUN_KIND" ]]; then
  echo "=================================================================="
  echo "cleanup | ${RUN_KIND} | $([[ "$DRY_RUN" -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY') | $(date '+%Y-%m-%d %H:%M:%S')"
  echo "=================================================================="
fi

# ---------- interactive menu (double-click / bare terminal run) ----------
INTERACTIVE=0
if [[ -z "$ORIG_ARGS" ]] && { [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; }; then
  INTERACTIVE=1
  echo ""
  echo "  storage-cleanup — interactive deep clean"
  echo "  ----------------------------------------"
  echo "  1) Preview main clean (caches, logs, trash — dry run)"
  echo "  2) Execute main clean (asks once before deleting)"
  echo "  3) Preview stale-app removal (curated list)"
  echo "  4) Execute stale-app removal (asks per app)"
  echo "  q) Quit"
  echo ""
  read -rp "  Choose [1]: " choice
  case "${choice:-1}" in
    1) ;;
    2) DRY_RUN=0 ;;
    3) DO_STALE_APPS=1 ;;
    4) DO_STALE_APPS=1; DRY_RUN=0 ;;
    q|Q) exit 0 ;;
    *) echo "  Unknown choice '${choice}' — exiting."; exit 2 ;;
  esac
fi

TOTAL_KB=0
HOME_DIR="${HOME}"

# App mode is active when any app flag was passed; it isolates from groups 1-7.
APP_MODE=0
if [[ ${#APP_TARGETS[@]} -gt 0 || "$DO_STALE_APPS" -eq 1 || -n "$LIST_APP" ]]; then APP_MODE=1; fi

human() {  # KB -> human
  awk -v kb="$1" 'BEGIN{
    if (kb>=1048576) printf "%.1f GB", kb/1048576;
    else if (kb>=1024) printf "%.0f MB", kb/1024;
    else printf "%d KB", kb }'
}

# reclaim <path> [label]
reclaim() {
  local p="$1" label="${2:-}"
  [[ -e "$p" ]] || return 0
  local kb; kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
  TOTAL_KB=$((TOTAL_KB + kb))
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  [DRY]     %10s  %s%s\n" "$(human "$kb")" "$p" "${label:+   ($label)}"
  else
    rm -rf "$p" && printf "  [DELETED] %10s  %s\n" "$(human "$kb")" "$p"
  fi
}

group() { echo ""; echo "### $1"; }

# ---------------------------------------------------------------------------
# Granular per-app removal engine (opt-in via --app / --stale-apps / --list-app)
# ---------------------------------------------------------------------------

# resolve an app's bundle identifier (Spotlight, falling back to Info.plist)
resolve_bid() {
  local app="$1" bid
  bid=$(mdls -name kMDItemCFBundleIdentifier -raw "$app" 2>/dev/null)
  [[ -z "$bid" || "$bid" == "(null)" ]] && bid=$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)
  [[ "$bid" == "(null)" ]] && bid=""
  echo "$bid"
}

# normalize an app arg (name or path) to a .app path (may not exist — data-only
# cleanup still works if the bundle was already trashed)
resolve_app_path() {
  local a="${1%.app}"
  if [[ -d "$1" ]]; then echo "$1"
  elif [[ -d "/Applications/${a}.app" ]]; then echo "/Applications/${a}.app"
  elif [[ -d "${HOME_DIR}/Applications/${a}.app" ]]; then echo "${HOME_DIR}/Applications/${a}.app"
  elif [[ -d "/Applications/Utilities/${a}.app" ]]; then echo "/Applications/Utilities/${a}.app"
  else echo "/Applications/${a}.app"; fi
}

# Names that many programs share: a folder called this is not proof it belongs to the app of the same name.
SHARED_RUNTIME_NAMES="electron python java code docker steam unity google chromium chrome mozilla firefox microsoft adobe jetbrains node npm flutter qt wine android xcode apple"

# The app groups the app's OWN entitlements declare, one per line; nothing when they cannot be read
# (an unsigned app, codesign failing): a group container is only ever taken for a group the app names.
app_groups() {
  local app="$1" xml
  xml="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)" || return 0
  [[ -n "$xml" ]] || return 0
  # (plutil cannot name this key: its path syntax splits at the dots) read the <string>s of the key's array
  printf '%s' "$xml" | awk 'BEGIN { RS = "<" }
    /^key>com\.apple\.security\.application-groups/ { f = 1; next }
    f && /^\/array>/ { exit }
    f && /^string>/ { sub(/^string>/, ""); gsub(/[[:space:]]+$/, ""); print }'
}

# Is this group also declared by ANOTHER installed app? (the index of every app's groups is built once per run)
GROUP_INDEX=""
group_shared_elsewhere() {  # app group
  local app="$1" group="$2" dirs dir other g
  if [[ -z "$GROUP_INDEX" ]]; then
    GROUP_INDEX="$(mktemp "${TMPDIR:-/tmp}/cleanup-groups.XXXXXX")"
    trap 'rm -f "$GROUP_INDEX"' EXIT
    IFS=: read -r -a dirs <<< "${ANALYZERS_APP_DIRS:-/Applications:${HOME_DIR}/Applications}"
    for dir in "${dirs[@]}"; do
      for other in "$dir"/*.app; do
        [[ -d "$other" ]] || continue
        while IFS= read -r g; do [[ -n "$g" ]] && printf '%s\t%s\n' "$g" "$other" >> "$GROUP_INDEX"; done < <(app_groups "$other")
      done
    done
  fi
  awk -F'\t' -v g="$group" -v a="$app" '$1 == g && $2 != a { found = 1; exit } END { exit found ? 0 : 1 }' "$GROUP_INDEX"
}

# May a folder be taken because it carries the app's NAME? Only when no other installed app could own that
# name (the same name, or a longer one that begins with it) and the name is not a runtime name many programs use.
name_is_ours() {  # app name
  local app="$1" lname w dirs dir other base lbase
  lname="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  for w in $SHARED_RUNTIME_NAMES; do [[ "$lname" == "$w" ]] && return 1; done
  IFS=: read -r -a dirs <<< "${ANALYZERS_APP_DIRS:-/Applications:${HOME_DIR}/Applications}"
  for dir in "${dirs[@]}"; do
    for other in "$dir"/*.app; do
      [[ -d "$other" && "$other" != "$app" ]] || continue
      base="${other##*/}"; base="${base%.app}"
      lbase="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
      case "$lbase" in "$lname"|"$lname "*|"$lname-"*|"$lname."*) return 1 ;; esac
    done
  done
  return 0
}

# Fill APP_PATHS with every EXISTING path that goes with the app, and APP_LEFT / APP_LEFT_WHY with the ones that
# are NOT taken and why. Only names that are the app's own, EXACTLY:
#   <Library folder>/<bundle id>[.suffix the system adds]   by bundle id, never by a pattern
#   Preferences/ByHost/<bundle id>.<host uuid>.plist         that file name and no other
#   Group Containers/<group>                                 only for a group the app's own entitlements declare,
#                                                            and no other installed app declares too
#   <Library folder>/<app name>                              by name: with $4 = 1 only when the name is the app's alone
APP_PATHS=(); APP_LEFT=(); APP_LEFT_WHY=()
collect_app_footprint() {
  local app="$1" bid="$2" name="$3" strict="${4:-0}" p f g rest
  APP_PATHS=( "$app" ); APP_LEFT=(); APP_LEFT_WHY=()
  local -a byname=(
    "${HOME_DIR}/Library/Application Support/${name}"
    "${HOME_DIR}/Library/Caches/${name}"
    "${HOME_DIR}/Library/Logs/${name}"
    "${HOME_DIR}/Library/Preferences/${name}.plist"
  )
  for p in "${byname[@]}"; do
    [[ -e "$p" ]] || continue
    if [[ "$strict" -eq 1 ]] && ! name_is_ours "$app" "$name"; then
      APP_LEFT+=( "$p" ); APP_LEFT_WHY+=( "it carries the app's name, but another program may use the same name" )
    else
      APP_PATHS+=( "$p" )
    fi
  done
  [[ -n "$bid" ]] || return 0
  local -a cand=(
    "${HOME_DIR}/Library/Application Support/${bid}"
    "${HOME_DIR}/Library/Caches/${bid}"
    "${HOME_DIR}/Library/Containers/${bid}"
    "${HOME_DIR}/Library/HTTPStorages/${bid}"
    "${HOME_DIR}/Library/WebKit/${bid}"
    "${HOME_DIR}/Library/Saved Application State/${bid}.savedState"
    "${HOME_DIR}/Library/Application Scripts/${bid}"
    "${HOME_DIR}/Library/Preferences/${bid}.plist"
    "${HOME_DIR}/Library/Cookies/${bid}.binarycookies"
    "${HOME_DIR}/Library/Logs/${bid}"
  )
  for f in "${HOME_DIR}/Library/Preferences/ByHost/${bid}."*; do
    [[ -e "$f" ]] || continue
    rest="${f##*/}"; rest="${rest#"${bid}".}"
    [[ "$rest" =~ ^[0-9A-Fa-f-]{36}\.plist$ ]] && cand+=( "$f" )
  done
  for g in $(app_groups "$app"); do
    f="${HOME_DIR}/Library/Group Containers/${g}"
    [[ -e "$f" ]] || continue
    if group_shared_elsewhere "$app" "$g"; then
      APP_LEFT+=( "$f" ); APP_LEFT_WHY+=( "another app shares this group container" )
    else
      cand+=( "$f" )
    fi
  done
  for p in "${cand[@]}"; do [[ -e "$p" ]] && APP_PATHS+=( "$p" ); done
  return 0
}

# read-only: surface system-level leftovers (need sudo) — never deleted here. Exact names only: a
# pattern would list another app's launch entries and helpers (com.vendor.app2 for com.vendor.app).
detect_system_leftovers() {
  local bid="$1" name="$2" found=0 p
  local -a cand=()
  if [[ -n "$name" && "${3:-0}" -eq 0 ]]; then
    for p in "/Library/Application Support/${name}" "/Library/Logs/${name}"; do [[ -e "$p" ]] && cand+=( "$p" ); done
  fi
  if [[ -n "$bid" ]]; then
    for p in "/Library/LaunchDaemons/${bid}.plist" "/Library/LaunchAgents/${bid}.plist" \
             "/Library/PrivilegedHelperTools/${bid}" "/Library/PrivilegedHelperTools/${bid}.helper" \
             "/Library/Preferences/${bid}.plist" "/private/var/db/receipts/${bid}.plist" "/private/var/db/receipts/${bid}.bom"; do
      [[ -e "$p" ]] && cand+=( "$p" )
    done
  fi
  [[ ${#cand[@]} -gt 0 ]] || return 0
  for p in "${cand[@]}"; do
    [[ $found -eq 0 ]] && { echo "    — system-level leftovers (sudo rm to remove):"; found=1; }
    printf "        %10s  %s\n" "$(du -sh "$p" 2>/dev/null | awk '{print $1}')" "$p"
  done
}

# the granular per-app driver: list the full footprint, then (in execute) confirm and remove
purge_app() {
  local app_in="$1" app name bid p kb total_kb=0 ans lu keep i
  app="$(resolve_app_path "$app_in")"
  name="$(basename "${app%.app}")"
  bid="$(resolve_bid "$app")"
  # the reviewed list's key for an app is its bundle's path; each file that goes with it has its own key (its path)
  if ! approved "$app"; then
    group "APP: ${name}   (bundle: ${bid:-unknown})"
    echo "  [SKIP] not in approved set  ${app}"
    return 0
  fi
  group "APP: ${name}   (bundle: ${bid:-unknown})"
  printf "  [APP]     %s\n" "$app"
  lu=$(mdls -name kMDItemLastUsedDate -raw "$app" 2>/dev/null)
  [[ -n "$lu" && "$lu" != "(null)" ]] && echo "  last launched (Spotlight): ${lu%% *}"
  if [[ "$PURGE_KEEPCHECK" -eq 1 ]]; then
    keep="$(app_keep_reason "$app" "$bid")"
    if [[ -n "$keep" ]]; then printf "  [KEEP]    %s\n" "$keep"; return 0; fi
  fi
  if pgrep -x "$name" >/dev/null 2>&1 || pgrep -f "/${name}.app/Contents/MacOS/" >/dev/null 2>&1; then
    echo "  ⚠ ${name} appears to be RUNNING — quit it first; skipping this app."
    return 0
  fi
  collect_app_footprint "$app" "$bid" "$name" "$PURGE_KEEPCHECK"
  for p in "${APP_PATHS[@]}"; do
    kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"; total_kb=$((total_kb + kb))
    printf "  %-9s %10s  %s\n" "$([[ $DRY_RUN -eq 1 ]] && echo '[DRY]' || echo '[item]')" "$(human "$kb")" "$p"
  done
  i=0
  for p in ${APP_LEFT[@]+"${APP_LEFT[@]}"}; do
    kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
    printf "  %-9s %10s  %s  —  %s\n" "[LEFT]" "$(human "$kb")" "$p" "${APP_LEFT_WHY[$i]}"
    i=$((i + 1))
  done
  printf "  %-9s %10s  TOTAL — %d items\n" " " "$(human "$total_kb")" "${#APP_PATHS[@]}"
  TOTAL_KB=$((TOTAL_KB + total_kb))
  detect_system_leftovers "$bid" "$name" "$PURGE_KEEPCHECK"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  if [[ "$ASSUME_YES" -ne 1 ]]; then
    printf "  Remove %s and its %d items (%s)? [y/N] " "$name" "${#APP_PATHS[@]}" "$(human "$total_kb")"
    read -r ans </dev/tty 2>/dev/null || ans="n"
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "  skipped."; return 0; }
  fi
  # The app moves FIRST. If it cannot be moved, nothing else of it is touched: its settings and data without
  # the app would leave it installed and broken.
  kb=$(du -sk "$app" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
  if ! trash_item "$app" "$kb"; then
    printf "  [FAILED]  %s  —  %s; its settings and data were left where they are\n" "$app" "$(move_failure_reason "$app")"
    return 0
  fi
  for p in "${APP_PATHS[@]:1}"; do
    if ! approved "$p"; then echo "  [SKIP] not in approved set  ${p}"; continue; fi
    kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
    trash_item "$p" "$kb" || printf "  [FAILED]  %s\n" "$p"
  done
}

# fill STALE_APPS from the Mac itself when none was configured: apps Spotlight last saw opened
# ANALYZERS_STALE_APP_DAYS days ago or more, and apps it has no record of (purge_app decides which of
# those can be offered: see discovered_keep_reason). Nothing here removes anything.
discover_stale_apps() {
  local days="${ANALYZERS_STALE_APP_DAYS:-180}" app lu cutoff ts dirs dir
  cutoff=$(( $(date +%s) - days * 86400 ))
  STALE_APPS=()
  STALE_DISCOVERED=1
  IFS=: read -r -a dirs <<< "${ANALYZERS_APP_DIRS:-/Applications:${HOME_DIR}/Applications}"
  for dir in "${dirs[@]}"; do
    for app in "$dir"/*.app; do
      [[ -d "$app" || -L "$app" ]] || continue
      lu=$(mdls -name kMDItemLastUsedDate -raw "$app" 2>/dev/null)
      if [[ -n "$lu" && "$lu" != "(null)" ]]; then
        ts=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$lu" +%s 2>/dev/null) || { STALE_APPS+=( "$app" ); continue; }   # unreadable date: listed, and kept
        [[ "$ts" -lt "$cutoff" ]] && STALE_APPS+=( "$app" )
      else
        STALE_APPS+=( "$app" )     # no record of use: listed, then kept or "never opened" (below)
      fi
    done
  done
}

# why an app that cannot be moved cannot be: its folder is not the person's to change
move_failure_reason() {
  if [[ ! -w "$(dirname "$1")" ]]; then echo "it is installed for all users and needs an administrator: remove it in Finder"
  else echo "it could not be moved (is it in use?)"; fi
}

# Is the Login & Startup Items audit's inventory (login-items.tsv) recent enough to trust? Younger than a day.
# Login items set in System Settings leave no file in the app and no launch entry; only this inventory knows them.
inventory_is_fresh() {
  local inv="${ANALYZERS_LOGIN_INVENTORY:-${HOME_DIR}/mac-analyzers/reports/storage/login-items.tsv}" age
  [[ -f "$inv" ]] || return 1
  age=$(( $(date +%s) - $(stat -f %m "$inv" 2>/dev/null || echo 0) ))
  [[ "$age" -lt 86400 ]]
}

# Why an app must not be offered for removal when it is reviewed (the app's own screen, or a found app);
# prints the reason, nothing when it can be. When in doubt the answer is a reason: only an app that can be
# shown to be unused, and that the person can actually move, is offered.
app_keep_reason() {
  local app="$1" bid="$2" days="${ANALYZERS_STALE_APP_DAYS:-180}" cutoff lu added ts why index
  cutoff=$(( $(date +%s) - days * 86400 ))
  case "$bid" in com.apple.*) echo "Part of macOS"; return ;; esac
  [[ -z "$bid" ]] && { echo "macOS cannot say what this app is, so it is kept"; return; }
  if [[ -L "$app" ]]; then echo "Lives on another volume or is a link, so it is kept"; return; fi
  [[ -d "$app/Contents" ]] || { echo "Not a plain app folder, so it is kept"; return; }
  if [[ ! -w "$(dirname "$app")" ]]; then echo "Installed for all users: it needs an administrator, so remove it in Finder"; return; fi
  # runs on its own: the inventory the login items audit reads, and the launch entries that start the app
  # shellcheck source=../lib/launch-items.sh
  if [[ -f "$LAUNCH_LIB" ]] && source "$LAUNCH_LIB" 2>/dev/null; then
    why="$(app_runs_on_its_own "$app" "$bid")" && { echo "$why"; return; }
  else
    echo "The launch inventory (lib/launch-items.sh) is missing, so every app is kept"; return
  fi
  if ! inventory_is_fresh; then
    echo "Which apps open at login can't be checked yet: run Login & Startup Items first, then preview again"; return
  fi
  [[ "$PURGE_DISCOVERED" -eq 1 ]] || return 0      # an app the person named is theirs to remove once these checks pass
  # found by a date: a usable date, or a usable index that knows the app but has no use of it
  lu=$(mdls -name kMDItemLastUsedDate -raw "$app" 2>/dev/null)
  if [[ -n "$lu" && "$lu" != "(null)" ]]; then
    ts=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$lu" +%s 2>/dev/null) \
      || { echo "macOS has no record of when this was last opened"; return; }
    [[ "$ts" -lt "$cutoff" ]] || echo "Opened recently"
    return
  fi
  index="$(mdutil -s / 2>/dev/null)"
  case "$index" in *"Indexing enabled"*) : ;; *) echo "macOS has no record of when this was last opened (indexing is off)"; return ;; esac
  added=$(mdls -name kMDItemDateAdded -raw "$app" 2>/dev/null)
  if [[ -z "$added" || "$added" == "(null)" ]]; then echo "macOS has no record of when this was last opened"; return; fi
  ts=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$added" +%s 2>/dev/null) || { echo "macOS has no record of when this was last opened"; return; }
  [[ "$ts" -lt "$cutoff" ]] || echo "Installed recently, so it is too soon to say it is unused"
}

# The Trash that belongs to the volume a path is on: ~/.Trash for the home volume, <volume>/.Trashes/<uid> for another
# disk (a move across volumes would COPY, fill this disk and could leave half a copy). Fails when that disk has none
# and cannot make one. In a dry run nothing is created.
trash_dir_for() {  # path
  local p="$1" home_dev dev mount d
  home_dev="$(stat -f %d "$HOME_DIR" 2>/dev/null)"; dev="$(stat -f %d "$p" 2>/dev/null)"
  if [[ -z "$dev" || "$dev" == "$home_dev" ]]; then echo "${HOME_DIR}/.Trash"; return 0; fi
  mount="$(df -P "$p" 2>/dev/null | awk 'NR == 2 { $1 = $2 = $3 = $4 = $5 = ""; sub(/^ +/, ""); print }')"
  [[ -n "$mount" && -d "$mount" ]] || return 1
  d="${mount}/.Trashes/$(id -u)"
  if [[ -d "$d" ]]; then echo "$d"; return 0; fi
  if [[ -w "$mount" ]]; then
    [[ "$DRY_RUN" -eq 1 ]] && { echo "$d"; return 0; }
    mkdir -p "$d" 2>/dev/null && chmod 700 "$d" 2>/dev/null && { echo "$d"; return 0; }
  fi
  return 1
}

# a name in a Trash folder that nothing else has: the plain name, else <epoch>-<name>, else <epoch>-<n>-<name>
trash_dest() {  # trash-dir name
  local dir="$1" name="$2" dest stamp n=1
  dest="${dir}/${name}"
  if [[ -e "$dest" || -L "$dest" ]]; then
    stamp="$(date +%s)"; dest="${dir}/${stamp}-${name}"
    while [[ -e "$dest" || -L "$dest" ]]; do dest="${dir}/${stamp}-${n}-${name}"; n=$((n+1)); done
  fi
  echo "$dest"
}

# Move one path to its volume's Trash and print the receipt Undo reads:
#   [TRASHED] size  source  ->  destination  #id=<device:inode>
# The id is the item's identity, kept by a rename, so Undo can prove the Trash still holds THIS item.
trash_item() {  # <path> <size in KB>: 0 when it is in the Trash and the source is gone
  local src="$1" kb="$2" tdir dest _try tid
  tdir="$(trash_dir_for "$src")" || return 1
  mkdir -p "$tdir" 2>/dev/null
  for _try in 1 2 3 4 5; do
    dest="$(trash_dest "$tdir" "$(basename "$src")")"
    [[ -e "$dest" || -L "$dest" ]] && continue
    mv -n -- "$src" "$dest" 2>/dev/null || true
    if [[ ! -e "$src" && ! -L "$src" && ( -e "$dest" || -L "$dest" ) ]]; then
      tid="$(/usr/bin/stat -f '%d:%i' "$dest" 2>/dev/null || true)"
      printf "  [TRASHED] %s  %s  ->  %s%s\n" "$(human "$kb")" "$src" "$dest" "${tid:+  #id=${tid}}"
      return 0
    fi
  done
  return 1
}

run_app_mode() {
  local a save
  if [[ -n "$LIST_APP" ]]; then
    save="$DRY_RUN"; DRY_RUN=1; purge_app "$LIST_APP"; DRY_RUN="$save"
  fi
  if [[ "$DO_STALE_APPS" -eq 1 ]]; then
    [[ ${#STALE_APPS[@]} -eq 0 ]] && discover_stale_apps
    if [[ "$STALE_DISCOVERED" -eq 1 && "$DRY_RUN" -eq 0 && -z "$ONLY_PATHS" ]]; then
      echo "FATAL: these apps were found by a date, not chosen by you, so they are only removed after a review." >&2
      echo "       Review them in the Mac Analyzers app (Storage, Unused Apps), name the ones you want with --app \"Name\"," >&2
      echo "       or list them in ANALYZERS_STALE_APPS in config.local.sh. Nothing was removed." >&2
      exit 78
    fi
    if [[ ${#STALE_APPS[@]} -eq 0 ]]; then echo "  (no unused apps found)"; else
      PURGE_DISCOVERED="$STALE_DISCOVERED"
      # an app that is REVIEWED (the app's preview, a reviewed list) gets the safety checks, found or configured;
      # a configured app removed from Terminal with no list is the person's own choice and keeps its old behaviour
      if [[ "$STALE_DISCOVERED" -eq 1 || "$DRY_RUN" -eq 1 || -n "$ONLY_PATHS" ]]; then PURGE_KEEPCHECK=1; fi
      for a in "${STALE_APPS[@]}"; do purge_app "$a"; done
      PURGE_DISCOVERED=0; PURGE_KEEPCHECK=0
    fi
  fi
  if [[ ${#APP_TARGETS[@]} -gt 0 ]]; then
    for a in "${APP_TARGETS[@]}"; do purge_app "$a"; done
  fi
}

echo "=================================================================="
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo " DRY RUN — nothing will be deleted. Re-run with --execute to act."
else
  echo " EXECUTE MODE — files WILL be deleted."
fi
echo "=================================================================="

# --- APP MODE: when any app flag is passed, do ONLY granular app removal ---
if [[ "$APP_MODE" -eq 1 ]]; then
  echo ""
  echo " APP MODE — granular per-app removal only (cache/log groups skipped)."
  run_app_mode
  echo ""
  echo "=================================================================="
  echo " App-mode total identified: $(human "$TOTAL_KB")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo " DRY RUN. Re-run with --execute (per-app [y/N] confirm; add --yes to skip)."
  fi
  echo "=================================================================="
  exit 0
fi

# --- RECORDINGS MODE: --recordings-older-than prunes recordings ONLY ---
# Isolated like app mode: asking to prune recordings must never also sweep
# build caches out from under running dev servers. Requires
# ANALYZERS_RECORDINGS_DIR in config.local.sh.
if [[ -n "$REC_DAYS" ]]; then
  group "Recordings older than ${REC_DAYS} days  (cache/log groups skipped)"
  REC_DIR="${ANALYZERS_RECORDINGS_DIR:-}"
  if [[ -n "$REC_DIR" && -d "$REC_DIR" ]]; then
    while IFS= read -r d; do
      # old means NOTHING inside was written for REC_DAYS days: a folder's own date changes only when its direct
      # entries do, so new recordings one level down would make a busy folder look old
      [[ -z "$(find "$d" -mtime "-${REC_DAYS}" -print -quit 2>/dev/null)" ]] || continue
      kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
      if ! approved "$d"; then echo "  [SKIP] not in approved set  ${d}"; continue; fi
      # a recording on another disk goes to THAT disk's Trash; a disk with none keeps it, with the reason
      if ! trash_dir_for "$d" >/dev/null; then
        printf "  %-9s %10s  %s  —  %s\n" "[KEEP]" "$(human "$kb")" "$d" "this disk has no Trash to move it to"
        continue
      fi
      if [[ "$DRY_RUN" -eq 1 ]]; then reclaim "$d"; else
        # a person's own recordings go to the Trash, with a receipt Undo reads
        if trash_item "$d" "$kb"; then TOTAL_KB=$((TOTAL_KB + kb)); else printf "  [FAILED]  %s\n" "$d"; fi
      fi
    done < <(find "$REC_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  else
    echo "  (ANALYZERS_RECORDINGS_DIR not set — skipping)"
  fi
  echo ""
  echo "=================================================================="
  echo " Recordings total identified: $(human "$TOTAL_KB")"
  [[ "$DRY_RUN" -eq 1 ]] && echo " DRY RUN. Re-run with --execute to delete."
  echo "=================================================================="
  exit 0
fi

# ---------------------------------------------------------------------------
if [[ "$SKIP_BUILD" -eq 1 ]]; then
  group "1. Next.js / Turbo build caches  — SKIPPED (--skip-build-caches)"
  echo "  Leaving active build caches to auto-clean.sh (removes them once idle >3d)."
else
  group "1. Next.js / Turbo build caches under ~/Projects  (regenerable)"
  # Find .next and .turbo dirs at project level (skip ones nested in node_modules)
  if [[ -d "${HOME_DIR}/Projects" ]]; then
    while IFS= read -r d; do
      [[ "$d" == *"/node_modules/"* ]] && continue
      reclaim "$d"
    done < <(find "${HOME_DIR}/Projects" -type d \( -name .next -o -name .turbo \) -prune 2>/dev/null)
  fi
fi

# ---------------------------------------------------------------------------
group "2. Package-manager caches  (regenerable on next install)"
# Prefer the tools' own prune commands where they exist (safer than rm).
if command -v pnpm >/dev/null 2>&1; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY]     pnpm store prune   (removes only UNREFERENCED packages from ~/Library/pnpm, 9.5G store)"
  else
    echo "  running: pnpm store prune"; pnpm store prune || true
  fi
fi
if command -v npm >/dev/null 2>&1; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY]     npm cache clean --force   (~/.npm)"
  else
    echo "  running: npm cache clean --force"; npm cache clean --force || true
  fi
fi
reclaim "${HOME_DIR}/Library/Caches/pnpm"
reclaim "${HOME_DIR}/.npm-temp-cache"
reclaim "${HOME_DIR}/.expo"
reclaim "${HOME_DIR}/.gradle/caches"
reclaim "${HOME_DIR}/.cache"
reclaim "${HOME_DIR}/.bun/install/cache"

# ---------------------------------------------------------------------------
group "3. App / browser caches under ~/Library/Caches  (apps regenerate)"
for c in \
  "com.operasoftware.Opera" \
  "com.operasoftware.OperaDeveloper" \
  "Mozilla" \
  "electron" \
  "dotslash" \
  "loom-updater" \
  "goto-updater" \
  "com.logmein.goto.ShipIt" \
  "com.microsoft.VSCode.ShipIt" \
  "Google/Chrome" \
  "Homebrew" \
  "node-gyp" \
  "next-swc" ; do
  reclaim "${HOME_DIR}/Library/Caches/${c}"
done

# ---------------------------------------------------------------------------
group "4. Logs & Trash"
for f in "${HOME_DIR}/Library/Logs"/*; do reclaim "$f"; done
for f in "${HOME_DIR}/.Trash"/* "${HOME_DIR}/.Trash"/.[!.]* ; do reclaim "$f"; done

# ---------------------------------------------------------------------------
group "5. DMG installers in ~/Downloads older than 14 days (re-downloadable)"
while IFS= read -r dmg; do reclaim "$dmg"; done \
  < <(find "${HOME_DIR}/Downloads" -maxdepth 1 -name '*.dmg' -mtime +14 2>/dev/null)

# ---------------------------------------------------------------------------
group "6. Deprecated-app leftovers (ANALYZERS_DEPRECATED_PATHS in config.local.sh)"
if [[ -n "${ANALYZERS_DEPRECATED_PATHS+x}" ]]; then
  for p in "${ANALYZERS_DEPRECATED_PATHS[@]}"; do reclaim "$p"; done
else
  echo "  (none configured)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " TOTAL identified: $(human "$TOTAL_KB")"
echo "   (plus whatever 'pnpm store prune' / 'npm cache clean' free above)"
echo "=================================================================="

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "This was a DRY RUN. To actually delete:  $0 --execute"
fi

# ---------- interactive follow-through ----------
if [[ "${INTERACTIVE:-0}" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 && "$TOTAL_KB" -gt 0 ]]; then
    echo ""
    read -rp "  Execute this now? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
      if [[ "$DO_STALE_APPS" -eq 1 ]]; then "$0" --stale-apps --execute; else "$0" --execute; fi
    fi
  fi
  echo ""
  read -rp "  Done — press Enter to close this window… " _
fi
