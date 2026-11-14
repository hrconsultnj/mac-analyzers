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
# prune old recordings from every source in ANALYZERS_RECORDING_SOURCES (config.local.sh;
# the app writes it), or from ANALYZERS_RECORDINGS_DIR when there is no such list.
# lib/recording-sources.tsv says what one item is for each source: a subfolder, a Zoom
# meeting folder, or a file. This script never looks for a folder: it is told where.
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
# recordings it is the folder's (or file's) path. The script still finds everything itself,
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

# The app groups the app's OWN entitlements declare, one per line. Return 0 when the entitlements were read (an
# app with none, or one that is not signed at all, declares no group); 3 when they could not be read: codesign failed
# for another reason, or did not answer within ANALYZERS_CODESIGN_LIMIT seconds (15) and was stopped. Then "which
# groups does this app declare" is UNKNOWN, not "none".
app_groups_checked() {
  local app="$1" xml errf xmlf rc cpid wpid limit="${ANALYZERS_CODESIGN_LIMIT:-15}"
  errf="$(mktemp "${TMPDIR:-/tmp}/cleanup-codesign.XXXXXX")" || return 3
  xmlf="$(mktemp "${TMPDIR:-/tmp}/cleanup-codesign.XXXXXX")" || { rm -f "$errf"; return 3; }
  codesign -d --entitlements - --xml "$app" > "$xmlf" 2> "$errf" &
  cpid=$!
  ( sleep "$limit"; kill -9 "$cpid" 2>/dev/null ) > /dev/null 2>&1 &
  wpid=$!
  wait "$cpid" 2>/dev/null; rc=$?
  pkill -P "$wpid" 2>/dev/null; kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
  xml="$(cat "$xmlf" 2>/dev/null)"
  if [[ $rc -ne 0 ]]; then
    # "not signed at all": no entitlements. "bundle format unrecognized, invalid, or unsuitable": a folder that only looks
    # like a bundle (no Info.plist, no executable; Xcode's SDKs hold such .xpc stubs): there is no code in it to declare
    # anything. Any other failure is unknown.
    if grep -q -e "not signed at all" -e "bundle format unrecognized, invalid, or unsuitable" "$errf" 2>/dev/null; then rc=0; else rc=3; fi
    rm -f "$errf" "$xmlf"; [[ $rc -eq 0 ]] && return 0; return 3
  fi
  rm -f "$errf" "$xmlf"
  [[ -n "$xml" ]] || return 0
  # (plutil cannot name this key: its path syntax splits at the dots) read the <string>s of the key's array
  printf '%s' "$xml" | awk 'BEGIN { RS = "<" }
    /^key>com\.apple\.security\.application-groups/ { f = 1; next }
    f && /^\/array>/ { exit }
    f && /^string>/ { sub(/^string>/, ""); gsub(/[[:space:]]+$/, ""); print }'
  return 0
}

# the groups the app declares; nothing when they cannot be read (a group container is only ever taken for a group
# the app names)
app_groups() { app_groups_checked "$1" || true; }

