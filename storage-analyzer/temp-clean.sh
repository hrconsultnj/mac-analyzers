#!/usr/bin/env bash
# temp-clean.sh — what's really in /tmp, /var and your AI agents' folders,
# and a reviewed way to clear it
# ---------------------------------------------------------------------------
# Answers what `du /tmp` gets wrong:
#
#   1. DISK IMAGES — a folder in /tmp can be a MOUNTED disk image. Its contents
#      are not on your disk, but `du` counts them. They are listed on their own,
#      with the file that backs each one. Eject one with --eject <mountpoint>.
#   2. TEMP       — /tmp, your per-user temp folder ($TMPDIR) and /var/tmp,
#      entry by entry: what is ready to clear, and why everything else is left
#      alone (open right now, changed recently, someone else's, a system lock).
#   3. AI AGENTS  — Claude Code, Codex, the Claude app and npx-launched MCP
#      servers leave scratch behind. Only what the tool does NOT already clean
#      for itself, and only what it regenerates, is offered. Transcripts,
#      settings, credentials and databases are sized, never touched.
#   4. MANAGED    — macOS's own areas (logs, code-signing clones, app caches),
#      sized and explained. Never touched.
#
# CLEANER contract: dry-run by default. --apply moves approved items to the
# Trash (recoverable — receipts in the log, restorable from the app's Undo
# screen). --apply --permanent deletes them instead. An approved item that
# backs a mounted disk image ejects that image first (never forced); if the
# eject fails, the item is left alone.
#
# Knobs (config.local.sh):
#   TEMP_CLEAN_MIN_AGE_HOURS=24        # temp entries must be idle this long
#   TEMP_CLEAN_AGENT_SCRATCH_DAYS=3    # agent scratch must be idle this long
#   TEMP_CLEAN_NPX_DAYS=14             # npx packages must be idle this long
#   TEMP_CLEAN_KEEP_PATTERNS="*.iso:my-build-*"   # colon globs, never touched
#   ANALYZERS_AGENT_DIRS="$HOME/some/agent/archive"  # extra dirs, sized only
#
#   ./temp-clean.sh                          # audit (dry run)
#   ./temp-clean.sh --apply                  # move ready items to the Trash
#   ./temp-clean.sh --apply --permanent      # delete ready items for good
#   ./temp-clean.sh --eject /private/tmp/X   # eject a disk image mounted in temp
#   ./temp-clean.sh --apply --only-paths F   # act only on paths/tokens listed in F
# ---------------------------------------------------------------------------

set -u
shopt -s nullglob

DRY_RUN=1
PERMANENT=0
ONLY_PATHS=""
MIN_AGE_ARG=""
EJECT_TARGETS=()

LOG_DIR="${HOME}/mac-analyzers/reports/storage"
LOG_FILE="${LOG_DIR}/temp-clean.log"
LOCK_FILE="${LOG_DIR}/.temp-clean.lock"

# optional per-machine config (gitignored) — see config.example.sh at repo root
ANALYZERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Settings live in the user folder. When the engine runs from inside the
# app bundle, that bundle is replaced wholesale on every update, so the
# user copy is the one that must win.
[[ -f "${ANALYZERS_ROOT}/config.local.sh" ]] && source "${ANALYZERS_ROOT}/config.local.sh"
[[ -f "$HOME/mac-analyzers/config.local.sh" && "${ANALYZERS_ROOT}" != "$HOME/mac-analyzers" ]] \
  && source "$HOME/mac-analyzers/config.local.sh"

ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)         DRY_RUN=0 ;;
    --dry-run)       DRY_RUN=1 ;;
    --permanent)     PERMANENT=1 ;;
    --only-paths)    ONLY_PATHS="${2:-}"; shift ;;
    --min-age-hours) MIN_AGE_ARG="${2:-}"; shift ;;
    --eject)         EJECT_TARGETS+=("${2:-}"); shift ;;
    -h|--help)       sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

MIN_AGE_HOURS="${MIN_AGE_ARG:-${TEMP_CLEAN_MIN_AGE_HOURS:-24}}"
AGENT_DAYS="${TEMP_CLEAN_AGENT_SCRATCH_DAYS:-3}"
NPX_DAYS="${TEMP_CLEAN_NPX_DAYS:-14}"
KEEP="${TEMP_CLEAN_KEEP_PATTERNS:-}"
EXTRA_AGENT_DIRS="${ANALYZERS_AGENT_DIRS:-}"
for n in "$MIN_AGE_HOURS" "$AGENT_DAYS" "$NPX_DAYS"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "Ages must be whole numbers (got '$n')" >&2; exit 2; }
done
if [[ -n "${ONLY_PATHS}" && ! -f "${ONLY_PATHS}" ]]; then
  echo "--only-paths file not found: ${ONLY_PATHS}" >&2
  exit 2
fi
for t in ${EJECT_TARGETS[@]+"${EJECT_TARGETS[@]}"}; do
  [[ -n "$t" ]] || { echo "--eject needs a mount point" >&2; exit 2; }
done

GROUP_MIN=5        # this many siblings of one family collapse into one row
SMALL_KB=1024      # loose files under 1 MB group as "(small files)"

# ---------- interactive menu (double-click / bare terminal run) ----------
INTERACTIVE=0
FOLLOW_UP=""
if [[ -z "$ORIG_ARGS" ]] && { [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; }; then
  INTERACTIVE=1
  echo ""
  echo "  temp-clean — /tmp, /var and AI-agent leftovers, reviewed"
  echo "  ---------------------------------------------------------"
  echo "  1) Audit only (change nothing)"
  echo "  2) Audit, then move what's ready to the Trash (recoverable)"
  echo "  3) Audit, then delete what's ready permanently (frees space now)"
  echo "  q) Quit"
  echo ""
  read -rp "  Choose [1]: " choice
  case "${choice:-1}" in
    1) ;;
    2) FOLLOW_UP="--apply" ;;
    3) FOLLOW_UP="--apply --permanent"; PERMANENT=1 ;;
    q|Q) exit 0 ;;
    *) echo "  Unknown choice '${choice}' — exiting."; exit 2 ;;
  esac
fi

