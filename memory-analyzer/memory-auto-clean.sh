#!/usr/bin/env bash
# auto-clean.sh — automation-SAFE RAM maintenance (companion to analyze.sh / guard.sh)
# ---------------------------------------------------------------------------
# RAM can't be "cleaned" directly — compressed memory and swap only drain when
# the processes HOLDING them exit. This script reaps processes that are dead
# weight, which is what actually lets the compressor/swap shrink without a
# reboot:
#
#   1. ORPHANED MCP servers — parent Claude/VS Code session died (PPID=1).
#      These are pure leaks; killed under --apply.
#   2. Other orphaned dev tooling (node/playwright reparented to launchd) —
#      REPORT-ONLY by default (some PPID=1 daemons are deliberate);
#      pass --orphans-all to kill those too.
#   3. Dev servers older than --dev-age-hours (default 24) — the forgotten
#      `pnpm dev` / next-server from yesterday. Killed under --apply
#      (regenerable: just run dev again).
#   4. Playwright / headless-Chromium older than 2h — leftover test browsers.
#   5. DUPLICATE MCP sets under LIVE sessions — reported, never killed
#      (each live Claude/VS Code session legitimately owns one set).
#   6. Heavy long-lived VS Code helpers — reported only ("Developer: Reload
#      Window" releases them; killing them under an editor corrupts state).
#
# SAFE BY DEFAULT: dry-run unless --apply. Never touches Zoom, browsers,
# VS Code, Docker, Claude sessions, or anything on the protect list.
#
# Usage:
#   ./memory-auto-clean.sh                          # dry run
#   ./memory-auto-clean.sh --apply                  # act
#   ./memory-auto-clean.sh --apply --orphans-all    # also kill non-MCP orphans
#   ./memory-auto-clean.sh --dev-age-hours 48       # be laxer about dev servers
# ---------------------------------------------------------------------------

set -u

HOME_DIR="${HOME}"
DRY_RUN=1
ORPHANS_ALL=0
DEV_AGE_HOURS=24
PW_AGE_HOURS=2
LOG_DIR="${HOME_DIR}/mac-analyzers/reports/memory"
LOG_FILE="${LOG_DIR}/auto-clean.log"
LOCK_FILE="${LOG_DIR}/.auto-clean.lock"

# optional per-machine config (gitignored) — see config.example.sh at repo root
ANALYZERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ANALYZERS_ROOT}/config.local.sh" ]] && source "${ANALYZERS_ROOT}/config.local.sh"

MCP_RE='[Mm]cp'
[[ -n "${ANALYZERS_MCP_EXTRA_RE:-}" ]] && MCP_RE="${MCP_RE}|${ANALYZERS_MCP_EXTRA_RE}"
DEV_SERVER_RE='next-server|next dev|vite( |$)|pnpm( run)? dev|npm run dev|nodemon|turbo run dev'
PLAYWRIGHT_RE='headless_shell|ms-playwright|--headless'
NODEISH_RE='(^|/)(node|npm|npx|bun|tsx|deno)( |$)'
PROTECT_RE='.local/bin/claude|Claude.app|Visual Studio Code|Code Helper|zoom.us|ZoomCef|Docker|OrbStack|Opera.app|Google Chrome.app|Safari|WindowServer|loginwindow|mds|Finder|screencapture|QuickTime|CoreServices|iTerm'
[[ -n "${ANALYZERS_PROTECT_EXTRA:-}" ]] && PROTECT_RE="${PROTECT_RE}|${ANALYZERS_PROTECT_EXTRA}"

ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)          DRY_RUN=0 ;;
    --dry-run)        DRY_RUN=1 ;;
    --orphans-all)    ORPHANS_ALL=1 ;;
    --dev-age-hours)  DEV_AGE_HOURS="${2:-24}"; shift ;;
    --pw-age-hours)   PW_AGE_HOURS="${2:-2}"; shift ;;
    -h|--help)        sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# ---------- interactive menu (double-click / bare terminal run) ----------