# Every bundle that can declare an application group (Apple: "main executables packaged in bundled structures, app
# extensions, App Clips, and XPC Services", and system extensions are bundle main executables too): *.app, *.appex,
# *.xpc, *.systemextension and *.dext, under the app folders AT ANY DEPTH and inside bundles at any depth, nested ones
# inside nested ones too; found once per run. Every way a bundle can sit where this walk would not see it is either
# walked or recorded in INDEX_PROBLEMS, and then "shared elsewhere" is unknown:
#   code that cannot declare one and is not read: frameworks, plug-ins (.plugin, .bundle, .qlgenerator, .mdimporter,
#   .prefPane: they run with their host's entitlements), and BARE helper executables (a tool in Contents/Helpers or
#   Contents/Library/LaunchServices is not a bundle; it cannot be listed without reading every executable, and a
#   `group.` group needs a profile a bare tool cannot carry). Basis: tasks-plans/research/app/app-group-entitlement-carriers-2026-11-12.md
#   a configured app folder that is not there (an unplugged disk): a problem; none could be walked at all: a problem
#   a bundle with no Contents (a flat or wrapped one): searched itself
#   a linked folder in an app folder (never followed: it can point anywhere, a loop, the whole disk): a problem
#   a folder or bundle that could not be read (a find error): a problem
#   an app folder that is itself a link: followed (find -H), it is the folder the person named
#   a bundle named .APP, .App: found (-iname); a linked bundle: found, and read through the link
#   a nested app behind a link inside a bundle (a framework's Versions/Current is a link to a sibling folder that is
#   walked anyway): not followed; links inside bundles stay inside them
INDEX_PROBLEMS=()
ALL_BUNDLES=(); ALL_BUNDLES_DONE=0
_is_bundle_name() { case "$(printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]')" in *.app|*.appex|*.xpc|*.systemextension|*.dext) return 0 ;; esac; return 1; }
_is_app_name() { case "$(printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]')" in *.app) return 0 ;; esac; return 1; }
list_all_app_bundles() {
  [[ "$ALL_BUNDLES_DONE" -eq 1 ]] && return 0
  ALL_BUNDLES_DONE=1
  local dirs dir b n errf out line level walked=0
  local -a contents=()
  errf="$(mktemp "${TMPDIR:-/tmp}/cleanup-find.XXXXXX")" || { INDEX_PROBLEMS+=( "a list of the installed apps could not be made" ); return 0; }
  out="$(mktemp "${TMPDIR:-/tmp}/cleanup-find.XXXXXX")" || { rm -f "$errf"; INDEX_PROBLEMS+=( "a list of the installed apps could not be made" ); return 0; }
  IFS=: read -r -a dirs <<< "${ANALYZERS_APP_DIRS:-/Applications:${HOME_DIR}/Applications}"
  # The lists go through files, not process substitutions: bash 3.2 (the one macOS ships) crashes every later
  # command, and hangs, when process substitutions run in a loop over a few hundred bundles inside a function.
  for dir in "${dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      # a folder the person named that is not there now (an unplugged disk, a removed folder) holds apps nobody can
      # see; the default ~/Applications is allowed to be absent
      [[ -n "${ANALYZERS_APP_DIRS:-}" ]] && INDEX_PROBLEMS+=( "an app folder that is configured is not there: $dir" )
      continue
    fi
    walked=$((walked + 1))
    find -H "$dir" \( \( \( -type d -o -type l \) \( -iname '*.app' -o -iname '*.appex' -o -iname '*.xpc' -o -iname '*.systemextension' -o -iname '*.dext' \) -prune -print0 \) -o \( -type l -print0 \) \) > "$out" 2>>"$errf"
    while IFS= read -r -d '' b; do
      if _is_bundle_name "$b"; then
        ALL_BUNDLES+=( "$b" )
        if [[ -d "$b/Contents" ]]; then contents+=( "$b/Contents" ); elif [[ -d "$b" ]]; then contents+=( "$b" ); fi   # a bundle with no Contents: search it itself
      elif [[ -d "$b" ]]; then
        INDEX_PROBLEMS+=( "a link to a folder inside an app folder is not followed: $b" )
      fi
    done < "$out"
  done
  [[ $walked -gt 0 ]] || INDEX_PROBLEMS+=( "no app folder could be walked" )
  # the bundles INSIDE bundles, level by level (an app inside an app inside an app), each level one find over every
  # Contents folder
  level=0
  while [[ ${#contents[@]} -gt 0 && $level -lt 12 ]]; do
    level=$((level + 1))
    find "${contents[@]}" -mindepth 1 \( -type d -o -type l \) \( -iname '*.app' -o -iname '*.appex' -o -iname '*.xpc' -o -iname '*.systemextension' -o -iname '*.dext' \) -prune -print0 > "$out" 2>>"$errf"
    contents=()
    while IFS= read -r -d '' n; do
      ALL_BUNDLES+=( "$n" )
      if [[ -d "$n/Contents" ]]; then contents+=( "$n/Contents" ); elif [[ -d "$n" ]]; then contents+=( "$n" ); fi
    done < "$out"
  done
  [[ ${#contents[@]} -eq 0 ]] || INDEX_PROBLEMS+=( "bundles nested more than twelve levels deep were not read" )
  if [[ -s "$errf" ]]; then
    line="$(head -n 1 "$errf" | cut -c1-200)"
    INDEX_PROBLEMS+=( "a folder could not be searched: ${line}" )
  fi
  rm -f "$errf" "$out"
  return 0
}

# One line per (group, app) for every bundle, then "!UNREADABLE<TAB>bundle" for each whose entitlements could not be
# read (or not within the time limit). Built once per run, sixteen codesign reads at a time. Every read leaves its own
# file, so a read that was killed before it wrote one is noticed: the index is then not trusted.
GROUP_INDEX=""; GROUP_INDEX_COMPLETE=1
_index_one() {  # bundle outfile
  local b="$1" out="$2" g groups rc
  groups="$(app_groups_checked "$b")"; rc=$?
  if [[ $rc -ne 0 ]]; then printf '!UNREADABLE\t%s\n' "$b" > "$out"; return 0; fi
  : > "$out"
  while IFS= read -r g; do [[ -n "$g" ]] && printf '%s\t%s\n' "$g" "$b" >> "$out"; done <<< "$groups"
  return 0
}
build_group_index() {
  local tmpd i=0 b made=0 line
  GROUP_INDEX="$(mktemp "${TMPDIR:-/tmp}/cleanup-groups.XXXXXX")"
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-groups.XXXXXX")"
  trap 'rm -f "$GROUP_INDEX" "${REC_ERR:-}"' EXIT
  list_all_app_bundles
  for b in ${ALL_BUNDLES[@]+"${ALL_BUNDLES[@]}"}; do
    _index_one "$b" "$tmpd/$i" &
    i=$((i + 1))
    [[ $((i % 16)) -eq 0 ]] && wait
  done
  wait
  made="$(find "$tmpd" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$made" -eq "$i" ]] || INDEX_PROBLEMS+=( "$((i - made)) app reads did not finish" )
  [[ $i -gt 0 ]] && cat "$tmpd"/* >> "$GROUP_INDEX" 2>/dev/null
  rm -rf "$tmpd"
  while IFS=$'\t' read -r line b; do
    [[ "$line" == '!UNREADABLE' ]] && INDEX_PROBLEMS+=( "the settings of ${b##*/} could not be read" )
  done < "$GROUP_INDEX"
  [[ ${#INDEX_PROBLEMS[@]} -eq 0 ]] || GROUP_INDEX_COMPLETE=0
  return 0
}

# Said once, at the end of a run that looked at app groups: why no shared container was taken, when something could
# not be read. The app turns it into a sentence over the table.
report_index_problems() {
  [[ ${#INDEX_PROBLEMS[@]} -gt 0 ]] || return 0
  local joined="" p
  for p in "${INDEX_PROBLEMS[@]}"; do joined="${joined:+$joined; }$p"; done
  echo "[CONTAINERS-KEPT] ${joined}"
}

# Is this group also declared by ANOTHER installed app (any depth, helpers inside other bundles included; the
# app's own helpers do not count)? 0 = yes; 1 = no; 2 = unknown, because some app's entitlements or a folder could
# not be read, so it cannot be said that nobody else uses the group.
group_shared_elsewhere() {  # app group
  local app="$1" group="$2"
  [[ -n "$GROUP_INDEX" ]] || build_group_index
  if awk -F'\t' -v g="$group" -v a="$app" '$1 == g && $2 != a && index($2, a "/") != 1 { found = 1; exit } END { exit found ? 0 : 1 }' "$GROUP_INDEX"; then
    return 0
  fi
  [[ "$GROUP_INDEX_COMPLETE" -eq 1 ]] && return 1
  return 2
}

# May a folder be taken because it carries the app's NAME? Only when no other installed app could own that
# name (the same name, or a longer one that begins with it) and the name is not a runtime name many programs use.
name_is_ours() {  # app name
  local app="$1" lname w other base lbase
  lname="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  for w in $SHARED_RUNTIME_NAMES; do [[ "$lname" == "$w" ]] && return 1; done
  list_all_app_bundles
  # a folder that could not be searched may hold an app that owns the name: then nobody can say the name is the app's alone
  [[ ${#INDEX_PROBLEMS[@]} -eq 0 ]] || return 1
  for other in ${ALL_BUNDLES[@]+"${ALL_BUNDLES[@]}"}; do
    [[ "$other" != "$app" && "$other" != "$app"/* ]] || continue
    _is_app_name "$other" || continue        # an XPC service or an extension does not own an app's name
    base="${other##*/}"; base="${base%.app}"
    lbase="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
    case "$lbase" in "$lname"|"$lname "*|"$lname-"*|"$lname."*) return 1 ;; esac
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
  local declared=" " status
  for g in $(app_groups "$app"); do
    declared="${declared}${g} "
    f="${HOME_DIR}/Library/Group Containers/${g}"
    [[ -e "$f" ]] || continue
    group_shared_elsewhere "$app" "$g"; status=$?
    case "$status" in
      0) APP_LEFT+=( "$f" ); APP_LEFT_WHY+=( "another app shares this group container" ) ;;
      2) APP_LEFT+=( "$f" ); APP_LEFT_WHY+=( "some app's settings could not be read, so it cannot be said that no other app shares this group container" ) ;;
      *) cand+=( "$f" ) ;;
    esac
  done
  # a group container named for the app that its entitlements do not name (an unsigned app, or entitlements that
  # cannot be read): nothing proves it is the app's, so it is shown as left in place, never taken
  for f in "${HOME_DIR}/Library/Group Containers/group.${bid}" "${HOME_DIR}/Library/Group Containers/"??????????".${bid}"; do
    [[ -e "$f" ]] || continue
    g="${f##*/}"
    case "$declared" in *" ${g} "*) continue ;; esac
    [[ "${g%".${bid}"}" == group || "${g%".${bid}"}" =~ ^[A-Z0-9]{10}$ ]] || continue
    APP_LEFT+=( "$f" ); APP_LEFT_WHY+=( "its name matches the app, but the app does not declare it, so nothing shows it is the app's" )
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
  local app_in="$1" app name bid p kb total_kb=0 ans lu keep i nested_count nested_names
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
  # shellcheck source=../lib/launch-items.sh
  [[ -f "$LAUNCH_LIB" ]] && source "$LAUNCH_LIB" 2>/dev/null
  # (the library's anchored matching: see app_name_is_running; without the library the old, looser match)
  if { declare -F app_name_is_running >/dev/null && app_name_is_running "$name"; } \
     || { ! declare -F app_name_is_running >/dev/null && { pgrep -x "$name" >/dev/null 2>&1 || pgrep -f "/${name}.app/Contents/MacOS/" >/dev/null 2>&1; }; }; then
    echo "  ⚠ ${name} appears to be RUNNING — quit it first; skipping this app."
    return 0
  fi
  # apps inside it go with it: say how many, so a person is not surprised
  if declare -F nested_app_names >/dev/null; then
    IFS=$'\t' read -r nested_count nested_names <<< "$(nested_app_names "$app")"
    [[ "${nested_count:-0}" -gt 0 ]] && printf "  contains: %s other app(s) inside it, removed with it: %s (their own settings and data are left in place)\n" "$nested_count" "$nested_names"
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

# Can the Login & Startup Items audit's inventory (login-items.tsv) be trusted? Login items set in System Settings
# leave no file in the app and no launch entry; only this inventory knows them. Prints one word:
#   ok          a real inventory (header "#login-items-inventory", version 2), run today (the date is read from the
#               header, never from the file's time), not dated in the future, and the audit could READ the login items
#   unreadable  a real, recent inventory from a run that could not read them (System Events was not scriptable)
#   missing     none, empty, not an inventory, an unknown version, a date that cannot be read, in the future, or
#               older than a day
inventory_state() {
  local inv="${ANALYZERS_LOGIN_INVENTORY:-${HOME_DIR}/mac-analyzers/reports/storage/login-items.tsv}" head tag ver date logins ts now
  [[ -s "$inv" ]] || { echo missing; return; }
  head="$(head -n 1 "$inv" 2>/dev/null)"
  IFS=$'\t' read -r tag ver date _ _ logins <<< "$head"
  [[ "${tag:-}" == "#login-items-inventory" && "${ver:-}" == "2" ]] || { echo missing; return; }
  ts="$(date -j -f "%Y-%m-%d %H:%M:%S" "${date:-}" +%s 2>/dev/null)" || { echo missing; return; }
  now="$(date +%s)"
  [[ "$ts" -le "$now" && $((now - ts)) -lt 86400 ]] || { echo missing; return; }
  [[ "${logins:-}" == "logins=read" ]] && echo ok || echo unreadable
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
  case "$(inventory_state)" in
    ok) : ;;
    unreadable) echo "Which apps open at login can't be checked yet: the last Login & Startup Items check could not read your Login Items. Run it from the Mac Analyzers app, where macOS can ask for permission, then preview again"; return ;;
    *) echo "Which apps open at login can't be checked yet: run Login & Startup Items first, then preview again"; return ;;
  esac
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
  report_index_problems
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
# build caches out from under running dev servers.
#
# WHERE to look is ANALYZERS_RECORDING_SOURCES in config.local.sh, one "id|state|path" per source
# (written by the app, which is the only thing that discovers a folder; this script never looks for
# one). With no such list, ANALYZERS_RECORDINGS_DIR is the one folder, exactly as before. HOW to read
# each source (what one item is, which extensions, what is kept) comes from lib/recording-sources.tsv.
REC_TSV="${ANALYZERS_ROOT}/lib/recording-sources.tsv"

# rec_refusal <path> <layout>: why this folder can never be a source, else nothing (exit 1).
# Defence in depth: the app's Sources sheet refuses the same folders first.
rec_refusal() {
  local p="$1" layout="$2" lib name
  lib="${HOME_DIR}/Library"
  case "$p" in
    /*) ;;
    *) echo "it is not a full path"; return 0 ;;
  esac
  case "$p" in
    *$'\t'*|*$'\n'*) echo "its name holds a tab or a line break"; return 0 ;;
    */..|*/../*|*/.|*/./*) echo "it is not a plain path"; return 0 ;;
  esac
  if [[ "$p" == "/" || "$p" == "$HOME_DIR" ]]; then echo "it is your whole home folder or the whole disk"; return 0; fi
  case "$p" in
    /Volumes/*) [[ "${p#/Volumes/}" == */* ]] || { echo "it is a whole disk"; return 0; } ;;
  esac
  for name in Desktop Documents Downloads Movies Music Pictures Library; do
    if [[ "$p" == "${HOME_DIR}/${name}" && "$layout" != "files" ]]; then
      echo "it is your whole ${name} folder, which holds more than recordings; choose a folder inside it"; return 0
    fi
  done
  for name in CloudStorage "Mobile Documents" Containers "Group Containers"; do
    if [[ "$p" == "${lib}/${name}" || "$p" == "${lib}/${name}/"* ]]; then
      echo "it syncs to the cloud or belongs to another app, which keeps its own library there"; return 0
    fi
  done
  if [[ -L "$p" ]]; then echo "it is a link to another folder, and a link is not followed"; return 0; fi
  return 1
}

# rec_old <path> <days>: succeeds when NOTHING inside was written for that many days (a folder's own date
# changes only when its direct entries do, so new recordings one level down would make a busy folder look old).
# Sets REC_UNREADABLE=1 when part of it could not be searched, so a newer file may be hiding in there.
rec_old() {
  local newest find_rc
  REC_UNREADABLE=0
  newest="$(find "$1" -mtime "-$2" -print -quit 2>"$REC_ERR")"; find_rc=$?
  [[ -z "$newest" ]] || return 1
  if [[ "$find_rc" -ne 0 || -s "$REC_ERR" ]]; then REC_UNREADABLE=1; fi
  return 0
}

# rec_consider <path>: one item that is old, past every keep rule, to be listed or removed.
rec_consider() {
  local d="$1" kb
  kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
  # something inside could not be searched (an unreadable subfolder): a newer file may be in there, so it cannot be told
  if [[ "$REC_UNREADABLE" -eq 1 ]]; then
    printf "  %-9s %10s  %s  —  %s\n" "[KEEP]" "$(human "$kb")" "$d" "part of it could not be read, so it cannot be told whether anything in it is recent"
    return 0
  fi
  # Zoom writes a raw .zoom file while it records and until it is converted: that is the only copy
  if [[ "$REC_KEEP_ZOOM" -eq 1 && -d "$d" && -n "$(find "$d" -name '*.zoom' -print -quit 2>/dev/null)" ]]; then
    printf "  %-9s %10s  %s  —  %s\n" "[KEEP]" "$(human "$kb")" "$d" "Zoom has not converted this recording yet. Open it in Zoom first."
    return 0
  fi
  if ! approved "$d"; then echo "  [SKIP] not in approved set  ${d}"; return 0; fi
  # a recording on another disk goes to THAT disk's Trash; a disk with none keeps it, with the reason
  if ! trash_dir_for "$d" >/dev/null; then
    printf "  %-9s %10s  %s  —  %s\n" "[KEEP]" "$(human "$kb")" "$d" "this disk has no Trash to move it to"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then reclaim "$d"; else
    # a person's own recordings go to the Trash, with a receipt Undo reads
    if trash_item "$d" "$kb"; then TOTAL_KB=$((TOTAL_KB + kb)); else printf "  [FAILED]  %s\n" "$d"; fi
  fi
}

# rec_has_signature <folder>: Zoom's own marks: recording.conf, a video*.mp4 + audio*.m4a pair, or a *.zoom file.
rec_has_signature() {
  local d="$1"
  [[ -e "$d/recording.conf" ]] && return 0
  [[ -n "$(find "$d" -maxdepth 1 -name '*.zoom' -print -quit 2>/dev/null)" ]] && return 0
  [[ -n "$(find "$d" -maxdepth 1 -name 'video*.mp4' -print -quit 2>/dev/null)" \
     && -n "$(find "$d" -maxdepth 1 -name 'audio*.m4a' -print -quit 2>/dev/null)" ]] && return 0
  return 1
}

# rec_files <dir> <comma extensions>: the files at the top of a folder with one of the extensions.
# The extensions are matched with find -iname, never built into a pattern from a path and never eval'd.
rec_files() {
  local dir="$1" exts="$2" ext
  local args=()
  local IFS_SAVE="$IFS"
  IFS=','; for ext in $exts; do
    [[ -n "$ext" ]] || continue
    [[ ${#args[@]} -gt 0 ]] && args+=( -o )
    args+=( -iname "*.${ext}" )
  done
  IFS="$IFS_SAVE"
  [[ ${#args[@]} -gt 0 ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -type f \( "${args[@]}" \) 2>/dev/null
}

# rec_scan <id> <title> <layout> <exts> <keepIf> <warning> <path> <heading 0|1>
rec_scan() {
  local id="$1" title="$2" layout="$3" exts="$4" keepif="$5" warning="$6" p="$7" heading="$8" why d f
  p="${p%/}"; [[ -n "$p" ]] || p="/"
  if [[ "$heading" -eq 1 ]]; then printf '### Source\t%s\t%s\t%s\n' "$id" "$title" "$p"; fi
  if why="$(rec_refusal "$p" "$layout")"; then
    printf "  %-9s %10s  %s  —  %s\n" "[KEEP]" "" "$p" "not used: ${why}"
    return 0
  fi
  if [[ ! -d "$p" ]]; then echo "  (folder not found: ${p})"; return 0; fi
  [[ -n "$warning" && "$warning" != "-" ]] && echo "  [WARN] ${warning}"
  REC_KEEP_ZOOM=0; [[ "$keepif" == "zoomFile" ]] && REC_KEEP_ZOOM=1
  case "$layout" in
    folders|meetingFolders)
      while IFS= read -r d; do
        if [[ "$layout" == "meetingFolders" ]] && ! rec_has_signature "$d"; then continue; fi
        rec_old "$d" "$REC_DAYS" || continue
        rec_consider "$d"
      done < <(find "$p" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
      if [[ "$layout" == "meetingFolders" ]]; then
        while IFS= read -r f; do
          rec_old "$f" "$REC_DAYS" || continue
          REC_KEEP_ZOOM=0; rec_consider "$f"; REC_KEEP_ZOOM=1
        done < <(rec_files "$p" "$exts")
      fi
      ;;
    files)
      while IFS= read -r f; do
        rec_old "$f" "$REC_DAYS" || continue
        rec_consider "$f"
      done < <(rec_files "$p" "$exts")
      ;;
    *) echo "  (nothing here is ever removed)" ;;
  esac
}

if [[ -n "$REC_DAYS" ]]; then
  group "Recordings older than ${REC_DAYS} days  (cache/log groups skipped)"
  REC_ERR="$(mktemp "${TMPDIR:-/tmp}/cleanup-rec.XXXXXX")"
  trap 'rm -f "${REC_ERR:-}"' EXIT
  REC_UNREADABLE=0; REC_KEEP_ZOOM=0
  REC_LISTED=0
  if [[ -n "${ANALYZERS_RECORDING_SOURCES+x}" && ${#ANALYZERS_RECORDING_SOURCES[@]} -gt 0 ]]; then
    # the list of sources, in the order the person keeps them
    if [[ ! -f "$REC_TSV" ]]; then
      echo "FATAL: lib/recording-sources.tsv is missing, so it cannot be told how to read each source. Nothing was removed." >&2
      exit 78
    fi
    for entry in "${ANALYZERS_RECORDING_SOURCES[@]}"; do
      [[ "$entry" == *"|"*"|"* ]] || { echo "  (a source entry is not id|state|path, skipped)"; continue; }
      rec_id="${entry%%|*}"; rec_rest="${entry#*|}"
      rec_state="${rec_rest%%|*}"; rec_path="${rec_rest#*|}"; rec_path="${rec_path%/}"
      rec_row="$(awk -F'\t' -v id="$rec_id" '/^#/ {next} $1 == id {print; exit}' "$REC_TSV")"
      if [[ -z "$rec_row" ]]; then echo "  (unknown source '${rec_id}', skipped)"; continue; fi
      rec_title="$(printf '%s' "$rec_row" | awk -F'\t' '{print $2}')"
      rec_layout="$(printf '%s' "$rec_row" | awk -F'\t' '{print $4}')"
      rec_exts="$(printf '%s' "$rec_row" | awk -F'\t' '{print ($5 == "-" ? "" : $5)}')"
      rec_keep="$(printf '%s' "$rec_row" | awk -F'\t' '{print $6}')"
      rec_warn="$(printf '%s' "$rec_row" | awk -F'\t' '{print ($9 == "-" ? "" : $9)}')"
      [[ "$rec_id" == "custom" ]] && rec_title="${rec_path##*/}"
      if [[ "$rec_state" != "on" ]]; then
        printf '### Source\t%s\t%s\t%s\n' "$rec_id" "$rec_title" "$rec_path"
        echo "  Turned off in Sources"
        continue
      fi
      REC_LISTED=1
      rec_scan "$rec_id" "$rec_title" "$rec_layout" "$rec_exts" "$rec_keep" "$rec_warn" "$rec_path" 1
    done
  else
    REC_DIR="${ANALYZERS_RECORDINGS_DIR:-}"
    if [[ -n "$REC_DIR" && -d "$REC_DIR" ]]; then
      REC_LISTED=1
      rec_scan custom "${REC_DIR##*/}" folders "" "" "" "$REC_DIR" 0
    fi
  fi
  if [[ "$REC_LISTED" -eq 0 ]]; then
    if [[ -n "${ANALYZERS_RECORDING_SOURCES+x}" && ${#ANALYZERS_RECORDING_SOURCES[@]} -gt 0 ]]; then
      echo "  (no recording folder is turned on in Sources — skipping)"
    else
      echo "  (ANALYZERS_RECORDINGS_DIR not set — skipping)"
    fi
  fi
  echo ""
  echo "=================================================================="
  echo " Recordings total identified: $(human "$TOTAL_KB")"
  [[ "$DRY_RUN" -eq 1 ]] && echo " DRY RUN. Re-run with --execute to move them to the Trash."
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