mkdir -p "$LOG_DIR"
# Single instance, like every other cleaner: two runs racing over the same
# Trash destinations is how a receipt ends up pointing at the wrong file.
if [[ -e "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
  echo "temp-clean already running (pid $(cat "$LOCK_FILE")); exiting." >&2
  exit 0
fi
echo "$$" > "$LOCK_FILE"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/temp-clean.XXXXXX")"
trap 'rm -f "$LOCK_FILE"; rm -rf "$WORK"' EXIT
WORK_N="$(cd "$WORK" && pwd -P)"

log() { echo "$*" | tee -a "$LOG_FILE"; }

human() {
  awk -v k="${1:-0}" 'BEGIN {
    if (k >= 1048576)    printf "%.1f GB", k / 1048576
    else if (k >= 1024)  printf "%.1f MB", k / 1024
    else                 printf "%d KB", k
  }'
}

# /tmp and /var are symlinks into /private — one spelling everywhere, so the
# paths the app sends back match the paths this run derives.
norm() {
  local p="${1%/}"
  case "$p" in
    /tmp|/tmp/*) p="/private${p}" ;;
    /var|/var/*) p="/private${p}" ;;
  esac
  printf '%s' "$p"
}

ME="$(id -un)"
MY_UID="$(id -u)"
NOW="$(date +%s)"
TMP_ROOT="/private/tmp"
USER_T="$(norm "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)")"
USER_C="$(norm "$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)")"
USER_X="${USER_T%/T}/X"
VAR_TMP="/private/var/tmp"
CLAUDE_TMP="$(norm "${CLAUDE_CODE_TMPDIR:-/private/tmp}")/claude-${MY_UID}"
CLAUDE_HOME="${HOME}/.claude"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CLAUDE_APP_DIR="${HOME}/Library/Application Support/Claude"
CODEX_SPARKLE="${HOME}/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle"
NPX_DIR="${HOME}/.npm/_npx"

keep_match() {
  local name="$1" pat
  [[ -z "${KEEP}" ]] && return 1
  local IFS=':'
  for pat in ${KEEP}; do
    # shellcheck disable=SC2053
    [[ "${name}" == ${pat} ]] && return 0
  done
  return 1
}

# --only-paths <file>: act ONLY on paths (or family tokens) listed in the file.
# Everything is still derived from scratch — the approved set can only ever
# SHRINK what gets touched, never add to it.
approved() {
  [[ -z "${ONLY_PATHS}" ]] && return 0
  grep -qxF -- "$1" "${ONLY_PATHS}" && return 0
  [[ -n "${2:-}" ]] && grep -qxF -- "$2" "${ONLY_PATHS}" && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Facts, gathered once
# ---------------------------------------------------------------------------

# Disk images: "mountpoint<TAB>image<TAB>kb" for every attached image.
hdiutil info 2>/dev/null | awk '
  /^image-path/ { img = substr($0, index($0, ":") + 2) }
  /^\/dev\/disk/ { print $1 "\t" img }' > "$WORK/devimg.tsv"
mount | awk '/^\/dev\/disk/ {
  i = index($0, " on "); rest = substr($0, i + 4); j = index(rest, " (")
  print $1 "\t" substr(rest, 1, j - 1) }' > "$WORK/mounts.raw"
: > "$WORK/mounts.tsv"
while IFS=$'\t' read -r dev mp; do
  img="$(awk -F'\t' -v d="$dev" '$1 == d { print $2; exit }' "$WORK/devimg.tsv")"
  [[ -z "$img" ]] && continue
  kb="$(df -k "$mp" 2>/dev/null | awk 'NR == 2 { print $3 }')"
  printf '%s\t%s\t%s\n' "$(norm "$mp")" "$(norm "$img")" "${kb:-0}" >> "$WORK/mounts.tsv"
done < "$WORK/mounts.raw"

MP=(); MIMG=(); MKB=()
while IFS=$'\t' read -r mp img kb; do
  MP+=("$mp"); MIMG+=("$img"); MKB+=("$kb")
done < "$WORK/mounts.tsv"

under_temp() {
  case "$1" in
    "$TMP_ROOT"/*|"$USER_T"/*|"$VAR_TMP"/*|"$CLAUDE_TMP"/*) return 0 ;;
  esac
  return 1
}

# Open files (only your own processes are visible without sudo — which is
# exactly the set this tool may touch).
lsof -n -P -w -F pcn 2>/dev/null | awk '
  /^p/ { pid = substr($0, 2) }
  /^c/ { cmd = substr($0, 2) }
  /^n\// {
    n = substr($0, 2)
    if (n ~ /^\/tmp\//) n = "/private" n
    else if (n ~ /^\/var\//) n = "/private" n
    print n "\t" cmd " (pid " pid ")"
  }' | sort -u > "$WORK/open.tsv"

ps -axo pid=,args= 2>/dev/null > "$WORK/ps.txt"
# Running apps by BUNDLE ID, not by app name: Codex ships inside other apps
# (com.openai.codex is the ChatGPT app on current builds), so a path guess
# would miss it and offer its live temp files.
app_running() { [[ -n "$(lsappinfo find bundleid="$1" 2>/dev/null)" ]]; }
CODEX_RUNNING=0;  app_running com.openai.codex && CODEX_RUNNING=1
CLAUDE_RUNNING=0; app_running com.anthropic.claudefordesktop && CLAUDE_RUNNING=1

# Live Claude Code sessions: one registry file per RUNNING session.
: > "$WORK/live-ids.txt"
for f in "$CLAUDE_HOME"/sessions/*.json; do
  pid="$(basename "$f" .json)"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || continue
  # the registry file has no trailing newline — add one, or read(1) drops it
  { sed -n 's/.*"sessionId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f"; echo; } >> "$WORK/live-ids.txt"
done
CLAUDE_LIVE="$(awk 'NF' "$WORK/live-ids.txt" | wc -l | tr -d ' ')"

CLEANUP_DAYS="$(sed -n 's/.*"cleanupPeriodDays"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
  "$CLAUDE_HOME/settings.json" 2>/dev/null | head -1)"
CLEANUP_DAYS="${CLEANUP_DAYS:-30}"

# ---------------------------------------------------------------------------
# Scan: every candidate becomes one row in rows.tsv
#   section  parent  path  status  kb  family  reason
# ---------------------------------------------------------------------------
: > "$WORK/rows.tsv"
# Empty fields would collapse under IFS=tab on read-back — reason defaults to "-".
row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "${7:--}" >> "$WORK/rows.tsv"; }

size_kb() { du -xsk "$1" 2>/dev/null | awk '{ print $1; exit }'; }

# report_row SECTION STATUS PATH REASON — a sized line that is never acted on
report_row() {
  [[ -e "$3" ]] || return 0
  local kb; kb="$(size_kb "$3")"
  [[ "${kb:-0}" -eq 0 ]] && return 0
  row "$1" "$(dirname "$3")" "$3" "$2" "${kb:-0}" "$(basename "$3")" "$4"
}

# scan_dir SECTION PARENT MINUTES RULE [NAME_GLOB]
#   Classifies each direct child of PARENT. RULE adds a tool-specific gate:
#   systemp | claude | codexapp | codextmp | claudeapp | versions | npx
scan_dir() {
  local sec="$1" parent="$2" minutes="$3" rule="$4" glob="${5:-}"
  [[ -d "$parent" ]] || return 0
  local pdev; pdev="$(stat -f '%d' "$parent" 2>/dev/null)"
  local -a nameargs=()
  [[ -n "$glob" ]] && nameargs=(-name "$glob")

  # One stat pass (owner, type, device), one du pass, one recency walk, one
  # join — no per-entry process spawns, because a busy temp folder holds
  # thousands of entries.
  find "$parent" -mindepth 1 -maxdepth 1 ${nameargs[@]+"${nameargs[@]}"} -print0 2>/dev/null > "$WORK/list0"
  [[ -s "$WORK/list0" ]] || return 0
  xargs -0 stat -f "%Su%t%HT%t%d%t%N" < "$WORK/list0" 2>/dev/null > "$WORK/st.tsv"
  # du only what lives on this disk — never into a mounted image
  awk -F'\t' -v d="$pdev" '$3 == d { print $4 }' "$WORK/st.tsv" | tr '\n' '\0' \
    | xargs -0 du -xsk 2>/dev/null > "$WORK/du.tsv"
  : > "$WORK/recent.txt"
  if [[ "$minutes" -gt 0 ]]; then                 # 0 = no recency gate (--min-age-hours 0)
    xargs -0 -J % find % -xdev \( -mmin -"$minutes" -o -cmin -"$minutes" \) < "$WORK/list0" 2>/dev/null \
      | awk -v p="$parent/" 'index($0, p) == 1 { r = substr($0, length(p) + 1); sub(/\/.*/, "", r); print r }' \
      | sort -u > "$WORK/recent.txt"
  fi
  # diskimages-helper holding a file open only means an image is mounted from
  # it — that is handled by ejecting, so it does not count as "in use" here.
  awk -F'\t' -v p="$parent/" 'index($1, p) == 1 && $2 !~ /^diskimages/ {
      r = substr($1, length(p) + 1); sub(/\/.*/, "", r)
      if (!(r in seen)) { seen[r] = $2; order[++n] = r }
    } END { for (i = 1; i <= n; i++) print order[i] "\t" seen[order[i]] }' \
    "$WORK/open.tsv" > "$WORK/openby.tsv"
  : > "$WORK/empty"
  awk -F'\t' -v OFS='\t' -v pd="$pdev" -v pre="$parent/" -v small="$SMALL_KB" -v stem="${glob%\*}" '
    # name family: random suffixes stripped so 900 siblings read as one row
    function fam(n, type, kb,   f, i, sfx) {
      # a glob-scoped scan (one tool only) keeps its own small-files token
      if (type != "Directory" && kb + 0 < small) return stem "(small files)"
      if (n ~ /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) return "(uuid-named)"
      if (n ~ /^\.?tmp[A-Za-z0-9_]{6,}$/) return (substr(n, 1, 1) == ".") ? ".tmp" : "tmp"
      # strip random-looking suffixes only (a digit, or mixed case) — never
      # real words, so "playwright_chromiumdev_profile-aXpfno" stays itself
      f = n
      for (i = 0; i < 1; i++) {
        if (!(match(f, /[._-][A-Za-z0-9]{6,}$/) && RSTART > 1)) break
        sfx = substr(f, RSTART + 1)
        if (sfx !~ /[0-9]/ && !(sfx ~ /[a-z]/ && sfx ~ /[A-Z]/)) break
        f = substr(f, 1, RSTART - 1)
      }
      if (match(f, /[0-9]+$/) && RSTART > 1) f = substr(f, 1, RSTART - 1)
      sub(/[._-]$/, "", f)
      return (f == "") ? n : f
    }
    FILENAME == ARGV[1] { kb[$2] = $1; next }
    FILENAME == ARGV[2] { rec[$1] = 1; next }
    FILENAME == ARGV[3] { ob[$1] = $2; next }
    FILENAME == ARGV[4] { next }
    {
      if ($3 != pd) next                      # a mounted image — own section
      name = substr($4, length(pre) + 1)
      k = ($4 in kb) ? kb[$4] : 0
      print $1, $2, $4, name, k, ((name in rec) ? 1 : 0), fam(name, $2, k), ((name in ob) ? ob[name] : "-")
    }' "$WORK/du.tsv" "$WORK/recent.txt" "$WORK/openby.tsv" "$WORK/empty" "$WORK/st.tsv" \
    > "$WORK/joined.tsv"

  local newest=""
  if [[ "$rule" == "versions" ]]; then
    newest="$(find "$parent" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      | sed 's|.*/||' | sort -V 2>/dev/null | tail -1)"
  fi

  local owner type path name kb recent openby status reason fam
  while IFS=$'\t' read -r owner type path name kb recent fam openby; do
    # empty entries and near-empty folders: nothing to gain, only noise
    [[ "$kb" -eq 0 ]] && continue
    [[ "$type" == "Directory" && "$kb" -lt 16 ]] && continue
    [[ "$path" == "$WORK_N" ]] && continue
    [[ "$rule" == "claudefiles" && "$type" == "Directory" ]] && continue
    [[ "$rule" == "systemp" ]] && is_agent_entry "$parent" "$name" && continue
    status="DRY"; reason=""
    case "$name" in
      .X11-unix|.ICE-unix|.font-unix|.XIM-unix|.X*-lock|quota.user|quota.group|\
      com.apple.*|.vfs_rsrc_streams_*|powerlog|TemporaryItems|\
      *.lock|*.lck|*-lock|*Lock|*Locks|.DS_Store)
        status="SYSTEM"; reason="system or lock entry — left for its owner" ;;
    esac
    if [[ "$status" != "DRY" ]]; then
      :
    elif [[ "$owner" != "$ME" ]]; then
      status="NOT YOURS"; reason="owned by ${owner}"
    elif keep_match "$name"; then
      status="KEEP"; reason="matches your keep list"
    elif [[ "$rule" == claude* ]] && name_has_live_id "$name"; then
      status="PROTECTED"; reason="live Claude Code session"
    elif [[ "$rule" == "codexapp" && "$CODEX_RUNNING" -eq 1 ]]; then
      status="PROTECTED"; reason="the Codex app is running — quit it to clear these"
    elif [[ "$rule" == "claudeapp" && "$CLAUDE_RUNNING" -eq 1 ]]; then
      status="PROTECTED"; reason="Claude is running — quit it to clear its caches"
    elif [[ "$rule" == "codextmp" && "$type" != "Directory" ]]; then
      status="KEPT"; reason="Codex state marker — left alone"
    elif [[ "$rule" == "versions" && "$type" != "Directory" ]]; then
      status="KEPT"; reason="version marker — left alone"
    elif [[ "$rule" == "versions" && "$name" == "$newest" ]]; then
      status="KEPT"; reason="current version"
    elif [[ "$openby" != "-" ]]; then
      status="IN USE"; reason="open by ${openby}"
    elif [[ "$rule" == "npx" ]] && npx_in_use "$name"; then
      status="IN USE"; reason="a running MCP server or tool uses it"
    elif [[ "$recent" == "1" ]]; then
      status="RECENT"; reason="changed in the last $(age_words "$minutes")"
    fi
    # npx caches are hash-named — say which tool each one is
    if [[ "$rule" == "npx" ]]; then
      local pkg
      pkg="$(plutil -extract dependencies json -o - "$path/package.json" 2>/dev/null \
        | tr ',' '\n' | sed -n 's/^[{]*"\([^"]*\)".*/\1/p' | sed 's|\\/|/|g' | paste -sd ',' - | sed 's/,/, /g')"
      [[ -n "$pkg" ]] && reason="${reason:+$reason · }${pkg}"
    fi
    row "$sec" "$parent" "$path" "$status" "$kb" "$fam" "$reason"
  done < "$WORK/joined.tsv"
}

npx_in_use() {
  local line
  while IFS= read -r line; do
    [[ "$line" == *"_npx/$1/"* ]] && return 0
  done < "$WORK/ps.txt"
  return 1
}

name_has_live_id() {
  local id
  while IFS= read -r id; do
    [[ -n "$id" && "$1" == *"$id"* ]] && return 0
  done < "$WORK/live-ids.txt"
  return 1
}

age_words() {
  local m="$1"
  if (( m >= 2880 )); then echo "$(( m / 1440 )) days"
  elif (( m >= 60 )); then echo "$(( m / 60 ))h"
  else echo "${m} min"; fi
}

# Agent-owned entries inside the shared temp roots move to their tool's section.
is_agent_entry() {
  local parent="$1" name="$2"
  case "$parent/$name" in
    "$CLAUDE_TMP"|"$TMP_ROOT"/claude-*|"$TMP_ROOT"/codex*) return 0 ;;
    "$USER_T"/.com.openai.codex.*|"$USER_T"/com.openai.codex*|"$USER_T"/codex*) return 0 ;;
  esac
  return 1
}

