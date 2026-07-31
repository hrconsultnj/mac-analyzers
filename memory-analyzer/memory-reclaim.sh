#!/usr/bin/env bash
# memory-reclaim.sh — the manual "free my RAM NOW" button (reboot effect, no reboot)
# ---------------------------------------------------------------------------
# A restart clears swap + compressed memory only because it kills every
# process. This does the same thing surgically, so you don't have to reboot:
#
#   * Sweeps ALL dev tooling immediately (no age thresholds, unlike the daily
#     memory-auto-clean.sh): MCP servers, dev servers, playwright / headless
#     Chromium, orphaned node tools.
#   * With --apps, also QUITS heavy GUI apps gracefully via AppleScript (same
#     as ⌘Q — unsaved-work dialogs still appear, nothing is force-killed).
#     Default quit list: Opera, Google Chrome, Visual Studio Code, ChatGPT,
#     Docker. Zoom is NEVER on the list.
#
# After the sweep, compressed memory and swap held by those processes drain
# over the next minutes. Relaunch whatever you need — dev servers restart with
# `pnpm dev`, MCP servers respawn with their next Claude session.
#
# LIVE-SESSION PROTECTION: every open Claude Code session (any terminal) and
# ChatGPT/Codex keeps its MCP servers — the sweep exempts all descendants of
# live session roots, however this script is invoked (terminal, Finder,
# launchd). Close a session and its servers become sweepable dead weight.
#
# SAFE BY DEFAULT: dry-run unless --apply.
#
# Usage:
#   ./memory-reclaim.sh                        # show what would go
#   ./memory-reclaim.sh --apply                # sweep dev processes only
#   ./memory-reclaim.sh --apply --apps         # sweep + quit default heavy apps
#   ./memory-reclaim.sh --apply --apps-list "Opera,Docker"   # custom quit list
# ---------------------------------------------------------------------------

set -u

HOME_DIR="${HOME}"
DRY_RUN=1
QUIT_APPS=0
LOG_DIR="${HOME_DIR}/mac-analyzers/reports/memory"
LOG_FILE="${LOG_DIR}/reclaim.log"

# optional per-machine config (gitignored) — see config.example.sh at repo root
ANALYZERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ANALYZERS_ROOT}/config.local.sh" ]] && source "${ANALYZERS_ROOT}/config.local.sh"

APPS_LIST="${ANALYZERS_RECLAIM_APPS:-Opera,Google Chrome,Visual Studio Code,ChatGPT,Docker}"

SWEEP_RE='[Mm]cp|next-server|next dev|vite( |$)|pnpm( run)? dev|npm run dev|nodemon|turbo run dev|headless_shell|ms-playwright|--headless|(^|/)(node|npm|npx|bun|tsx|deno)( |$)'
[[ -n "${ANALYZERS_MCP_EXTRA_RE:-}" ]] && SWEEP_RE="${SWEEP_RE}|${ANALYZERS_MCP_EXTRA_RE}"
PROTECT_RE='.local/bin/claude|Claude.app|Visual Studio Code|Code Helper|zoom.us|ZoomCef|Docker|OrbStack|Opera.app|Google Chrome.app|Safari|WindowServer|loginwindow|mds|Finder|screencapture|QuickTime|CoreServices|iTerm'
[[ -n "${ANALYZERS_PROTECT_EXTRA:-}" ]] && PROTECT_RE="${PROTECT_RE}|${ANALYZERS_PROTECT_EXTRA}"
# NOTE: VS Code / Docker / browsers are protected from the PROCESS sweep —
# they are only ever closed via the graceful --apps quit below.

ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)      DRY_RUN=0 ;;
    --dry-run)    DRY_RUN=1 ;;
    --apps)       QUIT_APPS=1 ;;
    --apps-list)  QUIT_APPS=1; APPS_LIST="${2:?--apps-list needs a comma-separated list}"; shift ;;
    -h|--help)    sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# ---------- interactive menu (double-click / bare terminal run) ----------
