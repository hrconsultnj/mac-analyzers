#!/usr/bin/env bash
# guard.sh — RAM spike listener for macOS (companion to analyze.sh / auto-clean.sh)
# ---------------------------------------------------------------------------
# Watches kernel memory-pressure and per-process growth so a runaway dev
# process (playwright fleet, leaking node build, forgotten bundler) never
# freezes the machine mid-meeting again.
#
#   * WARNING pressure  → macOS notification naming the top offenders.
#   * CRITICAL pressure → dumps a forensic snapshot to ~/memory-reports/,
#                         then kills the BIGGEST safelisted offender.
#   * Hard cap          → a single safelisted process above --hard-cap-mb
#                         (default 6144) is killed even at normal pressure —
#                         this is the "package/playwright spiked" scenario.
#   * Spike detection   → a safelisted process growing >400 MB per tick is
#                         logged + notified before it becomes a problem.
#
# ONLY dev tooling is ever killed (node/npx/bun/next/vite/playwright/headless
# chromium). Zoom, browsers, VS Code, Docker, Claude sessions, screen
# recording and all system processes are on a hard never-kill list.
#
# Designed to run forever under launchd (KeepAlive). Test with:
#   ./memory-guard.sh --once --verbose
#
# Pause/resume WITHOUT unloading the agent (e.g. during a heavy legit build):
#   touch ~/mac-analyzers/reports/memory/.guard-paused
#   rm    ~/mac-analyzers/reports/memory/.guard-paused
# ---------------------------------------------------------------------------

set -u

HOME_DIR="${HOME}"
LOG_DIR="${HOME_DIR}/mac-analyzers/reports/memory"
LOG_FILE="${LOG_DIR}/guard.log"
STATE_FILE="${LOG_DIR}/.guard-prev-snapshot"
CPU_STATE_FILE="${LOG_DIR}/.guard-cpu-hits"
PAUSE_FLAG="${LOG_DIR}/.guard-paused"

# optional per-machine config (gitignored) — see config.example.sh at repo root
ANALYZERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ANALYZERS_ROOT}/config.local.sh" ]] && source "${ANALYZERS_ROOT}/config.local.sh"

# ---------- tunables (env or flags) ----------
INTERVAL="${GUARD_INTERVAL:-15}"              # seconds between ticks
WARN_COOLDOWN="${GUARD_WARN_COOLDOWN:-300}"   # min seconds between WARNING notifications
KILL_COOLDOWN="${GUARD_KILL_COOLDOWN:-60}"    # min seconds between kills
HARD_CAP_MB="${GUARD_HARD_CAP_MB:-6144}"      # single safelisted proc above this → kill at ANY pressure
SPIKE_MB="${GUARD_SPIKE_MB:-400}"             # growth per tick that flags a runaway…
SPIKE_MIN_MB="${GUARD_SPIKE_MIN_MB:-1024}"    # …once the process is at least this big
CPU_HOG_PCT="${GUARD_CPU_HOG_PCT:-150}"       # %CPU that counts as a hog…
CPU_HOG_TICKS="${GUARD_CPU_HOG_TICKS:-3}"     # …sustained for this many ticks → notify (NEVER kill)

# what the guard is ALLOWED to kill (dev tooling only). Binary names are
# anchored ((^|/)name( |$)) so `bun` can't substring-match "usbaudio.bundle".
KILLABLE_RE='(^|/)(node|npm|npx|bun|tsx|deno)( |$)|next-server|next dev|vite|esbuild|webpack|turbo|tsup|vitest|jest|playwright|headless_shell|--headless|ms-playwright'
# what it must NEVER kill, even if it also matches above (checked second, wins)
PROTECT_RE='.local/bin/claude|Claude.app|Visual Studio Code|Code Helper|zoom.us|ZoomCef|Docker|OrbStack|Opera.app|Google Chrome.app|Safari|WindowServer|loginwindow|mds|Finder|screencapture|screencaptureui|QuickTime|CoreServices|iTerm'
[[ -n "${ANALYZERS_PROTECT_EXTRA:-}" ]] && PROTECT_RE="${PROTECT_RE}|${ANALYZERS_PROTECT_EXTRA}"