TEMP_MIN=$(( MIN_AGE_HOURS * 60 ))
AGENT_MIN=$(( AGENT_DAYS * 1440 ))
NPX_MIN=$(( NPX_DAYS * 1440 ))

# --- system temp ---
scan_dir tmp      "$TMP_ROOT" "$TEMP_MIN" systemp
scan_dir usertemp "$USER_T"   "$TEMP_MIN" systemp
scan_dir vartmp   "$VAR_TMP"  "$TEMP_MIN" systemp

# --- Claude Code ---
if [[ -d "$CLAUDE_TMP" ]]; then
  for proj in "$CLAUDE_TMP"/*/; do
    scan_dir claude "${proj%/}" "$AGENT_MIN" claude
  done
  scan_dir claude "$CLAUDE_TMP" "$AGENT_MIN" claudefiles
fi
for b in "$TMP_ROOT"/claude-mcp-browser-bridge-*; do
  report_row claude KEPT "$b" "Claude in Chrome bridge — left alone"
done
if [[ -d "$CLAUDE_HOME" ]]; then
  report_row claude HISTORY "$CLAUDE_HOME/projects" \
    "session transcripts — Claude Code deletes them after ${CLEANUP_DAYS} days (cleanupPeriodDays); auto-memory is never deleted"
  for d in file-history tasks plans debug paste-cache session-env shell-snapshots backups usage-data uploads image-cache; do
    report_row claude MANAGED "$CLAUDE_HOME/$d" "Claude Code prunes this itself after ${CLEANUP_DAYS} days"
  done
fi

# --- Codex ---
scan_dir codex "$USER_T"   "$TEMP_MIN"  codexapp '.com.openai.codex.*'
scan_dir codex "$USER_T"   "$TEMP_MIN"  codexapp 'com.openai.codex*'
scan_dir codex "$TMP_ROOT" "$TEMP_MIN"  systemp-agent 'codex*'
scan_dir codex "$USER_T"   "$TEMP_MIN"  systemp-agent 'codex*'
scan_dir codex "$CODEX_HOME_DIR/.tmp" "$AGENT_MIN" codextmp
for d in Installation PersistentDownloads; do
  scan_dir codex "$CODEX_SPARKLE/$d" "$AGENT_MIN" codexapp
done
if [[ -d "$CODEX_HOME_DIR" ]]; then
  report_row codex HISTORY "$CODEX_HOME_DIR/sessions" \
    "conversation history — Codex keeps it until you delete threads (codex delete); removing files directly can orphan threads"
  report_row codex HISTORY "$CODEX_HOME_DIR/archived_sessions" "archived conversations — same rule as sessions"
  for f in "$CODEX_HOME_DIR"/logs_*.sqlite; do
    report_row codex MANAGED "$f" "log database — Codex trims it itself"
  done
fi

# --- Claude app ---
if [[ -d "$CLAUDE_APP_DIR" ]]; then
  for d in "Cache" "Code Cache" "GPUCache" "DawnGraphiteCache" "DawnWebGPUCache"; do
    scan_dir claudeapp "$CLAUDE_APP_DIR" "$TEMP_MIN" claudeapp "$d"
  done
  scan_dir claudeapp "$CLAUDE_APP_DIR/claude-code" "$AGENT_MIN" versions
  scan_dir claudeapp "$CLAUDE_APP_DIR/claude-code-vm" "$AGENT_MIN" versions
  report_row claudeapp KEPT "$CLAUDE_APP_DIR/vm_bundles" \
    "Cowork's virtual machine and its saved sessions — not touched"
  report_row claudeapp HISTORY "$CLAUDE_APP_DIR/local-agent-mode-sessions" "agent-mode sessions"
  report_row claudeapp HISTORY "$CLAUDE_APP_DIR/claude-code-sessions" "Code-tab sessions"
fi

# --- npx-launched tools (MCP servers) ---
scan_dir npx "$NPX_DIR" "$NPX_MIN" npx

# --- other agents (sized only) ---
for spec in ".gemini|Gemini CLI / Antigravity — keeps chats per its own general.sessionRetention" \
            ".copilot|GitHub Copilot CLI" ".cursor|Cursor" ".continue|Continue" \
            ".opencode|OpenCode" ".local/share/opencode|OpenCode data" \
            ".local/share/goose|Goose" ".local/share/amp|Amp"; do
  report_row others KEPT "$HOME/${spec%%|*}" "${spec#*|} — sized only"
done
if [[ -n "$EXTRA_AGENT_DIRS" ]]; then
  IFS=':' read -r -a EXTRA <<< "$EXTRA_AGENT_DIRS"
  for d in ${EXTRA[@]+"${EXTRA[@]}"}; do
    d="${d/#\~/$HOME}"
    report_row others KEPT "$d" "from your config (ANALYZERS_AGENT_DIRS) — sized only"
  done
fi

# --- macOS-managed (sized only) ---
report_row managed MANAGED "$USER_X" "code-signing clones — macOS keeps copies of running apps here and prunes them itself"
report_row managed MANAGED "$USER_C" "per-app caches — each app manages its own; clear one from that app"
report_row managed MANAGED "/private/var/log" "system logs — rotated by macOS"
report_row managed MANAGED "/private/var/db/diagnostics" "unified logs — macOS ages them out by size and date"
report_row managed MANAGED "/private/var/db/uuidtext" "symbol data for unified logs — pruned with them"
report_row managed MANAGED "/private/var/vm" "swap and sleep image — shrinks after a restart"

# ---------------------------------------------------------------------------
# Disk-image helpers
# ---------------------------------------------------------------------------

# mounts_backed_by PATH — indices of images whose file lives in PATH, or whose
# mount point sits inside it, plus (transitively) images whose file lives
# inside one of THOSE mounts. One per line.
mount_closure() {
  local -a cl=("$@")
  local changed=1 i j inset
  while [[ "$changed" -eq 1 ]]; do
    changed=0
    for (( i = 0; i < ${#MP[@]}; i++ )); do
      inset=0
      for j in "${cl[@]}"; do [[ "$j" == "$i" ]] && inset=1; done
      [[ "$inset" -eq 1 ]] && continue
      for j in "${cl[@]}"; do
        if [[ "${MIMG[$i]}" == "${MP[$j]}"/* ]]; then cl+=("$i"); changed=1; break; fi
      done
    done
  done
  for j in "${cl[@]}"; do echo "$j"; done
}

mounts_backed_by() {
  local p="$1" i
  local -a seed=()
  for (( i = 0; i < ${#MP[@]}; i++ )); do
    if [[ "${MIMG[$i]}" == "$p" || "${MIMG[$i]}" == "$p"/* || "${MP[$i]}" == "$p"/* ]]; then
      seed+=("$i")
    fi
  done
  [[ ${#seed[@]} -eq 0 ]] && return 0
  mount_closure "${seed[@]}"
}

# eject_set IDX... — detach deepest-first (an image whose file lives inside
# another image must go first). Never forced. Prints failures; returns 1 on any.
eject_set() {
  local -a left=("$@")
  local progress=1 rc=0 i j blocked k
  while [[ ${#left[@]} -gt 0 && "$progress" -eq 1 ]]; do
    progress=0
    local -a next=()
    for i in "${left[@]}"; do
      blocked=0
      for j in "${left[@]}"; do
        [[ "$j" == "$i" ]] && continue
        [[ "${MIMG[$j]}" == "${MP[$i]}"/* ]] && blocked=1
      done
      if [[ "$blocked" -eq 1 ]]; then next+=("$i"); continue; fi
      if hdiutil detach "${MP[$i]}" -quiet 2>/dev/null; then
        log "  [EJECTED] $(human "${MKB[$i]}")  ${MP[$i]}  <-  ${MIMG[$i]}"
      else
        log "  [EJECT FAILED] $(human "${MKB[$i]}")  ${MP[$i]}  <-  ${MIMG[$i]}"
        log "    ↳ still in use — close whatever is reading from it, then eject"
        rc=1
      fi
      progress=1
    done
    left=(${next[@]+"${next[@]}"})
  done
  for k in ${left[@]+"${left[@]}"}; do rc=1; done
  return "$rc"
}

# ---------------------------------------------------------------------------
# Acting
# ---------------------------------------------------------------------------

ALLOWED_PARENTS="$TMP_ROOT
$USER_T
$VAR_TMP
$CLAUDE_TMP
$CODEX_HOME_DIR/.tmp
$CODEX_SPARKLE/Installation
$CODEX_SPARKLE/PersistentDownloads
$CLAUDE_APP_DIR
$CLAUDE_APP_DIR/claude-code
$CLAUDE_APP_DIR/claude-code-vm
$NPX_DIR"

# Last line of defense before anything moves: a direct child of a parent this
# run scanned, yours, not a mount point, never a bare root.
safe_target() {
  local p="$1" parent ok=0 a
  [[ "$p" == /* && "$p" != *"/../"* && "$p" != *"/.." ]] || return 1
  parent="$(dirname "$p")"
  # Claude Code scratch is one level deeper: <claude tmp>/<project>/<session>
  [[ "$(dirname "$parent")" == "$CLAUDE_TMP" ]] && parent="$CLAUDE_TMP"
  while IFS= read -r a; do [[ -n "$a" && "$parent" == "$a" ]] && ok=1; done <<< "$ALLOWED_PARENTS"
  [[ "$ok" -eq 1 ]] || return 1
  # the Claude app folder holds logins and settings too — only its caches qualify
  if [[ "$parent" == "$CLAUDE_APP_DIR" ]]; then
    case "${p##*/}" in
      "Cache"|"Code Cache"|"GPUCache"|"DawnGraphiteCache"|"DawnWebGPUCache") ;;
      *) return 1 ;;
    esac
  fi
  [[ -e "$p" || -L "$p" ]] || return 1
  [[ "$(stat -f '%Su' "$p" 2>/dev/null)" == "$ME" ]] || return 1
  [[ -L "$p" ]] || [[ "$(stat -f '%d' "$p")" == "$(stat -f '%d' "$(dirname "$p")")" ]] || return 1
  return 0
}