# Agents & launchd pass flags (or have no TTY) and never see this.
INTERACTIVE=0
INVOKED="flags: ${ORIG_ARGS:-(none — defaults)}"
if [[ -z "$ORIG_ARGS" ]] && { [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; }; then
  INTERACTIVE=1
  echo ""
  echo "  memory-reclaim — free RAM now (reboot effect, no reboot)"
  echo "  --------------------------------------------------------"
  echo "  1) Preview (dry run — show what would be closed)"
  echo "  2) Sweep dev processes (dead-session MCP servers, dev servers, playwright)"
  echo "  3) Sweep + gracefully quit heavy apps (Opera, Chrome, VS Code, ChatGPT, Docker)"
  echo "  q) Quit"
  echo ""
  read -rp "  Choose [1]: " choice
  case "${choice:-1}" in
    1) ;;
    2) DRY_RUN=0 ;;
    3) DRY_RUN=0; QUIT_APPS=1 ;;
    q|Q) exit 0 ;;
    *) echo "  Unknown choice '${choice}' — exiting."; exit 2 ;;
  esac
  INVOKED="interactive menu: choice ${choice:-1}"
fi

mkdir -p "$LOG_DIR"

FREED_KB=0
KILL_COUNT=0

log() { echo "$*" | tee -a "$LOG_FILE"; }
group() { log ""; log "### $1"; }

# shared notifier — with alerter installed, clicking the notification opens
# this script's log (see lib/notify.sh); inline fallback keeps it standalone.
if [[ -f "${ANALYZERS_ROOT}/lib/notify.sh" ]]; then
  source "${ANALYZERS_ROOT}/lib/notify.sh"
else
  notify() {
    command -v osascript >/dev/null 2>&1 || return 0
    osascript -e "display notification \"${2//\"/\'}\" with title \"${1//\"/\'}\" sound name \"Glass\"" >/dev/null 2>&1 || true
  }
fi

# ---------- live-session protection ----------
# Exempt every process descending from a LIVE AI coding session, no matter how
# this script was invoked (terminal, Finder double-click, launchd). Session
# roots are found in the process table itself: claude CLI processes (under any
# terminal — iTerm, VS Code, anywhere) and ChatGPT's codex app-server. Killing
# their MCP servers (cortex, context7, shadcn, …) breaks the session's tools
# until restart. Orphaned servers (parent session dead) are NOT exempt.
PIDTABLE="$(ps axo pid=,ppid=)"
# tr: macOS awk errors on literal newlines in -v values — keep this space-separated
SESSION_ROOTS="$(ps axo pid=,args= | awk '
  $0 ~ /awk|grep/ { next }
  /\.local\/bin\/claude|ChatGPT\.app.*codex/ { print $1 }' | tr '\n' ' ')"
EXEMPT="$(
  if [[ -n "${SESSION_ROOTS// /}" ]]; then
    echo "$PIDTABLE" | awk -v roots="$SESSION_ROOTS" '
      BEGIN { n=split(roots, r, /[[:space:]]+/); for (i=1;i<=n;i++) if (r[i]!="") root[r[i]]=1 }
      { pp[$1]=$2 }
      END { for (pid in pp) { q=pid; while (q > 1 && q != "") {
              if (q in root) { print pid; break }; q = pp[q] } }
            for (p in root) print p }'
  fi
  echo "$$"
)"
SESS_COUNT="$(echo "$SESSION_ROOTS" | wc -w | tr -d ' ')"

is_exempt() { echo "$EXEMPT" | grep -qx "$1"; }

reap() {
  local pid="$1" rsskb="$2" desc="$3"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "  [DRY]     $(printf '%7s' "$((rsskb/1024)) MB")  pid=$pid  $desc"
    FREED_KB=$((FREED_KB + rsskb)); KILL_COUNT=$((KILL_COUNT + 1))
    return 0
  fi
  kill -TERM "$pid" 2>/dev/null || { log "  [GONE]    pid=$pid  $desc"; return 0; }
  local i=0
  while kill -0 "$pid" 2>/dev/null && [[ $i -lt 5 ]]; do sleep 1; i=$((i+1)); done
  kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  log "  [KILLED]  $(printf '%7s' "$((rsskb/1024)) MB")  pid=$pid  $desc"
  FREED_KB=$((FREED_KB + rsskb)); KILL_COUNT=$((KILL_COUNT + 1))
}

state() { top -l 1 -n 0 2>/dev/null | grep PhysMem; sysctl -n vm.swapusage; }