# The 08:30 launchd agent passes --apply (and has no TTY) — it never sees this.
INTERACTIVE=0
INVOKED="flags: ${ORIG_ARGS:-(none — defaults)}"
if [[ -z "$ORIG_ARGS" ]] && { [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; }; then
  INTERACTIVE=1
  echo ""
  echo "  memory-auto-clean — daily RAM reaper"
  echo "  ------------------------------------"
  echo "  1) Preview (dry run)"
  echo "  2) Apply (orphaned MCP servers, dev servers >${DEV_AGE_HOURS}h, stale playwright)"
  echo "  3) Apply + also kill ALL orphaned node tools (--orphans-all)"
  echo "  q) Quit"
  echo ""
  read -rp "  Choose [1]: " choice
  case "${choice:-1}" in
    1) ;;
    2) DRY_RUN=0 ;;
    3) DRY_RUN=0; ORPHANS_ALL=1 ;;
    q|Q) exit 0 ;;
    *) echo "  Unknown choice '${choice}' — exiting."; exit 2 ;;
  esac
  INVOKED="interactive menu: choice ${choice:-1}"
fi

mkdir -p "$LOG_DIR"

# ---------- single-instance lock ----------
if [[ -e "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
  echo "memory auto-clean already running (pid $(cat "$LOCK_FILE")); exiting." >&2
  exit 0
fi
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ---------- helpers ----------
FREED_KB=0
KILL_COUNT=0
TS_NOW="$(date '+%Y-%m-%d %H:%M:%S')"

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

# reap <pid> <rss_kb> <desc> — dry-run-aware kill with accounting
reap() {
  local pid="$1" rsskb="$2" desc="$3"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "  [DRY]     $(printf '%7s' "$((rsskb/1024)) MB")  pid=$pid  $desc"
    FREED_KB=$((FREED_KB + rsskb)); KILL_COUNT=$((KILL_COUNT + 1))
    return 0
  fi
  if ! kill -TERM "$pid" 2>/dev/null; then
    log "  [GONE]    pid=$pid  $desc"; return 0
  fi
  local i=0
  while kill -0 "$pid" 2>/dev/null && [[ $i -lt 5 ]]; do sleep 1; i=$((i+1)); done
  kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  log "  [KILLED]  $(printf '%7s' "$((rsskb/1024)) MB")  pid=$pid  $desc"
  FREED_KB=$((FREED_KB + rsskb)); KILL_COUNT=$((KILL_COUNT + 1))
}

# ps snapshot once: pid \t ppid \t rss \t age_seconds \t args
SNAP="$(ps axo pid=,ppid=,rss=,etime=,args= | awk '
  function etime2s(e,  a,d,hms,n,s) {
    d=0; if (e ~ /-/) { split(e,a,"-"); d=a[1]; e=a[2] }
    n=split(e,hms,":");
    if (n==3) s=hms[1]*3600+hms[2]*60+hms[3];
    else if (n==2) s=hms[1]*60+hms[2];
    else s=hms[1]+0;
    return d*86400+s
  }
  { pid=$1; ppid=$2; rss=$3; et=$4; $1=$2=$3=$4=""; sub(/^ +/,"");
    gsub(/\t/," ");
    printf "%s\t%s\t%s\t%s\t%.140s\n", pid, ppid, rss, etime2s(et), $0 }')"

# candidates <filter_re> <exclude_protect=1> — rows of SNAP matching re
candidates() {
  local re="$1"
  echo "$SNAP" | awk -F'\t' -v re="$re" -v protre="$PROTECT_RE" -v self="$$" '
    $1+0 > 500 && $1 != self && $5 ~ re && $5 !~ protre'
}

before_state() { top -l 1 -n 0 2>/dev/null | grep PhysMem; sysctl -n vm.swapusage; }

# ---------- header ----------
log "=================================================================="
log " memory auto-clean  |  $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY')  |  ${TS_NOW}"
log " dev-age>${DEV_AGE_HOURS}h  pw-age>${PW_AGE_HOURS}h  orphans-all=${ORPHANS_ALL}"
log " input: ${INVOKED}"
log "=================================================================="
BEFORE="$(before_state)"

# ---------- 1. Orphaned MCP servers (PPID=1 — parent session is gone) ----------
group "1. Orphaned MCP servers (parent Claude/VS Code session died)"
FOUND=0
while IFS=$'\t' read -r pid ppid rss age args; do
  [[ -z "${pid:-}" ]] && continue
  [[ "$ppid" -eq 1 ]] || continue
  reap "$pid" "$rss" "orphan-mcp: $args"; FOUND=1
done < <(candidates "$MCP_RE")
[[ "$FOUND" -eq 0 ]] && log "  none found — all MCP servers belong to live sessions."

# ---------- 2. Other orphaned dev tooling ----------
group "2. Other orphaned node/dev processes (PPID=1) — $([[ $ORPHANS_ALL -eq 1 ]] && echo 'KILL mode' || echo 'report-only; --orphans-all to kill')"
FOUND=0
while IFS=$'\t' read -r pid ppid rss age args; do
  [[ -z "${pid:-}" ]] && continue
  [[ "$ppid" -eq 1 ]] || continue
  echo "$args" | grep -qE "$MCP_RE" && continue   # section 1 owns these
  [[ "$age" -lt 1800 ]] && continue                # <30 min old: might be starting up
  if [[ "$ORPHANS_ALL" -eq 1 ]]; then
    reap "$pid" "$rss" "orphan: $args"
  else
    log "  [REPORT]  $(printf '%7s' "$((rss/1024)) MB")  pid=$pid  up $((age/3600))h  $args"
  fi
  FOUND=1
done < <(candidates "$NODEISH_RE")
[[ "$FOUND" -eq 0 ]] && log "  none found."

# ---------- 3. Forgotten dev servers ----------
group "3. Dev servers older than ${DEV_AGE_HOURS}h (regenerable — just run dev again)"
FOUND=0
while IFS=$'\t' read -r pid ppid rss age args; do
  [[ -z "${pid:-}" ]] && continue
  [[ "$age" -ge $((DEV_AGE_HOURS * 3600)) ]] || continue
  reap "$pid" "$rss" "stale-dev ($((age/3600))h): $args"; FOUND=1
done < <(candidates "$DEV_SERVER_RE")
[[ "$FOUND" -eq 0 ]] && log "  none older than ${DEV_AGE_HOURS}h."

# ---------- 4. Leftover playwright / headless chromium ----------
group "4. Playwright / headless-Chromium older than ${PW_AGE_HOURS}h"
FOUND=0
while IFS=$'\t' read -r pid ppid rss age args; do
  [[ -z "${pid:-}" ]] && continue
  if [[ "$ppid" -eq 1 || "$age" -ge $((PW_AGE_HOURS * 3600)) ]]; then
    reap "$pid" "$rss" "stale-playwright ($((age/60))min): $args"; FOUND=1
  fi
done < <(candidates "$PLAYWRIGHT_RE")
[[ "$FOUND" -eq 0 ]] && log "  none found."

# ---------- 5. Duplicate MCP sets under LIVE sessions (informational) ----------
group "5. MCP servers under live sessions (one set per session is NORMAL)"
echo "$SNAP" | awk -F'\t' -v re="$MCP_RE" '
  $5 ~ re && $2 != 1 {
    n=split($5, p, "/"); bin=p[n]; sub(/ .*/, "", bin);
    cnt[bin]++; mem[bin]+=$3
  }
  END {
    if (length(cnt)==0) { print "  none running."; exit }
    for (b in cnt) printf "  %d× %-40s %d MB total\n", cnt[b], b, mem[b]/1024
    print "  (N× here = N live Claude/VS Code sessions, each owning its own set."
    print "   Close idle sessions to release theirs — these are NOT killed.)"
  }' | tee -a "$LOG_FILE"

# ---------- 6. Heavy long-lived VS Code helpers (informational) ----------
group "6. VS Code helpers >250 MB and up >2 days (use 'Developer: Reload Window')"
echo "$SNAP" | awk -F'\t' '
  $5 ~ /Visual Studio Code/ && $3 > 256000 && $4 > 172800 {
    printf "  %d MB  up %dd  pid=%s\n", $3/1024, $4/86400, $1; f=1 }
  END { if (!f) print "  none." }' | tee -a "$LOG_FILE"

# ---------- summary ----------
log ""
log "=================================================================="
if [[ "$DRY_RUN" -eq 1 ]]; then
  log " DRY RUN — would reap ${KILL_COUNT} process(es), ~$((FREED_KB/1024)) MB resident. Re-run with --apply."
  notify "Memory auto-clean (dry run)" "Would reap ${KILL_COUNT} process(es), ~$((FREED_KB/1024)) MB resident."
else
  log " DONE — reaped ${KILL_COUNT} process(es), ~$((FREED_KB/1024)) MB resident."
  log ""
  log " Before: ${BEFORE}"
  sleep 5
  log " After:  $(before_state)"
  log " (compressor + swap held by reaped processes drains over the next minutes)"
  notify "Memory auto-clean" "Reaped ${KILL_COUNT} process(es), ~$((FREED_KB/1024)) MB resident."
fi
log "=================================================================="

# ---------- interactive follow-through ----------
if [[ "$INTERACTIVE" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 && "$KILL_COUNT" -gt 0 ]]; then
    echo ""
    read -rp "  Apply now? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] && "$0" --apply
  fi
  echo ""
  read -rp "  Done — press Enter to close this window… " _
fi