# Every mount point on the system (not just disk images): moving or deleting
# a folder with ANY filesystem mounted inside it would reach into that
# filesystem — a network share, another disk. Refreshed after each eject.
refresh_all_mounts() {
  ALLMP=()
  local m
  while IFS= read -r m; do ALLMP+=("$(norm "$m")"); done < <(mount | awk '{
    i = index($0, " on "); rest = substr($0, i + 4); j = index(rest, " (")
    print substr(rest, 1, j - 1) }')
}
has_nested_mount() {
  local m
  for m in ${ALLMP[@]+"${ALLMP[@]}"}; do [[ "$m" == "$1"/* ]] && return 0; done
  return 1
}
refresh_all_mounts

ACTED_KB=0
ACTED_N=0

trash_dest() {
  local name="$1" dest="${HOME}/.Trash/$1" stamp n=1
  if [[ -e "$dest" || -L "$dest" ]]; then
    stamp="$(date +%s)"
    dest="${HOME}/.Trash/${stamp}-${name}"
    # Same name again within the same second: keep counting until the name
    # is free. A move must never land on — and replace — something that is
    # already in the Trash.
    while [[ -e "$dest" || -L "$dest" ]]; do
      n=$((n + 1))
      dest="${HOME}/.Trash/${stamp}-${n}-${name}"
    done
  fi
  printf '%s' "$dest"
}

# act_members TOKEN_OR_PATH KB COUNT MEMBER... — receipts written the moment
# each move lands, so a crash mid-run never loses the way back.
act_members() {
  local label="$1" kb="$2" count="$3"; shift 3
  local -a members=("$@")
  local p i rc ok=0 failed=0 dest folder

  # eject anything these members back, deepest first
  local -a idx=()
  for p in "${members[@]}"; do
    while IFS= read -r i; do [[ -n "$i" ]] && idx+=("$i"); done < <(mounts_backed_by "$p")
  done
  if [[ ${#idx[@]} -gt 0 ]]; then
    local -a uniq=()
    while IFS= read -r i; do uniq+=("$i"); done < <(printf '%s\n' "${idx[@]}" | sort -un)
    if ! eject_set "${uniq[@]}"; then
      refresh_all_mounts
      log "  [FAILED] $(human "$kb")  ${label}"
      log "    ↳ left alone — a disk image it holds could not be ejected"
      return 0
    fi
    refresh_all_mounts
  fi
  # anything still mounted inside a member (a share, another disk): refuse
  # the whole row rather than reach into another filesystem
  for p in "${members[@]}"; do
    if has_nested_mount "$p"; then
      log "  [FAILED] $(human "$kb")  ${label}"
      log "    ↳ left alone — another filesystem is mounted inside ${p}"
      return 0
    fi
  done

  if [[ "$PERMANENT" -eq 1 ]]; then
    for p in "${members[@]}"; do
      if safe_target "$p" && rm -rf -- "$p" 2>/dev/null && [[ ! -e "$p" ]]; then ok=$((ok + 1))
      else failed=$((failed + 1)); fi
    done
    if [[ "$ok" -gt 0 ]]; then
      log "  [DELETED] $(human "$kb")  ${label}"
      [[ "$count" -gt 1 ]] && log "    ↳ ${ok} items"
      ACTED_KB=$((ACTED_KB + kb)); ACTED_N=$((ACTED_N + ok))
    fi
  elif [[ "$count" -gt 1 ]]; then
    folder="$(trash_dest "temp-clean-$(basename "$label" | tr -c 'A-Za-z0-9.\n-' '_' | sed 's/^_*//; s/_*$//')")"
    mkdir -p "$folder" || { log "  [FAILED] $(human "$kb")  ${label}"; log "    ↳ could not create a folder in the Trash"; return 0; }
    for p in "${members[@]}"; do
      if safe_target "$p" && mv -- "$p" "$folder/" 2>/dev/null; then ok=$((ok + 1))
      else failed=$((failed + 1)); fi
    done
    if [[ "$ok" -gt 0 ]]; then
      log "  [TRASHED] $(human "$kb")  ${label}  ->  ${folder}"
      log "    ↳ ${ok} items"
      ACTED_KB=$((ACTED_KB + kb)); ACTED_N=$((ACTED_N + ok))
    else
      rmdir "$folder" 2>/dev/null
    fi
  else
    p="${members[0]}"
    dest="$(trash_dest "$(basename "$p")")"
    if safe_target "$p" && mv -- "$p" "$dest" 2>/dev/null; then
      log "  [TRASHED] $(human "$kb")  ${p}  ->  ${dest}"
      ACTED_KB=$((ACTED_KB + kb)); ACTED_N=$((ACTED_N + 1))
    else
      failed=1
    fi
  fi
  if [[ "$failed" -gt 0 ]]; then
    log "  [FAILED] $(human "$kb")  ${label}"
    log "    ↳ ${failed} item(s) could not be moved — permissions, or it changed mid-run"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

MODE_WORD="DRY RUN"
[[ "$DRY_RUN" -eq 1 && "$PERMANENT" -eq 1 ]] && MODE_WORD="DRY RUN (permanent)"
[[ "$DRY_RUN" -eq 0 ]] && MODE_WORD="APPLY — to Trash"
[[ "$DRY_RUN" -eq 0 && "$PERMANENT" -eq 1 ]] && MODE_WORD="APPLY — permanent"
[[ ${#EJECT_TARGETS[@]} -gt 0 ]] && MODE_WORD="EJECT + ${MODE_WORD}"

log "=================================================================="
log " temp-clean  |  ${MODE_WORD}  |  $(date '+%Y-%m-%d %H:%M:%S')"
log "=================================================================="

sum_kb() { awk -F'\t' -v s="$1" -v st="$2" '($1 ~ s) && ($4 ~ st) { t += $5 } END { print t + 0 }' "$WORK/rows.tsv"; }
count_rows() { awk -F'\t' -v s="$1" -v st="$2" '($1 ~ s) && ($4 ~ st) { n++ } END { print n + 0 }' "$WORK/rows.tsv"; }

TEMP_SEC='^(tmp|usertemp|vartmp)$'
AGENT_SEC='^(claude|codex|claudeapp|npx|others)$'
TEMP_DISK="$(sum_kb "$TEMP_SEC" '.')"
AGENT_DISK="$(sum_kb "$AGENT_SEC" '.')"
READY_KB="$(sum_kb "$TEMP_SEC|$AGENT_SEC" '^DRY$')"
READY_N="$(count_rows "$TEMP_SEC|$AGENT_SEC" '^DRY$')"
IMG_KB=0; for (( i = 0; i < ${#MP[@]}; i++ )); do
  if under_temp "${MP[$i]}" || under_temp "${MIMG[$i]}"; then
    [[ "${MP[$i]}" == /Volumes/* ]] || IMG_KB=$((IMG_KB + MKB[i]))
  fi
done
FREE_KB="$(df -k "$HOME" | awk 'NR == 2 { print $4 }')"

log ""
log "### 1. Overview"
log "  Free space now: $(human "$FREE_KB")"
log "  Temp on disk: $(human "$TEMP_DISK")  |  Inside mounted images: $(human "$IMG_KB")  |  A plain du would show: $(human $((TEMP_DISK + IMG_KB)))"
log "  AI agent folders: $(human "$AGENT_DISK")  |  Live Claude Code sessions: ${CLAUDE_LIVE}  |  Codex running: $([[ $CODEX_RUNNING -eq 1 ]] && echo yes || echo no)  |  Claude app running: $([[ $CLAUDE_RUNNING -eq 1 ]] && echo yes || echo no)"
log "  Ready to clear: $(human "$READY_KB") in ${READY_N} item(s)"
log "  Rules: temp idle ${MIN_AGE_HOURS}h+ · agent scratch idle ${AGENT_DAYS}d+ · npx tools idle ${NPX_DAYS}d+ · never anything open, live, someone else's, or a mounted image you have not approved"
log "  macOS also deletes /tmp files untouched for 3+ days each night (tmp_cleaner) — it skips mounted images and anything still being used"

# ---------- mounted disk images ----------
log ""
log "### 2. Mounted disk images"
if [[ ${#EJECT_TARGETS[@]} -gt 0 ]]; then
  for t in "${EJECT_TARGETS[@]}"; do
    t="$(norm "$t")"; t="${t:-/}"; hit=""
    for (( i = 0; i < ${#MP[@]}; i++ )); do
      if [[ "${MP[$i]}" == "$t" ]] && { under_temp "${MP[$i]}" || under_temp "${MIMG[$i]}"; }; then hit="$i"; fi
    done
    if [[ -z "$hit" ]]; then
      log "  [EJECT FAILED] 0 KB  ${t}  <-  (not a disk image mounted from temp)"
      log "    ↳ refused — only images inside /tmp or your temp folder are ejected here"
      continue
    fi
    closure=(); while IFS= read -r i; do closure+=("$i"); done < <(mount_closure "$hit")
    eject_set "${closure[@]}" || true
  done
fi
MOUNTED_SHOWN=0
for (( i = 0; i < ${#MP[@]}; i++ )); do
  under_temp "${MP[$i]}" || under_temp "${MIMG[$i]}" || continue
  mount | grep -qF " on ${MP[$i]} (" || continue   # ejected above
  log "  [MOUNTED] $(human "${MKB[$i]}")  ${MP[$i]}  <-  ${MIMG[$i]}"
  under_temp "${MIMG[$i]}" && log "    ↳ its image file lives in temp"
  deps=""
  while IFS= read -r j; do
    [[ -n "$j" && "$j" != "$i" ]] && deps="${deps} ${MP[$j]}"
  done < <(mount_closure "$i")
  [[ -n "$deps" ]] && log "    ↳ ejecting it also ejects:${deps}"
  MOUNTED_SHOWN=$((MOUNTED_SHOWN + 1))
done
[[ "$MOUNTED_SHOWN" -eq 0 ]] && log "  (none)"

# ---------- per-section rows ----------
# Collapse families: ≥GROUP_MIN siblings with the same parent+family+status
# become one row whose path is the token "<parent>/<family>*".
emit_section() {
  local sec="$1" title="$2"
  awk -F'\t' -v s="$sec" '$1 == s' "$WORK/rows.tsv" > "$WORK/sec.tsv"
  [[ -s "$WORK/sec.tsv" ]] || { [[ "$sec" =~ ^(tmp|usertemp|vartmp)$ ]] || return 0; }
  log ""
  log "### ${title}"
  if [[ ! -s "$WORK/sec.tsv" ]]; then log "  (nothing here)"; return 0; fi

  awk -F'\t' -v gmin="$GROUP_MIN" '
    { k = $2 "\t" $6 "\t" $4; n[k]++; kb[k] += $5; first[k] = (k in first) ? first[k] : NR; line[NR] = $0; key[NR] = k }
    END {
      for (r = 1; r <= NR; r++) {
        split(line[r], f, "\t"); k = key[r]
        if (n[k] >= gmin) {
          if (done[k]++) continue
          print kb[k] "\t" f[4] "\t" f[2] "/" f[6] "*" "\t" f[7] "\t" n[k] "\t" f[2] "\t" f[6]
        } else {
          print f[5] "\t" f[4] "\t" f[3] "\t" f[7] "\t1\t" f[2] "\t" f[6]
        }
      }
    }' "$WORK/sec.tsv" | sort -t$'\t' -k1,1nr > "$WORK/disp.tsv"

  local kb status path reason count parent fam p
  while IFS=$'\t' read -r kb status path reason count parent fam; do
    if [[ "$status" != "DRY" ]]; then
      log "  [${status}] $(human "$kb")  ${path}"
      [[ "$count" -gt 1 ]] && log "    ↳ ${count} items"
      [[ "$reason" != "-" ]] && log "    ↳ ${reason}"
      continue
    fi
    # members of this display row (path<TAB>kb)
    local -a members=() mkb=()
    local m_path m_kb
    if [[ "$count" -gt 1 ]]; then
      while IFS=$'\t' read -r m_path m_kb; do members+=("$m_path"); mkb+=("$m_kb"); done < <(
        awk -F'\t' -v par="$parent" -v fm="$fam" \
          '$2 == par && $6 == fm && $4 == "DRY" { print $3 "\t" $5 }' "$WORK/sec.tsv")
    else
      members=("$path"); mkb=("$kb")
    fi
    # what ejects first (cheap precheck: most rows back no image at all)
    local -a ej=(); local i names="" hit
    for p in "${members[@]}"; do
      hit=0
      for (( i = 0; i < ${#MP[@]}; i++ )); do
        [[ "${MIMG[$i]}" == "$p" || "${MIMG[$i]}" == "$p"/* || "${MP[$i]}" == "$p"/* ]] && hit=1
      done
      [[ "$hit" -eq 1 ]] || continue
      while IFS= read -r i; do [[ -n "$i" ]] && ej+=("$i"); done < <(mounts_backed_by "$p")
    done
    if [[ ${#ej[@]} -gt 0 ]]; then
      while IFS= read -r i; do names="${names} ${MP[$i]}"; done < <(printf '%s\n' "${ej[@]}" | sort -un)
    fi
    # approval: the whole row if its path/token was approved, otherwise any
    # member whose own path was (a preview may have shown it ungrouped)
    local -a ok=(); local okkb=0 k
    if approved "$path"; then
      ok=("${members[@]}"); okkb="$kb"
    else
      for (( k = 0; k < ${#members[@]}; k++ )); do
        if grep -qxF -- "${members[$k]}" "${ONLY_PATHS}"; then
          ok+=("${members[$k]}"); okkb=$((okkb + mkb[k]))
        fi
      done
    fi
    if [[ ${#ok[@]} -eq 0 ]]; then
      log "  [SKIP] $(human "$kb")  ${path}"
      [[ "$count" -gt 1 ]] && log "    ↳ ${count} items"
      log "    ↳ not in your approved list"
      continue
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [DRY] $(human "$kb")  ${path}"
      [[ "$count" -gt 1 ]] && log "    ↳ ${count} items"
      [[ "$reason" != "-" ]] && log "    ↳ ${reason}"
      [[ -n "$names" ]] && log "    ↳ backs mounted disk images — ejected first:${names}"
    else
      act_members "$path" "$okkb" "${#ok[@]}" "${ok[@]}"
    fi
  done < "$WORK/disp.tsv"
}

emit_section tmp       "3. /tmp"
emit_section usertemp  "4. Your temp folder"
emit_section vartmp    "5. /var/tmp"
emit_section claude    "6. AI agents — Claude Code"
emit_section codex     "7. AI agents — Codex"
emit_section claudeapp "8. AI agents — Claude app"
emit_section npx       "9. AI agents — npx-run tools & MCP servers"
emit_section others    "10. AI agents — other tools"
emit_section managed   "11. Managed by macOS (never touched)"

# ---------- summary ----------
log ""
log "=================================================================="
if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ "$PERMANENT" -eq 1 ]]; then
    log " DRY RUN — would delete ${READY_N} item(s), $(human "$READY_KB"), permanently. Re-run with --apply --permanent."
  else
    log " DRY RUN — would move ${READY_N} item(s), $(human "$READY_KB"), to the Trash. Re-run with --apply."
  fi
elif [[ "$PERMANENT" -eq 1 ]]; then
  log " DONE — deleted ${ACTED_N} item(s), $(human "$ACTED_KB"), permanently."
else
  log " DONE — moved ${ACTED_N} item(s), $(human "$ACTED_KB"), to the Trash (recoverable). The space returns when the Trash is emptied."
fi
[[ "$DRY_RUN" -eq 0 ]] && log " Free space now: $(human "$(df -k "$HOME" | awk 'NR == 2 { print $4 }')")"
log "=================================================================="

if [[ "$INTERACTIVE" -eq 1 ]]; then
  if [[ -n "$FOLLOW_UP" && "$READY_N" -gt 0 ]]; then
    echo ""
    if [[ "$PERMANENT" -eq 1 ]]; then
      read -rp "  PERMANENTLY delete these ${READY_N} item(s), $(human "$READY_KB")? This cannot be undone. [y/N] " yn
    else
      read -rp "  Move these ${READY_N} item(s), $(human "$READY_KB"), to the Trash? [y/N] " yn
    fi
    # shellcheck disable=SC2086
    [[ "$yn" =~ ^[Yy]$ ]] && { rm -f "$LOCK_FILE"; "$0" $FOLLOW_UP; }
  fi
  echo ""
  read -rp "  Done — press Enter to close this window… " _
fi
exit 0