# ---------- header ----------
log "=================================================================="
log " memory-reclaim  |  $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY')  |  apps=$([[ $QUIT_APPS -eq 1 ]] && echo "${APPS_LIST}" || echo 'no')  |  $(date '+%Y-%m-%d %H:%M:%S')"
log " input: ${INVOKED}"
[[ "$SESS_COUNT" -gt 0 ]] && log " exempt: ${SESS_COUNT} live Claude/Codex session(s) + their MCP servers (roots: ${SESSION_ROOTS})"
log "=================================================================="
BEFORE="$(state)"

# ---------- 1. quit heavy GUI apps (graceful, optional) ----------
if [[ "$QUIT_APPS" -eq 1 ]]; then
  group "1. Quitting heavy apps (graceful ⌘Q — save dialogs still appear)"
  IFS=',' read -ra APPS <<< "$APPS_LIST"
  for app in "${APPS[@]}"; do
    app="$(echo "$app" | sed 's/^ *//;s/ *$//')"
    # aggregate current footprint for the log
    kb=$(ps axo rss,args | grep -F "/Applications/${app}.app/" | grep -v grep | awk '{s+=$1} END{print s+0}')
    if [[ "$kb" -eq 0 ]]; then log "  [SKIP]    ${app} — not running"; continue; fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [DRY]     $(printf '%7s' "$((kb/1024)) MB")  would quit: ${app}"
    else
      log "  [QUIT]    $(printf '%7s' "$((kb/1024)) MB")  ${app}"
      osascript -e "tell application \"${app}\" to quit" >/dev/null 2>&1 &
    fi
    FREED_KB=$((FREED_KB + kb))
  done
  [[ "$DRY_RUN" -eq 0 ]] && { log "  waiting 15s for apps to exit…"; sleep 15; }
fi

# ---------- 2. sweep dev tooling ----------
group "2. Sweeping dev tooling (MCP servers, dev servers, playwright, node tools)"
FOUND=0
while IFS=$'\t' read -r pid rss args; do
  [[ -z "${pid:-}" ]] && continue
  is_exempt "$pid" && { log "  [EXEMPT]  pid=$pid  $args"; continue; }
  reap "$pid" "$rss" "$args"; FOUND=1
done < <(ps axo pid=,rss=,args= | awk -v re="$SWEEP_RE" -v protre="$PROTECT_RE" '
  { pid=$1; rss=$2; $1=$2=""; sub(/^ +/,"");
    if (pid+0 <= 500) next;
    if ($0 ~ /^(awk|ps|grep|sed) /) next;   # never match our own pipeline helpers
    if ($0 !~ re) next;
    if ($0 ~ protre) next;
    gsub(/\t/," ");
    printf "%s\t%s\t%.120s\n", pid, rss, $0 }')
[[ "$FOUND" -eq 0 ]] && log "  nothing to sweep."

# ---------- summary ----------
log ""
log "=================================================================="
if [[ "$DRY_RUN" -eq 1 ]]; then
  log " DRY RUN — would reclaim ~$((FREED_KB/1024)) MB resident across ${KILL_COUNT} process(es)$([[ $QUIT_APPS -eq 1 ]] && echo ' + app quits'). Re-run with --apply."
  notify "Memory reclaim (dry run)" "Would reclaim ~$((FREED_KB/1024)) MB resident."
else
  log " DONE — reclaimed ~$((FREED_KB/1024)) MB resident."
  log ""
  log " Before: ${BEFORE}"
  sleep 5
  log " After:  $(state)"
  log " (compressed memory + swap drain over the next minutes as macOS rebalances;"
  log "  swapfiles shrink back automatically once their contents are freed)"
  notify "Memory reclaim" "Reclaimed ~$((FREED_KB/1024)) MB resident. Compressed/swap drains over the next minutes."
fi
log "=================================================================="

# ---------- interactive follow-through ----------
if [[ "$INTERACTIVE" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 && "$KILL_COUNT" -gt 0 ]]; then
    echo ""
    read -rp "  Apply now? [y = sweep / a = sweep + quit apps / N = no] " yn
    case "$yn" in
      y|Y) "$0" --apply ;;
      a|A) "$0" --apply --apps ;;
    esac
  fi
  echo ""
  read -rp "  Done — press Enter to close this window… " _
fi