ONCE=0
VERBOSE=0
ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)         ONCE=1 ;;
    --verbose)      VERBOSE=1 ;;
    --interval)     INTERVAL="${2:-15}"; shift ;;
    --hard-cap-mb)  HARD_CAP_MB="${2:-6144}"; shift ;;
    -h|--help)      sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$LOG_DIR"

# ---------- interactive control panel (double-click / bare terminal run) ----------
# launchd starts the daemon with no args AND no TTY, so it skips this.
if [[ -z "$ORIG_ARGS" ]] && { [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; }; then
  GUARD_PID="$(cat "${LOG_DIR}/.guard.lock" 2>/dev/null)"
  if [[ -n "$GUARD_PID" ]] && kill -0 "$GUARD_PID" 2>/dev/null; then
    GUARD_STATE="RUNNING (pid ${GUARD_PID})$([[ -e "$PAUSE_FLAG" ]] && echo ' — PAUSED')"
  else
    GUARD_STATE="NOT RUNNING"; GUARD_PID=""
  fi
  echo ""
  echo "  memory-guard — RAM spike listener"
  echo "  ---------------------------------"
  echo "  Background guard: ${GUARD_STATE}"
  echo ""
  echo "  1) Show recent activity (last 20 log lines)"
  echo "  2) Pause guard actions"
  echo "  3) Resume guard actions"
  echo "  4) Single diagnostic tick (verbose; only if guard not running)"
  echo "  q) Quit"
  echo ""
  read -rp "  Choose [1]: " choice
  case "${choice:-1}" in
    1) echo ""; tail -20 "$LOG_FILE" 2>/dev/null || echo "  (no log yet)" ;;
    2) touch "$PAUSE_FLAG"; echo "  paused — guard keeps polling but takes no action." ;;
    3) rm -f "$PAUSE_FLAG"; echo "  resumed." ;;
    4) if [[ -n "$GUARD_PID" ]]; then
         echo "  guard already running (pid ${GUARD_PID}) — pause/uninstall it first."
       else
         ONCE=1; VERBOSE=1
       fi ;;
    q|Q) exit 0 ;;
    *) echo "  Unknown choice '${choice}' — exiting."; exit 2 ;;
  esac
  if [[ "$ONCE" -ne 1 ]]; then
    echo ""
    read -rp "  Done — press Enter to close this window… " _
    exit 0
  fi
fi

