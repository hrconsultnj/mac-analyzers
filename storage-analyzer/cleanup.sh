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
# Optional extra block (OFF by default), prune old recording folders:
#   ./cleanup.sh --recordings-older-than 90            # dry run
#   ./cleanup.sh --recordings-older-than 90 --execute  # delete
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

# optional per-machine config (gitignored) — see config.example.sh at repo root
ANALYZERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Settings live in the user folder. When the engine runs from inside the
# app bundle, that bundle is replaced wholesale on every update, so the
# user copy is the one that must win.
[[ -f "1/config.local.sh" ]] && source "1/config.local.sh"
[[ -f "/mac-analyzers/config.local.sh" && "1" != "/mac-analyzers" ]] && source "/mac-analyzers/config.local.sh"

# Curated "stale apps" come from config.local.sh (ANALYZERS_STALE_APPS) — run
# analyze.sh §24 (apps by last-opened) to build your list. Only acts with
# --stale-apps, and even then it's a dry run until --execute.
STALE_APPS=()
[[ -n "${ANALYZERS_STALE_APPS+x}" ]] && STALE_APPS=( "${ANALYZERS_STALE_APPS[@]}" )

ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) DRY_RUN=0 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --recordings-older-than) REC_DAYS="${2:-}"; shift ;;
    --app) APP_TARGETS+=( "${2:-}" ); shift ;;
    --stale-apps) DO_STALE_APPS=1 ;;
    --list-app) LIST_APP="${2:-}"; shift ;;
    --skip-build-caches) SKIP_BUILD=1 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
  shift
done

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

# fill global APP_PATHS with every EXISTING footprint path for an app
collect_app_footprint() {
  local app="$1" bid="$2" name="$3" p f
  APP_PATHS=()
  local -a cand=(
    "$app"
    "${HOME_DIR}/Library/Application Support/${name}"
    "${HOME_DIR}/Library/Caches/${name}"
    "${HOME_DIR}/Library/Logs/${name}"
    "${HOME_DIR}/Library/Preferences/${name}.plist"
  )
  if [[ -n "$bid" ]]; then
    cand+=(
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
    for f in "${HOME_DIR}/Library/Preferences/ByHost/${bid}".*; do [[ -e "$f" ]] && cand+=( "$f" ); done
    for f in "${HOME_DIR}/Library/Group Containers/"*"${bid}"*; do [[ -e "$f" ]] && cand+=( "$f" ); done
  fi
  for p in "${cand[@]}"; do [[ -e "$p" ]] && APP_PATHS+=( "$p" ); done
}

# read-only: surface system-level leftovers (need sudo) — never deleted here
detect_system_leftovers() {
  local bid="$1" name="$2" found=0 p
  local -a cand=()
  [[ -n "$name" ]] && for p in "/Library/Application Support/${name}" "/Library/Logs/${name}"; do
    [[ -e "$p" ]] && cand+=( "$p" )
  done
  if [[ -n "$bid" ]]; then
    for p in /Library/LaunchDaemons/*"${bid}"* /Library/LaunchAgents/*"${bid}"* \
             /Library/PrivilegedHelperTools/*"${bid}"* "/Library/Preferences/${bid}.plist" \
             /private/var/db/receipts/*"${bid}"*; do
      [[ -e "$p" ]] && cand+=( "$p" )
    done
  fi
  [[ ${#cand[@]} -gt 0 ]] || return 0
  for p in "${cand[@]}"; do
    [[ $found -eq 0 ]] && { echo "    — system-level leftovers (sudo rm to remove):"; found=1; }
    printf "        %10s  %s\n" "$(du -sh "$p" 2>/dev/null | awk '{print $1}')" "$p"
  done
}

# the granular per-app driver: list full footprint, then (in execute) confirm+remove
purge_app() {
  local app_in="$1" app name bid p kb total_kb=0 ans lu
  app="$(resolve_app_path "$app_in")"
  name="$(basename "${app%.app}")"
  bid="$(resolve_bid "$app")"
  group "APP: ${name}   (bundle: ${bid:-unknown})"
  lu=$(mdls -name kMDItemLastUsedDate -raw "$app" 2>/dev/null)
  [[ -n "$lu" && "$lu" != "(null)" ]] && echo "  last launched (Spotlight): ${lu%% *}"
  if pgrep -x "$name" >/dev/null 2>&1 || pgrep -f "/${name}.app/Contents/MacOS/" >/dev/null 2>&1; then
    echo "  ⚠ ${name} appears to be RUNNING — quit it first; skipping this app."
    return 0
  fi
  collect_app_footprint "$app" "$bid" "$name"
  if [[ ${#APP_PATHS[@]} -eq 0 ]]; then echo "  (no footprint found — already clean)"; return 0; fi
  for p in "${APP_PATHS[@]}"; do
    kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"; total_kb=$((total_kb + kb))
    printf "  %-9s %10s  %s\n" "$([[ $DRY_RUN -eq 1 ]] && echo '[DRY]' || echo '[item]')" "$(human "$kb")" "${p/#${HOME_DIR}/~}"
  done
  printf "  %-9s %10s  TOTAL — %d items\n" " " "$(human "$total_kb")" "${#APP_PATHS[@]}"
  TOTAL_KB=$((TOTAL_KB + total_kb))
  detect_system_leftovers "$bid" "$name"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  if [[ "$ASSUME_YES" -ne 1 ]]; then
    printf "  Remove %s and its %d items (%s)? [y/N] " "$name" "${#APP_PATHS[@]}" "$(human "$total_kb")"
    read -r ans </dev/tty 2>/dev/null || ans="n"
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "  skipped."; return 0; }
  fi
  for p in "${APP_PATHS[@]}"; do rm -rf "$p" 2>/dev/null && printf "  [DELETED] %s\n" "${p/#${HOME_DIR}/~}"; done
}

run_app_mode() {
  local a save
  if [[ -n "$LIST_APP" ]]; then
    save="$DRY_RUN"; DRY_RUN=1; purge_app "$LIST_APP"; DRY_RUN="$save"
  fi
  if [[ "$DO_STALE_APPS" -eq 1 ]]; then
    for a in "${STALE_APPS[@]}"; do purge_app "$a"; done
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
# OPTIONAL — dated recording folders older than N days. OFF unless requested,
# and requires ANALYZERS_RECORDINGS_DIR in config.local.sh.
if [[ -n "$REC_DAYS" ]]; then
  group "7. Recordings older than ${REC_DAYS} days  (OPT-IN)"
  REC_DIR="${ANALYZERS_RECORDINGS_DIR:-}"
  if [[ -n "$REC_DIR" && -d "$REC_DIR" ]]; then
    while IFS= read -r d; do reclaim "$d"; done \
      < <(find "$REC_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+${REC_DAYS}" 2>/dev/null)
  else
    echo "  (ANALYZERS_RECORDINGS_DIR not set — skipping)"
  fi
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
