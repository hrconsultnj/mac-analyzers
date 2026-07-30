#!/usr/bin/env bash
# Storage analyzer for macOS — READ-ONLY.
# Scans common space-hog locations and writes a categorized markdown report.
# This script never deletes, moves, or modifies any file.
#
# Usage: ./analyze.sh [output_dir]
#   default output_dir: ~/storage-reports

set -u
shopt -s nullglob

HOME_DIR="${HOME}"
OUT_DIR="${1:-${HOME_DIR}/system-reports/storage}"
DATE_DIR="${OUT_DIR}/$(date +%Y-%m-%d)"
REPORT="${DATE_DIR}/report-$(date +%H%M).md"
LATEST="${OUT_DIR}/latest.md"

mkdir -p "${DATE_DIR}"

# ---------- helpers ----------
# du -sh that gracefully handles missing dirs and permission errors
size_of() {
  local path="$1"
  if [[ -e "$path" ]]; then
    du -sh "$path" 2>/dev/null | awk '{print $1}'
  else
    echo "-"
  fi
}

# Top-N children of a dir by size, formatted as markdown table rows
top_children() {
  local dir="$1"
  local n="${2:-15}"
  [[ -d "$dir" ]] || { echo "_(not present)_"; return; }
  # du in KB then sort, then humanize
  du -sk "${dir}"/* "${dir}"/.* 2>/dev/null \
    | grep -vE "/\.\.?$" \
    | sort -rn \
    | head -n "$n" \
    | awk '{
        kb=$1; $1=""; sub(/^ /,"");
        if (kb>=1048576) printf "| %.1f GB | %s |\n", kb/1048576, $0;
        else if (kb>=1024) printf "| %.0f MB | %s |\n", kb/1024, $0;
        else printf "| %d KB | %s |\n", kb, $0
      }'
}

section() {
  echo ""
  echo "## $1"
  echo ""
}

table_header() {
  echo "| Size | Path |"
  echo "|------|------|"
}

# ---------- last-used / activity helpers (for the decision sections 24-27) ----------
# spotlight metadata date (YYYY-MM-DD) for an attribute (default last-used), or "-"
mdls_date() {
  local v; v=$(mdls -name "${2:-kMDItemLastUsedDate}" -raw "$1" 2>/dev/null)
  [[ -z "$v" || "$v" == "(null)" ]] && { echo "-"; return; }
  echo "${v%% *}"
}

# whole days since a YYYY-MM-DD date; -1 if blank/unknown
days_since() {
  local d="$1" t
  [[ -z "$d" || "$d" == "-" ]] && { echo "-1"; return; }
  t=$(date -j -f "%Y-%m-%d" "$d" "+%s" 2>/dev/null) || { echo "-1"; return; }
  echo $(( ($(date +%s) - t) / 86400 ))
}

# whole days since an epoch-seconds value; -1 if blank
days_since_epoch() {
  local e="$1"; [[ -z "$e" ]] && { echo "-1"; return; }
  echo $(( ($(date +%s) - e) / 86400 ))
}

# Best "last used" epoch for an .app: newest of Spotlight last-used + the app's
# own data-dir mtimes (saved state / prefs / container / httpstorage). Robust to
# apps whose Spotlight metadata was wiped by a migration. Empty if no signal.
app_best_epoch() {
  local app="$1" bid lu e best="" p
  bid=$(mdls -name kMDItemCFBundleIdentifier -raw "$app" 2>/dev/null)
  [[ -z "$bid" || "$bid" == "(null)" ]] && bid=$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)
  lu=$(mdls -name kMDItemLastUsedDate -raw "$app" 2>/dev/null)
  if [[ -n "$lu" && "$lu" != "(null)" ]]; then
    e=$(date -j -f '%Y-%m-%d %H:%M:%S %z' "$lu" '+%s' 2>/dev/null)
    [[ -n "$e" ]] && best="$e"
  fi
  if [[ -n "$bid" && "$bid" != "(null)" ]]; then
    for p in \
      "${HOME_DIR}/Library/Saved Application State/${bid}.savedState" \
      "${HOME_DIR}/Library/Preferences/${bid}.plist" \
      "${HOME_DIR}/Library/Containers/${bid}" \
      "${HOME_DIR}/Library/HTTPStorages/${bid}"; do
      [[ -e "$p" ]] || continue
      e=$(stat -f '%m' "$p" 2>/dev/null)
      [[ -n "$e" && ( -z "$best" || "$e" -gt "$best" ) ]] && best="$e"
    done
  fi
  echo "$best"
}

# run a command with a timeout (macOS ships no `timeout`); prints its output,
# or a note if it hangs past <secs>. Used to stop `docker system df` blocking.
timed() {
  local secs="$1"; shift
  local tmpf; tmpf="$(mktemp)"
  ( "$@" >"$tmpf" 2>&1 ) & local pid=$!
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1; i=$((i+1))
    if [[ $i -ge $secs ]]; then
      kill -9 "$pid" 2>/dev/null
      echo "(timed out after ${secs}s — skipped)"
      rm -f "$tmpf"; return 124
    fi
  done
  wait "$pid" 2>/dev/null
  cat "$tmpf"; rm -f "$tmpf"
}

# ---------- begin report ----------
{
  echo "# Storage Analyzer Report"
  echo ""
  echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "**Host:** $(hostname)"
  echo "**User:** ${USER}"
  echo "**Invocation:** analyze.sh${1:+ $1}$( [[ -t 0 ]] && echo " (interactive)" )"
  echo ""
  echo "> Read-only scan. No files were modified."
  echo ""

  # ---------- 1. Volume summary ----------
  section "1. Volume Summary"
  echo '```'
  df -h | awk 'NR==1 || /\/System\/Volumes\/Data$|^\/dev\/disk3s1s1/'
  echo '```'
  echo ""
  echo "APFS container usage:"
  echo '```'
  diskutil apfs list 2>/dev/null | grep -E "Container disk3|Capacity (Ceiling|In Use|Not Allocated)" | head -5
  echo '```'

  # ---------- 2. Top-level home directories ----------
  section "2. Top 20 Items in \$HOME"
  echo "_(includes hidden directories like ~/Library, ~/.docker)_"
  echo ""
  table_header
  top_children "$HOME_DIR" 20

  # ---------- 3. ~/Library breakdown ----------
  section "3. ~/Library — Top 20"
  echo "_macOS app data lives here. Not all of this is safe to touch._"
  echo ""
  table_header
  top_children "$HOME_DIR/Library" 20

  # ---------- 4. Caches ----------
  section "4. ~/Library/Caches — Top 20"
  echo "_Caches are generally safe to delete; apps regenerate them._"
  echo ""
  table_header
  top_children "$HOME_DIR/Library/Caches" 20

  # ---------- 5. Application Support ----------
  section "5. ~/Library/Application Support — Top 20"
  echo "_App data: configs, databases, downloaded models. Some safe, some critical._"
  echo ""
  table_header
  top_children "$HOME_DIR/Library/Application Support" 20

  # ---------- 6. Containers (sandboxed apps) ----------
  section "6. ~/Library/Containers — Top 20"
  echo "_Sandboxed app data. Often holds large content like Docker, Mail, Photos cache._"
  echo ""
  table_header
  top_children "$HOME_DIR/Library/Containers" 20

  # ---------- 7. Group Containers ----------
  section "7. ~/Library/Group Containers — Top 20"
  echo ""
  table_header
  top_children "$HOME_DIR/Library/Group Containers" 20

  # ---------- 8. Developer (Xcode et al) ----------
  section "8. ~/Library/Developer — Top 20"
  echo "_Xcode DerivedData, iOS device support, simulators, archives. Mostly regenerable._"
  echo ""
  table_header
  top_children "$HOME_DIR/Library/Developer" 20
  echo ""
  echo "**Notable subdirectories:**"
  echo ""
  table_header
  for sub in "Xcode/DerivedData" "Xcode/Archives" "Xcode/iOS DeviceSupport" "Xcode/watchOS DeviceSupport" "Xcode/UserData" "CoreSimulator/Caches" "CoreSimulator/Devices" "CoreSimulator/Volumes"; do
    p="${HOME_DIR}/Library/Developer/${sub}"
    if [[ -d "$p" ]]; then
      sz=$(size_of "$p")
      echo "| ${sz} | ~/Library/Developer/${sub} |"
    fi
  done

  # ---------- 9. Logs ----------
  section "9. ~/Library/Logs — Total"
  table_header
  echo "| $(size_of "$HOME_DIR/Library/Logs") | ~/Library/Logs |"
  echo "| $(size_of "/Library/Logs") | /Library/Logs |"
  echo "| $(size_of "/private/var/log") | /private/var/log |"

  # ---------- 10. Dev toolchain caches (dotfiles) ----------
  section "10. Dev Toolchain Caches"
  echo "_These are package manager caches — safe to delete; will redownload on next install._"
  echo ""
  table_header
  for d in .npm .pnpm-store .yarn .bun .cache .cargo .rustup .gradle .m2 .ivy2 .cocoapods .gem .deno .nvm .nuget .android/build-cache .docker .electron-gyp .expo .next-cache; do
    p="${HOME_DIR}/${d}"
    if [[ -e "$p" ]]; then
      sz=$(size_of "$p")
      echo "| ${sz} | ~/${d} |"
    fi
  done

  # ---------- 11. Docker data ----------
  section "11. Docker Desktop Data"
  echo ""
  table_header
  for p in \
    "${HOME_DIR}/Library/Containers/com.docker.docker" \
    "${HOME_DIR}/Library/Group Containers/group.com.docker" \
    "${HOME_DIR}/.docker"; do
    if [[ -e "$p" ]]; then
      sz=$(size_of "$p")
      echo "| ${sz} | ${p/${HOME_DIR}/~} |"
    fi
  done
  if command -v docker >/dev/null 2>&1; then
    echo ""
    echo "**\`docker system df\`:**"
    echo '```'
    timed 12 docker system df
    echo '```'
  fi

  # ---------- 12. node_modules in Projects ----------
  section "12. node_modules under ~/Projects"
  echo "_Each is regenerable via \`npm install\` / \`bun install\` / \`pnpm install\`._"
  echo "_Showing top 30, sorted by size._"
  echo ""
  table_header
  if [[ -d "${HOME_DIR}/Projects" ]]; then
    find "${HOME_DIR}/Projects" -type d -name node_modules -prune 2>/dev/null \
      | while read -r nm; do
          du -sk "$nm" 2>/dev/null
        done \
      | sort -rn \
      | head -30 \
      | awk '{
          kb=$1; $1=""; sub(/^ /,"");
          if (kb>=1048576) printf "| %.1f GB | %s |\n", kb/1048576, $0;
          else printf "| %.0f MB | %s |\n", kb/1024, $0
        }'
    echo ""
    total_kb=$(find "${HOME_DIR}/Projects" -type d -name node_modules -prune 2>/dev/null \
      | while read -r nm; do du -sk "$nm" 2>/dev/null | awk '{print $1}'; done \
      | awk '{sum+=$1} END{print sum+0}')
    echo "**Total node_modules across ~/Projects:** $(awk -v kb="$total_kb" 'BEGIN{ if (kb>=1048576) printf "%.1f GB", kb/1048576; else printf "%.0f MB", kb/1024 }')"
  fi

  # ---------- 13. Other build/cache dirs in Projects ----------
  section "13. Build/Cache Directories under ~/Projects"
  echo "_Top 25 of: .next, dist, build, .turbo, .cache, .vite, target, .nuxt, .svelte-kit_"
  echo ""
  table_header
  if [[ -d "${HOME_DIR}/Projects" ]]; then
    find "${HOME_DIR}/Projects" -type d \( \
        -name .next -o -name dist -o -name build -o -name .turbo -o -name .cache -o \
        -name .vite -o -name target -o -name .nuxt -o -name .svelte-kit -o -name .parcel-cache \
      \) -prune 2>/dev/null \
      | while read -r d; do du -sk "$d" 2>/dev/null; done \
      | sort -rn \
      | head -25 \
      | awk '{
          kb=$1; $1=""; sub(/^ /,"");
          if (kb>=1048576) printf "| %.1f GB | %s |\n", kb/1048576, $0;
          else printf "| %.0f MB | %s |\n", kb/1024, $0
        }'
  fi

  # ---------- 14. Downloads ----------
  section "14. ~/Downloads — Top 20"
  echo ""
  table_header
  top_children "$HOME_DIR/Downloads" 20

  # ---------- 15. Trash ----------
  section "15. Trash"
  echo ""
  table_header
  echo "| $(size_of "$HOME_DIR/.Trash") | ~/.Trash |"
  for v in /Volumes/*; do
    [[ -d "${v}/.Trashes" ]] && echo "| $(size_of "${v}/.Trashes") | ${v}/.Trashes |"
  done

  # ---------- 16. Desktop / Documents / Movies / Pictures / Music totals ----------
  section "16. User Content Folders (totals only)"
  echo ""
  table_header
  for d in Desktop Documents Movies Music Pictures; do
    p="${HOME_DIR}/${d}"
    [[ -d "$p" ]] && echo "| $(size_of "$p") | ~/${d} |"
  done

  # ---------- 17. iCloud local cache ----------
  section "17. iCloud Drive (local cache)"
  echo ""
  table_header
  p="${HOME_DIR}/Library/Mobile Documents/com~apple~CloudDocs"
  [[ -d "$p" ]] && echo "| $(size_of "$p") | ~/Library/Mobile Documents/com~apple~CloudDocs |"

  # ---------- 18. Photos / Mail ----------
  section "18. Photos & Mail"
  echo ""
  table_header
  for p in "${HOME_DIR}/Pictures/Photos Library.photoslibrary" "${HOME_DIR}/Library/Mail" "${HOME_DIR}/Library/Containers/com.apple.mail"; do
    [[ -e "$p" ]] && echo "| $(size_of "$p") | ${p/${HOME_DIR}/~} |"
  done

  # ---------- 19. Browser caches/profiles ----------
  section "19. Browser Caches & Profiles"
  echo ""
  table_header
  for p in \
    "${HOME_DIR}/Library/Application Support/Google/Chrome" \
    "${HOME_DIR}/Library/Caches/Google/Chrome" \
    "${HOME_DIR}/Library/Application Support/Firefox" \
    "${HOME_DIR}/Library/Caches/Firefox" \
    "${HOME_DIR}/Library/Application Support/Arc" \
    "${HOME_DIR}/Library/Caches/Arc" \
    "${HOME_DIR}/Library/Containers/com.apple.Safari" \
    "${HOME_DIR}/Library/Application Support/Microsoft Edge" \
    "${HOME_DIR}/Library/Application Support/BraveSoftware"; do
    [[ -e "$p" ]] && echo "| $(size_of "$p") | ${p/${HOME_DIR}/~} |"
  done

  # ---------- 20. AI/Editor app data ----------
  section "20. AI Tools & Editors (often large)"
  echo ""
  table_header
  for p in \
    "${HOME_DIR}/.cursor" \
    "${HOME_DIR}/Library/Application Support/Cursor" \
    "${HOME_DIR}/Library/Application Support/Code" \
    "${HOME_DIR}/Library/Application Support/Code - Insiders" \
    "${HOME_DIR}/Library/Application Support/Claude" \
    "${HOME_DIR}/Library/Caches/Cursor" \
    "${HOME_DIR}/Library/Caches/com.todesktop.230313mzl4w4u92" \
    "${HOME_DIR}/.codex" \
    "${HOME_DIR}/.continue" \
    "${HOME_DIR}/.aider" \
    "${HOME_DIR}/.copilot" \
    "${HOME_DIR}/.coderabbit" \
    "${HOME_DIR}/.composure" \
    "${HOME_DIR}/.claude" \
    "${HOME_DIR}/.cagent"; do
    [[ -e "$p" ]] && echo "| $(size_of "$p") | ${p/${HOME_DIR}/~} |"
  done

  # ---------- 21. Large files anywhere in $HOME ----------
  section "21. Files Larger Than 500MB Anywhere in \$HOME"
  echo "_Excludes ~/Library by default to keep this readable._"
  echo ""
  table_header
  # -prune stops find from DESCENDING into the excluded dirs (-not -path only
  # hides matches but still walks them — it wedged for hours on cloud-backed
  # paths). node_modules pruned too: millions of inodes, and sections 12-13
  # already size them; any big files inside are regenerable.
  find "${HOME_DIR}" \( -path "${HOME_DIR}/Library" -o -path "${HOME_DIR}/.Trash" -o -name node_modules \) -prune \
    -o -type f -size +500M -print \
    2>/dev/null \
    | while read -r f; do du -sk "$f" 2>/dev/null; done \
    | sort -rn \
    | head -50 \
    | awk '{
        kb=$1; $1=""; sub(/^ /,"");
        if (kb>=1048576) printf "| %.1f GB | %s |\n", kb/1048576, $0;
        else printf "| %.0f MB | %s |\n", kb/1024, $0
      }'

  # ---------- 22. APFS local snapshots ----------
  section "22. APFS Local Snapshots (Time Machine)"
  echo "_Local snapshots can hold significant space if Time Machine is on. They roll over automatically but you can list them._"
  echo ""
  echo '```'
  tmutil listlocalsnapshots / 2>/dev/null || echo "(tmutil unavailable)"
  echo '```'

  # ---------- 23. /private/var (system temp) ----------
  section "23. System Temp & Scratch"
  echo ""
  table_header
  for p in /private/var/folders /private/tmp /private/var/log; do
    [[ -e "$p" ]] && echo "| $(sudo -n du -sh "$p" 2>/dev/null | awk '{print $1}' || echo "?") | ${p} |"
  done

  # ====================================================================
  #  DECISION CLASSIFIER — "is this still used?" signals, oldest first
  # ====================================================================

  # ---------- 24. Applications by last opened ----------
  section "24. Applications — by last opened (oldest / never-used first)"
  echo "_Composite of Spotlight last-used + the app's own data-dir activity (so it survives migrations that wipe Spotlight metadata). 'never?' = no usage signal at all (often a web-stub or genuinely never launched). Verify before removing._"
  echo ""
  echo "| Last used | Days ago | Size | App |"
  echo "|-----------|----------|------|-----|"
  {
    for appdir in /Applications /Applications/Utilities "${HOME_DIR}/Applications"; do
      [[ -d "$appdir" ]] || continue
      for app in "$appdir"/*.app; do
        [[ -e "$app" ]] || continue
        e=$(app_best_epoch "$app"); ds=$(days_since_epoch "$e")
        if [[ "$ds" == "-1" ]]; then sk=99999; dsd="never?"; dd="-"; else sk=$ds; dsd="$ds"; dd=$(date -r "$e" '+%Y-%m-%d'); fi
        printf "%05d\t%s\t%s\t%s\t%s\n" "$sk" "$dd" "$dsd" "$(size_of "$app")" "${app##*/}"
      done
    done
  } | sort -rn | head -45 | awk -F'\t' '{printf "| %s | %s | %s | %s |\n",$2,$3,$4,$5}'

  # ---------- 25. Downloads by idle time ----------
  section "25. ~/Downloads — by idle time (oldest first)"
  echo "_Added = when it arrived; Last opened = if ever used; Idle = days since last touch._"
  echo ""
  echo "| Last opened | Added | Days idle | Size | Item |"
  echo "|-------------|-------|-----------|------|------|"
  {
    for item in "${HOME_DIR}/Downloads"/* "${HOME_DIR}/Downloads"/.[!.]*; do
      [[ -e "$item" ]] || continue
      lu=$(mdls_date "$item"); da=$(mdls_date "$item" kMDItemDateAdded)
      ref="$lu"; [[ "$ref" == "-" ]] && ref="$da"
      ds=$(days_since "$ref"); if [[ "$ds" == "-1" ]]; then sk=99999; dsd="?"; else sk=$ds; dsd="$ds"; fi
      printf "%05d\t%s\t%s\t%s\t%s\t%s\n" "$sk" "$lu" "$da" "$dsd" "$(size_of "$item")" "${item##*/}"
    done
  } | sort -rn | head -40 | awk -F'\t' '{printf "| %s | %s | %s | %s | %s |\n",$2,$3,$4,$5,$6}'

  # ---------- 26. Projects by last git activity ----------
  section "26. ~/Projects — by last activity (oldest first)"
  echo "_Last git commit per repo (folder mtime if no git). Stale repos = safe build-cache / node_modules candidates for cleanup.sh / auto-clean.sh._"
  echo ""
  echo "| Last activity | Days ago | Size | Repo / Folder |"
  echo "|---------------|----------|------|---------------|"
  if [[ -d "${HOME_DIR}/Projects" ]]; then
    {
      find "${HOME_DIR}/Projects" -maxdepth 3 -type d -name .git -prune 2>/dev/null | while read -r g; do
        root="$(dirname "$g")"
        d=$(git -C "$root" log -1 --format=%cs 2>/dev/null)
        [[ -z "$d" ]] && d=$(stat -f '%Sm' -t '%Y-%m-%d' "$root" 2>/dev/null)
        ds=$(days_since "$d"); if [[ "$ds" == "-1" ]]; then sk=99999; dsd="?"; else sk=$ds; dsd="$ds"; fi
        printf "%05d\t%s\t%s\t%s\t%s\n" "$sk" "$d" "$dsd" "$(size_of "$root")" "${root#${HOME_DIR}/Projects/}"
      done
    } | sort -rn | head -40 | awk -F'\t' '{printf "| %s | %s | %s | %s |\n",$2,$3,$4,$5}'
  fi

  # ---------- 27. Documents & Desktop by last modified ----------
  section "27. ~/Documents & ~/Desktop — top-level by last modified (oldest first)"
  echo ""
  echo "| Modified | Days ago | Size | Item |"
  echo "|----------|----------|------|------|"
  {
    for base in "${HOME_DIR}/Documents" "${HOME_DIR}/Desktop"; do
      [[ -d "$base" ]] || continue
      for item in "$base"/* "$base"/.[!.]*; do
        [[ -e "$item" ]] || continue
        d=$(stat -f '%Sm' -t '%Y-%m-%d' "$item" 2>/dev/null)
        ds=$(days_since "$d"); if [[ "$ds" == "-1" ]]; then sk=99999; dsd="?"; else sk=$ds; dsd="$ds"; fi
        printf "%05d\t%s\t%s\t%s\t%s\n" "$sk" "$d" "$dsd" "$(size_of "$item")" "${item#${HOME_DIR}/}"
      done
    done
  } | sort -rn | head -30 | awk -F'\t' '{printf "| %s | %s | %s | %s |\n",$2,$3,$4,$5}'

  echo ""
  echo "---"
  echo ""
  echo "_Report ends. Review with Claude or your own judgment before deleting anything._"
} > "${REPORT}"

# Update latest.md symlink
ln -sfn "${REPORT}" "${LATEST}"

echo "Report written to: ${REPORT}"
echo "Latest symlink:    ${LATEST}"

# ---------- interactive follow-through (double-click / bare terminal run) ----------
if [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; then
  read -rp "Open the report now? [Y/n] " yn
  [[ ! "$yn" =~ ^[Nn]$ ]] && open "${REPORT}"
  read -rp "Done — press Enter to close this window… " _
fi