# ---------- single-instance lock ----------
LOCK_FILE="${LOG_DIR}/.guard.lock"
if [[ -e "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
  echo "guard already running (pid $(cat "$LOCK_FILE")); exiting." >&2
  exit 0
fi
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE" "$STATE_FILE" "$CPU_STATE_FILE"; exit 0' EXIT INT TERM

# ---------- helpers ----------
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
  [[ "$VERBOSE" -eq 1 ]] && echo "$*"
}

# shared notifier — with alerter installed, clicking the notification opens
# this script's log (see lib/notify.sh); inline fallback keeps it standalone.
if [[ -f "${ANALYZERS_ROOT}/lib/notify.sh" ]]; then
  source "${ANALYZERS_ROOT}/lib/notify.sh"
else
  notify() {  # title, message, [sound]
    command -v osascript >/dev/null 2>&1 || return 0
    osascript -e "display notification \"${2//\"/\'}\" with title \"${1//\"/\'}\" sound name \"${3:-Glass}\"" >/dev/null 2>&1 || true
  }
fi

# short human label for a ps args string
short_name() {
  echo "$1" | awk '{ n=split($1, p, "/"); printf "%s", p[n]; if (NF>1) printf " %s", $2 }' | cut -c1-60
}

# SIGTERM → wait ≤5s → SIGKILL. Args: pid, rss_kb, reason, args
kill_proc() {
  local pid="$1" rsskb="$2" reason="$3" args="$4" name
  name="$(short_name "$args")"
  kill -TERM "$pid" 2>/dev/null || { log "KILL-FAIL pid=$pid already gone"; return 1; }
  local i=0
  while kill -0 "$pid" 2>/dev/null && [[ $i -lt 5 ]]; do sleep 1; i=$((i+1)); done
  kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  LAST_KILL_TS=$(date +%s)
  log "KILLED [$reason] pid=$pid rss=$((rsskb/1024))MB  $args"
  notify "Memory Guard — killed process" "[$reason] ${name} ($((rsskb/1024)) MB) was terminated." "Sosumi"
}

# forensic snapshot for post-mortems ("what actually spiked?")
dump_forensics() {
  local f="${LOG_DIR}/$(date +%Y-%m-%d)/guard-critical-$(date +%H%M%S).log"
  mkdir -p "$(dirname "$f")"
  {
    echo "=== memory guard forensic snapshot: $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "--- pressure ---"
    sysctl kern.memorystatus_vm_pressure_level vm.swapusage 2>/dev/null
    top -l 1 -n 0 2>/dev/null | grep -E "PhysMem|VM:"
    echo "--- top 25 by RSS ---"
    ps axo rss,pid,ppid,etime,args | sort -rn | head -25
  } > "$f"
  log "FORENSICS written: $f"
}

# ---------- main loop ----------
LAST_WARN_TS=0
LAST_KILL_TS=0
log "guard started (pid $$, interval=${INTERVAL}s, hard-cap=${HARD_CAP_MB}MB)"

# rotate log at ~5 MB on startup
if [[ -f "$LOG_FILE" && $(stat -f '%z' "$LOG_FILE" 2>/dev/null || echo 0) -gt 5242880 ]]; then
  mv "$LOG_FILE" "${LOG_FILE}.1"
fi

tick() {
  [[ -e "$PAUSE_FLAG" ]] && return 0
  local now level
  now=$(date +%s)
  level=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)

  # snapshot of KILLABLE-and-not-PROTECTED candidates: pid \t rss_kb \t args
  local snap
  snap=$(ps axo pid=,rss=,args= | awk -v killre="$KILLABLE_RE" -v protre="$PROTECT_RE" -v self="$$" '
    { pid=$1; rss=$2; $1=""; $2=""; sub(/^ +/,"");
      if (pid+0 <= 500 || pid == self) next;
      if ($0 !~ killre) next;
      if ($0 ~ protre) next;
      gsub(/\t/," ");
      printf "%s\t%s\t%.140s\n", pid, rss, $0 }')

  # --- 1. hard cap: single runaway dev process, any pressure level ---
  if [[ -n "$snap" && $((now - LAST_KILL_TS)) -ge "$KILL_COOLDOWN" ]]; then
    local big bpid brss bargs
    big=$(echo "$snap" | sort -t$'\t' -k2 -rn | head -1)
    bpid=$(echo "$big" | cut -f1); brss=$(echo "$big" | cut -f2); bargs=$(echo "$big" | cut -f3)
    if [[ -n "$brss" && "$brss" -gt $((HARD_CAP_MB * 1024)) ]]; then
      dump_forensics
      kill_proc "$bpid" "$brss" "hard-cap ${HARD_CAP_MB}MB" "$bargs"
    fi
  fi

  # --- 2. spike detection vs previous tick ---
  if [[ -f "$STATE_FILE" && -n "$snap" ]]; then
    local spikes
    spikes=$(awk -F'\t' -v growkb=$((SPIKE_MB * 1024)) -v minkb=$((SPIKE_MIN_MB * 1024)) '
      NR==FNR { prev[$1]=$2; next }
      ($1 in prev) && ($2 - prev[$1] > growkb) && ($2 >= minkb) {
        printf "pid=%s +%dMB now %dMB  %s\n", $1, ($2-prev[$1])/1024, $2/1024, $3 }
    ' "$STATE_FILE" <(echo "$snap"))
    if [[ -n "$spikes" ]]; then
      log "SPIKE $spikes"
      if [[ $((now - LAST_WARN_TS)) -ge "$WARN_COOLDOWN" ]]; then
        LAST_WARN_TS=$now
        notify "Memory Guard — process spiking" "$(echo "$spikes" | head -1 | cut -c1-120)" "Glass"
      fi
    fi
  fi
  echo "$snap" > "$STATE_FILE"

  # --- 3. pressure levels ---
  if [[ "$level" -eq 2 ]]; then
    log "PRESSURE warning (level 2)"
    if [[ $((now - LAST_WARN_TS)) -ge "$WARN_COOLDOWN" ]]; then
      LAST_WARN_TS=$now
      local tops
      tops=$(ps axo rss,comm | sort -rn | head -3 | awk '{n=split($2,p,"/"); printf "%s %dMB; ", p[n], $1/1024}')
      notify "Memory Guard — pressure WARNING" "System compressing/swapping. Top: ${tops}" "Glass"
    fi
  elif [[ "$level" -ge 4 ]]; then
    log "PRESSURE CRITICAL (level $level)"
    dump_forensics
    if [[ -n "$snap" && $((now - LAST_KILL_TS)) -ge "$KILL_COOLDOWN" ]]; then
      local big bpid brss bargs
      big=$(echo "$snap" | sort -t$'\t' -k2 -rn | head -1)
      bpid=$(echo "$big" | cut -f1); brss=$(echo "$big" | cut -f2); bargs=$(echo "$big" | cut -f3)
      if [[ -n "$brss" && "$brss" -gt 512000 ]]; then   # only worth killing if >500 MB
        kill_proc "$bpid" "$brss" "pressure-critical" "$bargs"
      else
        notify "Memory Guard — pressure CRITICAL" "No big dev process to kill — close apps manually (see guard-critical log)." "Sosumi"
      fi
    fi
  fi

  # --- 4. sustained CPU hogs (notify-only — CPU is NEVER a kill reason) ---
  local cpu_now
  cpu_now=$(ps axo pid=,pcpu=,args= | awk -v th="$CPU_HOG_PCT" '
    $2+0 >= th && $1+0 > 500 { pid=$1; $1=$2=""; sub(/^ +/,"");
      gsub(/\t/," "); printf "%s\t%.80s\n", pid, $0 }')
  if [[ -n "$cpu_now" ]]; then
    local hits_new alert
    hits_new=$(echo "$cpu_now" | awk -F'\t' -v prevf="$CPU_STATE_FILE" '
      BEGIN { while ((getline line < prevf) > 0) { split(line, a, "\t"); prev[a[1]]=a[2] } }
      { c = ($1 in prev ? prev[$1]+1 : 1); printf "%s\t%d\t%s\n", $1, c, $2 }')
    echo "$hits_new" > "$CPU_STATE_FILE"
    alert=$(echo "$hits_new" | awk -F'\t' -v n="$CPU_HOG_TICKS" '$2==n {printf "pid=%s %s; ", $1, $3}')
    if [[ -n "$alert" ]]; then
      log "CPU-HOG sustained >=${CPU_HOG_PCT}% for ${CPU_HOG_TICKS} ticks: $alert"
      if [[ $((now - LAST_WARN_TS)) -ge "$WARN_COOLDOWN" ]]; then
        LAST_WARN_TS=$now
        notify "Memory Guard — sustained CPU hog" "$(echo "$alert" | cut -c1-120)" "Glass"
      fi
    fi
  else
    : > "$CPU_STATE_FILE"
  fi
}

while :; do
  tick
  [[ "$ONCE" -eq 1 ]] && { log "single tick done (--once)"; exit 0; }
  sleep "$INTERVAL"
done
