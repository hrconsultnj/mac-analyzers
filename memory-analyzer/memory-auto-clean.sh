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
#   2. Orphaned dev tooling — a tool tree whose parent is gone (tsc/vitest/
#      esbuild workers, npx/pnpm wrappers, headless test browsers). Reaped
#      once IDLE past its grace; busy ones are reported (some PPID=1
#      processes are deliberate — those that are busy are left alone);
#      --orphans-all kills the busy ones too.
#   3. Dev servers older than --dev-age-hours (default 24) — the forgotten
#      `pnpm dev` / next-server from yesterday. Killed under --apply
#      (regenerable: just run dev again).
#   4. Playwright / headless-Chromium older than 2h — leftover test browsers.
#   5. DUPLICATE MCP sets under LIVE sessions — reported, never killed
#      (each live Claude/VS Code session legitimately owns one set).
#   6. Heavy long-lived VS Code helpers — reported only ("Developer: Reload
#      Window" releases them; killing them under an editor corrupts state).
#   7. Idle emulators & simulators — no build, test, driver (adb, simctl,
#      xcodebuild, expo run, maestro…), Metro activity or window focus for
#      ANALYZERS_DEV_DEVICE_IDLE_MIN. Shut down gracefully (snapshot kept).
#   8. Build daemons with no build running (Gradle, Kotlin) — only while NO
#      Gradle build runs anywhere, so another project's build is never hit.
#   9. Leftovers of finished or failed native builds — Xcode build helpers
#      and emulator plumbing whose parent is gone.
#  10. Idle dev servers (Metro, next, vite, storybook…) — no client connected
#      and no activity: ANALYZERS_DEV_SERVER_IDLE_MIN while their project is
#      open in a session or terminal, ANALYZERS_DEV_ORPHAN_IDLE_MIN once not.
#
# Sections 2 and 7–10 judge what a process is DOING, not who started it:
# a connected client or growing CPU time keeps it (CPU only ever keeps a
# process alive — it is never a kill reason); the first idle sighting is
# remembered in .dev-idle-state and the process goes once idle past its
# grace. Live AI sessions keep their exemption (CONTRIBUTING.md invariant 3).
#
# 11. (opt-in, ANALYZERS_DEV_STOP_IDLE_STACKS=1, --dev only) Docker/Supabase stacks of projects with no
#     live AI session for ANALYZERS_STACK_IDLE_MIN — containers stopped (never removed), unmapped stacks kept.
#
# --dev runs only sections 1, 2 and 7–11 — the fast pass memory-guard.sh runs
# every GUARD_DEV_SWEEP_SECS, and that build scripts call after a failure.
#
# SAFE BY DEFAULT: dry-run unless --apply. Never touches Zoom, browsers,
# VS Code, Claude sessions, or anything on the protect list. Docker is left
# alone too, except for the opt-in section 11, which only `docker stop`s the
# containers of a stack no live session is working on (never removes anything).
#
# Usage:
#   ./memory-auto-clean.sh                          # dry run
#   ./memory-auto-clean.sh --apply                  # act
#   ./memory-auto-clean.sh --apply --orphans-all    # also kill busy orphans
#   ./memory-auto-clean.sh --dev-age-hours 48       # be laxer about dev servers
#   ./memory-auto-clean.sh --apply --dev            # dev pass only (sections 1, 2, 7–11)
#   ./memory-auto-clean.sh --apply --dev --now      # …and no idle wait for build
#                                                   #    leftovers (after a failed build)
#   ./memory-auto-clean.sh --apply --dev --quiet    # log/notify only when it reaps
# ---------------------------------------------------------------------------

set -u

# ---------- which bash is running this ----------
# The developer-tools pass (sections 2 and 7–11) keeps its bookkeeping in
# associative arrays, which need bash 4 or newer. macOS ships bash 3.2 as
# /bin/bash, and an app's PATH does not include Homebrew — so `env bash` can
# land on 3.2 even on a Mac that has a newer one. On 3.2 this script used to
# crash before section 1. Now: hand over to a newer bash when there is one;
# when there is not, run every section that does not need it and say plainly
# which ones were skipped.
DEV_PASS_OK=1
if (( BASH_VERSINFO[0] < 4 )); then
  for newer_bash in ${ANALYZERS_BASH_CANDIDATES:-/opt/homebrew/bin/bash /usr/local/bin/bash}; do
    if [[ -x "$newer_bash" ]] && "$newer_bash" -c '(( BASH_VERSINFO[0] >= 4 ))' 2>/dev/null; then
      exec "$newer_bash" "$0" "$@"
    fi
  done
  DEV_PASS_OK=0
fi
DEV_PASS_SKIPPED="skipped — the developer-tools checks need bash 4 or newer and this Mac has ${BASH_VERSION%%(*}. Install one with: brew install bash"

HOME_DIR="${HOME}"
DRY_RUN=1
ONLY_PIDS=""
ORPHANS_ALL=0
DEV_ONLY=0
DEV_NOW=0
QUIET=0
DEV_AGE_HOURS=24
PW_AGE_HOURS=2
LOG_DIR="${HOME_DIR}/mac-analyzers/reports/memory"
LOG_FILE="${LOG_DIR}/auto-clean.log"
LOCK_FILE="${LOG_DIR}/.auto-clean.lock"

# optional per-machine config (gitignored) — see config.example.sh at repo root
ANALYZERS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Settings live in the user folder. When the engine runs from inside the
# app bundle, that bundle is replaced wholesale on every update, so the
# user copy is the one that must win.
[[ -f "${ANALYZERS_ROOT}/config.local.sh" ]] && source "${ANALYZERS_ROOT}/config.local.sh"
[[ -f "$HOME/mac-analyzers/config.local.sh" && "${ANALYZERS_ROOT}" != "$HOME/mac-analyzers" ]] \
  && source "$HOME/mac-analyzers/config.local.sh"

MCP_RE='[Mm]cp'
[[ -n "${ANALYZERS_MCP_EXTRA_RE:-}" ]] && MCP_RE="${MCP_RE}|${ANALYZERS_MCP_EXTRA_RE}"
DEV_SERVER_RE='next-server|next dev|vite( |$)|pnpm( run)? dev|npm run dev|nodemon|turbo run dev'
PLAYWRIGHT_RE='headless_shell|ms-playwright|--headless'
PROTECT_RE='.local/bin/claude|(^|/)claude( |$)|Claude.app|Visual Studio Code|Code Helper|zoom.us|ZoomCef|Docker|OrbStack|Opera.app|Google Chrome.app|Safari|WindowServer|loginwindow|mds|Finder|screencapture|QuickTime|CoreServices|iTerm'
[[ -n "${ANALYZERS_PROTECT_EXTRA:-}" ]] && PROTECT_RE="${PROTECT_RE}|${ANALYZERS_PROTECT_EXTRA}"

# dev pass (sections 2, 7–10) — idle grace in minutes, see config.example.sh
DEV_DEVICE_IDLE_MIN="${ANALYZERS_DEV_DEVICE_IDLE_MIN:-20}"
DEV_DAEMON_IDLE_MIN="${ANALYZERS_DEV_DAEMON_IDLE_MIN:-5}"
DEV_SERVER_IDLE_MIN="${ANALYZERS_DEV_SERVER_IDLE_MIN:-30}"
DEV_ORPHAN_IDLE_MIN="${ANALYZERS_DEV_ORPHAN_IDLE_MIN:-3}"
DEV_REAP_SESSION_SERVERS="${ANALYZERS_DEV_REAP_SESSION_SERVERS:-0}"
DEV_BUSY_CPU_PCT=3      # CPU time growing faster than this % of one core = busy
DEV_STATE_FILE="${LOG_DIR}/.dev-idle-state"
DEV_NOTIFY_STAMP="${LOG_DIR}/.dev-notify-ts"

# dev pass, section 11 (opt-in) — stop the Docker/Supabase stacks of projects with no live AI session
DEV_STOP_IDLE_STACKS="${ANALYZERS_DEV_STOP_IDLE_STACKS:-0}"
STACK_IDLE_MIN="${ANALYZERS_STACK_IDLE_MIN:-30}"
STACK_PROTECT="${ANALYZERS_STACK_PROTECT:-}"
STACK_OWNER_MAP="${ANALYZERS_STACK_OWNER_MAP:-}"
STACK_REPO_ROOTS="${ANALYZERS_STACK_REPO_ROOTS:-$HOME/Projects}"
STACK_STATE_FILE="${ANALYZERS_STACK_STATE_FILE:-${LOG_DIR}/.stack-idle-state}"
STACK_STOP_BUDGET_S=180   # per stack: stop containers one by one until this many seconds are spent

ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)          DRY_RUN=0 ;;
    --dry-run)        DRY_RUN=1 ;;
    --orphans-all)    ORPHANS_ALL=1 ;;
    --dev)            DEV_ONLY=1 ;;
    --now)            DEV_NOW=1 ;;
    --quiet)          QUIET=1 ;;
    --only-pids)      ONLY_PIDS="${2:?--only-pids needs a file}"; shift ;;
    --dev-age-hours)  DEV_AGE_HOURS="${2:-24}"; shift ;;
    --pw-age-hours)   PW_AGE_HOURS="${2:-2}"; shift ;;
    -h|--help)        sed -n '2,60p' "$0"; exit 0 ;;
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
  echo "  4) Dev pass now — idle emulators/simulators, build daemons, dev servers (--dev)"
  echo "  q) Quit"
  echo ""
  read -rp "  Choose [1]: " choice
  case "${choice:-1}" in
    1) ;;
    2) DRY_RUN=0 ;;
    3) DRY_RUN=0; ORPHANS_ALL=1 ;;
    4) DRY_RUN=0; DEV_ONLY=1 ;;
    q|Q) exit 0 ;;
    *) echo "  Unknown choice '${choice}' — exiting."; exit 2 ;;
  esac
  INVOKED="interactive menu: choice ${choice:-1}"
fi

mkdir -p "$LOG_DIR"

# the guard's pause ("heavy legit build in progress") holds the dev pass too
if [[ "$DEV_ONLY" -eq 1 && -e "${LOG_DIR}/.guard-paused" ]]; then
  [[ "$QUIET" -eq 1 ]] || echo "memory guard is paused — dev pass skipped (resume: rm ${LOG_DIR}/.guard-paused)."
  exit 0
fi

# the dev-only pass has nothing it can do on an old bash — the guard calls it
# every few minutes with --quiet, so say it once only when someone is watching
if [[ "$DEV_ONLY" -eq 1 && "$DEV_PASS_OK" -eq 0 ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "Developer-tools pass ${DEV_PASS_SKIPPED}"
  exit 0
fi

# ---------- single-instance lock ----------
if [[ -e "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
  [[ "$QUIET" -eq 1 ]] || echo "memory auto-clean already running (pid $(cat "$LOCK_FILE")); exiting." >&2
  exit 0
fi
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE" "${STACK_STATE_FILE}.tmp.$$"' EXIT

# live AI-session exemption (shared with memory-reclaim.sh) — no lib, no sweep
# shellcheck disable=SC1091
if ! source "${ANALYZERS_ROOT}/lib/live-sessions.sh"; then
  echo "FATAL: lib/live-sessions.sh or its list of coding agents (lib/coding-agents.tsv) is missing, unreadable or names no agent — refusing to sweep without the live-session exemption." >&2
  exit 79
fi

# ---------- helpers ----------
FREED_KB=0
KILL_COUNT=0
TS_NOW="$(date '+%Y-%m-%d %H:%M:%S')"

# --quiet (the guard's dev pass every couple of minutes): hold the run's lines
# and write them only if it reaped something, so the app's Reap view keeps
# showing the last run that actually did something.
LOG_BUF=""
log() {
  if [[ "$QUIET" -eq 1 ]]; then LOG_BUF+="$*"$'\n'; else echo "$*" | tee -a "$LOG_FILE"; fi
}
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

# --only-pids <file>: stop ONLY the pids listed in the file, one per line.
# The sweep still finds its own candidates — the approved set can only ever
# SHRINK what gets stopped. A pid recycled between preview and apply is not
# a hazard either: identity is re-checked by the sweep, not taken from here.
approved_pid() {
  [[ -z "${ONLY_PIDS}" ]] && return 0
  case "$1" in
    *[!0-9]*) approved_list_has "$1" ;;          # a stack key and the like: a whole line
    *) approved_list_has_process "$1" ;;          # a pid: also the process it was when reviewed
  esac
}

# The reviewed list is read once (lib/approved-list.sh): a `grep` per item made a
# 6,000-item apply take minutes. A list that cannot be checked stops the run.
if [[ -n "${ONLY_PIDS}" ]]; then
  if ! source "${ANALYZERS_ROOT}/lib/approved-list.sh" 2>/dev/null; then
    echo "FATAL: lib/approved-list.sh is missing — refusing to run with a reviewed list it cannot check." >&2
    exit 78
  fi
  approved_list_load "${ONLY_PIDS}"
fi

# reap <pid> <rss_kb> <desc> — dry-run-aware kill with accounting
reap() {
  local pid="$1" rsskb="$2" desc="$3"
  if ! approved_pid "$pid"; then
    log "  [SKIP]    not in approved set  pid=$pid  $desc"
    return 0
  fi
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

# with_timeout <secs> <cmd…> — adb/simctl can hang on a wedged device
with_timeout() {
  local secs="$1" i=0 p; shift
  "$@" & p=$!
  while kill -0 "$p" 2>/dev/null && [[ $i -lt $((secs * 10)) ]]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then kill -KILL "$p" 2>/dev/null; wait "$p" 2>/dev/null; return 124; fi
  wait "$p"
}

# same_args <pid> <args-as-snapshotted> — guard against a recycled pid.
# Both sides are normalised (runs of spaces collapsed, ends trimmed) because a
# process that rewrites its title (npm: `npm exec expo start …`) is padded
# with a trailing space or followed by leftover env strings in ps's args=
# column — the snapshot (awk-rebuilt, so already trimmed) then never matched
# the live string byte-for-byte and a live idle Metro was logged [GONE] for
# days. The pid is the same process when the live args START WITH the
# snapshot's first <=60 chars (a tail is fine), on a word boundary when the
# snapshot was shorter than 60 so `node` can't pass for `node server.js`.
# A recycled pid runs a different command, so it still fails; no new
# snapshot column or ps call is needed, and it is no looser than before for
# any process whose args did not change.
same_args() {
  local now exp
  now="$(ps -o args= -p "$1" 2>/dev/null | tr -s ' ')"; now="${now# }"; now="${now% }"
  exp="$(printf '%s' "$2" | tr -s ' ' | cut -c1-60)"; exp="${exp# }"; exp="${exp% }"
  [[ -n "$now" && -n "$exp" ]] || return 1
  if [[ ${#exp} -ge 59 ]]; then [[ "${now:0:${#exp}}" == "$exp" ]]
  else [[ "$now" == "$exp" || "$now" == "$exp "* ]]; fi
}

# reap_tree <root> <members> <rss_kb> <desc> <root_args> [term_wait] — one
# dev unit (a server + its wrappers, an orphaned tool tree, a JVM daemon):
# SIGTERM every member root-first (a supervisor can't respawn what goes
# next), wait, SIGKILL survivors. Dry-run- and --only-pids-aware like reap().
reap_tree() {
  local root="$1" members="$2" rsskb="$3" desc="$4" rargs="$5" wait_s="${6:-5}" extra p i=0 alive
  if ! approved_pid "$root"; then
    log "  [SKIP]    not in approved set  pid=$root  $desc"; return 0
  fi
  extra=$(( $(wc -w <<<"$members") - 1 ))
  [[ "$extra" -gt 0 ]] && desc="$desc (+${extra} child process$([[ $extra -gt 1 ]] && echo es))"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "  [DRY]     $(printf '%7s' "$((rsskb/1024)) MB")  pid=$root  $desc"
    FREED_KB=$((FREED_KB + rsskb)); KILL_COUNT=$((KILL_COUNT + 1)); return 0
  fi
  if ! same_args "$root" "$rargs"; then
    log "  [GONE]    pid=$root  $desc"; return 0
  fi
  # re-derive the tree NOW (before any signal reparents it): the snapshot is
  # seconds old, and a recycled pid is never a descendant of this root
  members="$(ps axo pid=,ppid= | awk -v root="$root" -v snap=" $members " '
    { pp[$1] = $2 }
    END { for (p in pp) { q = p; while (q > 1 && q != "") { if (q == root) { if (index(snap, " " p " ")) print p; break }; q = pp[q] } } }' \
    | sort -n | awk -v root="$root" 'BEGIN { print root } $1 != root')"
  for p in $members; do kill -TERM "$p" 2>/dev/null; done
  while [[ $i -lt $wait_s ]]; do
    alive=0; for p in $members; do kill -0 "$p" 2>/dev/null && { alive=1; break; }; done
    [[ $alive -eq 0 ]] && break; sleep 1; i=$((i + 1))
  done
  for p in $members; do kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null; done
  log "  [KILLED]  $(printf '%7s' "$((rsskb/1024)) MB")  pid=$root  $desc"
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
    printf "%s\t%s\t%s\t%s\t%.400s\n", pid, ppid, rss, etime2s(et), $0 }')"

# candidates <filter_re> <exclude_protect=1> — rows of SNAP matching re
candidates() {
  local re="$1"
  echo "$SNAP" | awk -F'\t' -v re="$re" -v protre="$PROTECT_RE" -v self="$$" '
    $1+0 > 500 && $1 != self && $5 ~ re && $5 !~ protre'
}

before_state() { top -l 1 -n 0 2>/dev/null | grep PhysMem; sysctl -n vm.swapusage; }

# =================== dev pass: idle dev tooling (sections 2, 7–10) ===================
# One look at the process table groups dev tooling into UNITS — an emulator,
# a build daemon, a dev server with the wrappers that would respawn it, an
# orphaned tool tree — and judges each by what it is DOING:
#   busy = a client connected to its ports, or its CPU time grew since the
#          last pass (CPU only ever keeps a unit alive), or — for devices — a
#          build/test/driver process or Metro activity, or its window in front;
#   idle = none of that. The first idle sighting is kept in .dev-idle-state;
#          a unit is reaped once idle past its grace.
# Nothing descending from a live claude/codex session becomes a unit, except
# (opt-in, ANALYZERS_DEV_REAP_SESSION_SERVERS=1) an idle dev server such a
# session left running in the background.

DEV_PASS_SERVER_RE='next-server|(^|[ /])next (dev|start)( |$)|(^|/)vite( |$)|/vite/bin/vite\.js|expo/bin/cli start|(^|[ /])expo start( |$)|react-native start|(^|/)metro( |$)|webpack-dev-server|webpack(\.js)? serve|storybook (dev|start)|astro dev|nuxt dev|remix dev|wrangler dev|tsx watch|(^|/)nodemon( |$)|turbo run dev|pnpm( run)? dev( |$)|npm run dev( |$)|uvicorn|manage\.py runserver|flask run|http\.server'
DEV_METRO_RE='expo/bin/cli start|(^|[ /])expo start( |$)|react-native start|(^|/)metro( |$)'
# what makes an orphaned tree "dev tooling": installed tools, never a bare `node my-script.js`
DEV_TOOL_RE='node_modules|\.pnpm/|(^|/)(npm|npx|pnpm|pnpx|yarn|bunx|turbo|esbuild|tsc|tsx|vitest|jest)( |$)|headless_shell|ms-playwright|chrome-headless-shell'
DEV_XCODE_RE='/Xcode[^/]*\.app/Contents/.*/(ibtoold|XCBBuildService|SWBBuildService|swift-frontend|actool|ibtool|xcodebuild)( |$)|(^|/)(XCBBuildService|SWBBuildService)( |$)'
DEV_ANDROID_DRIVER_RE='(^|/)adb( |$)|org\.gradle\.wrapper\.GradleWrapperMain|org\.gradle\.launcher\.GradleMain|expo/bin/cli run:android|expo run:android|dev-emulator|maestro|uiautomator|scrcpy|detox'
DEV_IOS_DRIVER_RE='(^|/)xcodebuild( |$)|expo/bin/cli run:ios|expo run:ios|simctl|idb_companion|maestro|detox|XCTRunner|ios-deploy'
DEV_SELF_RE='memory-auto-clean|memory-guard|memory-reclaim|agent-runner'

NOW_TS=$(date +%s)
DEV_SESSION_ROOTS="$(live_session_roots)"
declare -a U_CLASS U_ROOT U_MEMBERS U_RSS U_CPU U_PCPU U_OWNER U_CONN U_AGE U_LABEL U_ARGS U_VERDICT U_NOTE
[[ "$DEV_PASS_OK" -eq 1 ]] && declare -A DEV_FLAG=() S_START=() S_IDLE=() S_CPU=() S_TS=()

# pid \t ppid \t tty \t rss \t pcpu \t cpu_s \t age_s \t args
DSNAP="$(LC_ALL=C ps axo pid=,ppid=,tt=,rss=,pcpu=,time=,etime=,args= | awk '
  function etime2s(e,  a,d,hms,n,s) {
    d=0; if (e ~ /-/) { split(e,a,"-"); d=a[1]; e=a[2] }
    n=split(e,hms,":");
    if (n==3) s=hms[1]*3600+hms[2]*60+hms[3]; else if (n==2) s=hms[1]*60+hms[2]; else s=hms[1]+0;
    return d*86400+s
  }
  function cpu2s(t,  a,n) { n=split(t,a,":"); if (n==3) return a[1]*3600+a[2]*60+a[3]; if (n==2) return a[1]*60+a[2]; return t+0 }
  { pid=$1; ppid=$2; tt=$3; rss=$4; pc=$5; ct=$6; et=$7; $1=$2=$3=$4=$5=$6=$7=""; sub(/^ +/,""); gsub(/\t/," ");
    printf "%s\t%s\t%s\t%s\t%s\t%d\t%d\t%.400s\n", pid, ppid, tt, rss, pc, cpu2s(ct), etime2s(et), $0 }')"

# build the units — one awk over sockets (S) + processes (P)
dev_build_units() {
  local launchd_pids exempt
  launchd_pids="$(launchctl list 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {printf "%s ", $1}')"
  exempt="$(live_session_exempt "$DEV_SESSION_ROOTS" | tr '\n' ' ')"
  {
    lsof -nP -iTCP -sTCP:LISTEN,ESTABLISHED -FpnT 2>/dev/null | awk '
      /^p/ { pid=substr($0,2); next } /^n/ { name=substr($0,2); next }
      /^TST=/ { print "S\t" pid "\t" substr($0,5) "\t" name }'
    echo "$DSNAP" | sed 's/^/P	/'
  } | RE_SELF="$DEV_SELF_RE" RE_PROTECT="$PROTECT_RE" RE_MCP="$MCP_RE" RE_SERVER="$DEV_PASS_SERVER_RE" \
      RE_METRO="$DEV_METRO_RE" RE_DEV="$DEV_TOOL_RE" RE_XCODE="$DEV_XCODE_RE" \
      RE_ANDROID="$DEV_ANDROID_DRIVER_RE" RE_IOS="$DEV_IOS_DRIVER_RE" \
    awk -F'\t' -v launchd="$launchd_pids" -v exempt="$exempt" -v roots="$DEV_SESSION_ROOTS" \
        -v self="$$" -v reapsession="$DEV_REAP_SESSION_SERVERS" '
    BEGIN {
      # patterns come through ENVIRON: awk -v would turn their \. into "any character"
      selfre = ENVIRON["RE_SELF"]; protre = ENVIRON["RE_PROTECT"]; mcpre = ENVIRON["RE_MCP"]
      serverre = ENVIRON["RE_SERVER"]; metrore = ENVIRON["RE_METRO"]; devre = ENVIRON["RE_DEV"]
      xcodere = ENVIRON["RE_XCODE"]; androidre = ENVIRON["RE_ANDROID"]; iosre = ENVIRON["RE_IOS"]
      n = split(launchd, lst, " "); for (i = 1; i <= n; i++) LD[lst[i]] = 1
      n = split(exempt, lst, " ");  for (i = 1; i <= n; i++) EX[lst[i]] = 1
      n = split(roots, lst, " ");   for (i = 1; i <= n; i++) SR[lst[i]] = 1
    }
    $1 == "S" {
      if ($3 == "LISTEN") { port = $4; sub(/.*:/, "", port); LP[$2 SUBSEP port] = 1 }
      else if ($3 == "ESTABLISHED") { split($4, ends, "->"); ne++; EP[ne] = $2; EL[ne] = ends[1]; ER[ne] = ends[2]; EOWN[ends[1]] = $2 }
      next
    }
    $1 == "P" { p = $2; PP[p] = $3; TT[p] = $4; RSS[p] = $5; PC[p] = $6; CPU[p] = $7; AGE[p] = $8; ARGS[p] = $9
                KIDS[$3] = KIDS[$3] " " p; ALL[++np] = p }
    function exe(p,  first, part, n) { first = ARGS[p]; sub(/ .*/, "", first); n = split(first, part, "/"); return part[n] }
    # who a process belongs to: session | launchd | tty | app | orphan (ROOT[p] = topmost ancestor)
    function owner(p,  q, top) {
      if (p in OWN) return OWN[p]
      if (p in EX) return OWN[p] = "session"
      q = p; top = p
      while (q != "" && q + 0 > 1) {
        if (q in LD) return OWN[p] = "launchd"
        if (TT[q] != "??") return OWN[p] = "tty"
        if (q != p && ARGS[q] ~ /^\/(Applications|System|Library\/Apple|usr\/libexec|usr\/sbin)\//) return OWN[p] = "app"
        top = q
        if (PP[q] + 0 <= 1 || !(PP[q] in ARGS)) break
        q = PP[q]
      }
      ROOT[p] = top
      return OWN[p] = "orphan"
    }
    function subtree(p,  out, k, n, i) {
      out = p; n = split(KIDS[p], k, " ")
      for (i = 1; i <= n; i++) if (k[i] != "") out = out " " subtree(k[i])
      return out
    }
    # 1 if a process OUTSIDE the unit holds a connection to one of its listening ports
    function connbusy(members,  m, n, i, j, mem, lp, listening) {
      n = split(members, m, " "); for (i = 1; i <= n; i++) mem[m[i]] = 1
      for (j = 1; j <= ne; j++) {
        if (!(EP[j] in mem)) continue
        lp = EL[j]; sub(/.*:/, "", lp); listening = 0
        for (i = 1; i <= n; i++) if ((m[i] SUBSEP lp) in LP) { listening = 1; break }
        if (!listening) continue
        if ((ER[j] in EOWN) && (EOWN[ER[j]] in mem)) continue
        return 1
      }
      return 0
    }
    # allow = 1 only for the opt-in session-server path (members are a background task of a live session)
    function emit(cls, root, members, label, allow,   m, n, i, rss, cpu, pc) {
      n = split(members, m, " ")
      for (i = 1; i <= n; i++) {
        if (ARGS[m[i]] ~ protre) return                               # the protect list always wins
        if ((m[i] in SR) || exe(m[i]) == "claude") return             # a session itself is never in a unit
        if ((m[i] in EX) && !allow) return                            # live-session exemption
        if (allow && ARGS[m[i]] ~ mcpre) return                       # never an MCP server of a session
      }
      for (i = 1; i <= n; i++) { rss += RSS[m[i]]; cpu += CPU[m[i]]; pc += PC[m[i]]; CLAIM[m[i]] = 1 }
      printf "U\t%s\t%s\t%s\t%d\t%d\t%d\t%s\t%d\t%d\t%s\t%.200s\n", cls, root, members, rss, cpu, pc, owner(root), connbusy(members), AGE[root], label, ARGS[root]
    }
    function skippable(p) { return p + 0 <= 100 || p == self || ARGS[p] ~ selfre || ARGS[p] ~ /CoreSimulator\// }
    END {
      for (i = 1; i <= np; i++) {
        p = ALL[i]; a = ARGS[p]; if (skippable(p)) continue
        if (a ~ androidre && !(exe(p) == "adb" && a ~ /fork-server|server nodaemon/)) F["android"] = 1
        if (a ~ iosre) F["ios"] = 1
        if (a ~ /org\.gradle\.wrapper\.GradleWrapperMain|org\.gradle\.launcher\.GradleMain/) F["gradle"] = 1
        if (exe(p) == "xcodebuild") F["xcodebuild"] = 1
        if (a ~ /Xcode[^\/]*\.app\/Contents\/MacOS\/Xcode( |$)/) F["xcodegui"] = 1
        if (a ~ /Android Studio[^\/]*\.app\/Contents\/MacOS\/studio/) F["studio"] = 1
        if (a ~ /Simulator\.app\/Contents\/MacOS\/Simulator( |$)/) F["simapp"] = p
        if (a ~ /qemu-system-/) F["qemu"]++
        # every Metro, a live session one too: CPU growth = someone is iterating on a device
        if (a ~ metrore && !((PP[p] in ARGS) && ARGS[PP[p]] ~ metrore)) printf "M\t%s\t%d\t%d\n", p, CPU[p], AGE[p]
      }
      for (f in F) printf "F\t%s\t%s\n", f, F[f]
      # devices, build daemons, build leftovers
      for (i = 1; i <= np; i++) {
        p = ALL[i]; a = ARGS[p]; if (skippable(p)) continue
        o = owner(p)
        if (a ~ /qemu-system-/) {
          if (o == "launchd" || o == "app" || o == "session") continue
          avd = "emulator"; if (match(a, /-avd [^ ]+/)) avd = substr(a, RSTART + 5, RLENGTH - 5)
          win = (a ~ /-no-window/ || exe(p) ~ /headless/) && o != "tty" ? "headless" : "windowed"
          emit("emulator", p, subtree(p), avd " " win)
        } else if (o == "orphan" && a ~ /org\.gradle\.launcher\.daemon\.bootstrap\.GradleDaemon|KotlinCompileDaemon/) {
          emit("daemon", p, subtree(p), a ~ /KotlinCompileDaemon/ ? "kotlin-daemon" : "gradle-daemon")
        } else if (o == "orphan" && a ~ xcodere) {
          emit("buildleft", p, subtree(p), "xcode-" exe(p))
        } else if (o == "orphan" && a ~ /\/emulator\/(netsimd|crashpad_handler)( |$)|(^|\/)netsimd( |$)/) {
          emit("plumbing", p, subtree(p), "emulator-" exe(p))
        }
      }
      # dev servers — the unit is the tree that would respawn them
      for (i = 1; i <= np; i++) {
        p = ALL[i]; a = ARGS[p]
        if (skippable(p) || (p in CLAIM) || a !~ serverre) continue
        if ((PP[p] in ARGS) && ARGS[PP[p]] ~ serverre) continue          # topmost server in its chain
        o = owner(p)
        if (o == "orphan") root = ROOT[p]
        else if (o == "session" && reapsession == "1") {
          root = p; while ((PP[root] in ARGS) && !(PP[root] in SR)) root = PP[root]
          if (!(PP[root] in SR)) continue                                # walk ended without reaching the session
          if (exe(root) !~ /^(zsh|bash|sh|fish)$/) continue             # only a tool-call shell, never a direct child (MCP)
        } else continue
        if (root in CLAIM) continue
        label = "dev-server"; if (match(a, serverre)) { label = substr(a, RSTART, RLENGTH); gsub(/^[ \/]+|[ ]+$/, "", label) }
        if (a ~ metrore) label = "metro"
        emit("server", root, subtree(root), label, o == "session")
      }
      # orphaned dev-tool trees (parent gone)
      for (i = 1; i <= np; i++) {
        p = ALL[i]; a = ARGS[p]
        if (skippable(p) || (p in CLAIM) || owner(p) != "orphan" || ROOT[p] != p) continue
        if (a ~ mcpre || a ~ /^\/(Applications|System|Library|usr\/libexec|usr\/sbin|sbin)\//) continue
        t = subtree(p); n = split(t, m, " "); taken = 0; kids = 0; alldev = 1
        for (j = 1; j <= n; j++) {
          if (m[j] in CLAIM) taken = 1
          if (j > 1 && exe(m[j]) !~ /^(zsh|bash|sh|fish)$/) { kids++; if (ARGS[m[j]] !~ devre) alldev = 0 }
        }
        # a `-c` wrapper shell (an orphaned tool call, sh -c pnpm dev) is plumbing;
        # a shell running a script file (backup.sh) is a user program — never dev tooling
        dev = (a ~ devre) || (exe(p) ~ /^(zsh|bash|sh|fish)$/ && a ~ / -c / && kids > 0 && alldev)
        if (dev && !taken) emit("orphan", p, t, exe(p))
      }
    }'
}

# dev_footprint_kb <pid…> — summed physical footprint (top's MEM: private + compressed),
# the number that actually comes back when those processes exit
dev_footprint_kb() {
  [[ $# -eq 0 ]] && { echo 0; return; }
  local args=() p
  for p in "$@"; do args+=(-pid "$p"); done
  top -l 1 -stats pid,mem "${args[@]}" 2>/dev/null | awk '
    $1 ~ /^[0-9]+$/ { v = $2; sub(/[+-]$/, "", v); u = substr(v, length(v)); n = v + 0
      if (u == "G") n *= 1048576; else if (u == "M") n *= 1024; else if (u == "B") n /= 1024
      s += n }
    END { printf "%d\n", s }'
}

# booted simulators: udid \t name \t launchd_sim pid \t footprint_kb
dev_booted_sims() {
  pgrep -x launchd_sim >/dev/null 2>&1 || return 0
  local udid name lpid kids kid footprint
  while IFS=$'\t' read -r udid name; do
    [[ -z "$udid" ]] && continue
    lpid="$(echo "$DSNAP" | awk -F'\t' -v u="$udid" '$8 ~ /launchd_sim/ && index($8, u) { print $1; exit }')"
    [[ -z "$lpid" ]] && continue
    # protect list wins here too (e.g. ANALYZERS_PROTECT_EXTRA='Simulator' or a device name)
    if printf '%s\n%s\n' "$name" "$(echo "$DSNAP" | awk -F'\t' -v p="$lpid" '$1 == p {print $8}')" | grep -qE -- "$PROTECT_RE"; then
      continue
    fi
    # the simulator's process tree, as an array so each pid is its own argument
    kids=()
    while IFS= read -r kid; do kids+=("$kid"); done < <(echo "$DSNAP" | awk -F'\t' -v root="$lpid" '
      { pp[$1] = $2 }
      END { for (p in pp) { q = p; while (q > 1 && q != "") { if (q == root) { print p; break }; q = pp[q] } } }')
    footprint="$(dev_footprint_kb ${kids[@]+"${kids[@]}"})"
    printf '%s\t%s\t%s\t%s\n' "$udid" "$name" "$lpid" "$footprint"
  done < <(with_timeout 20 xcrun simctl list devices booted 2>/dev/null | awk '
    /\(Booted\)/ && match($0, /\([0-9A-F-]{36}\)/) {
      name = substr($0, 1, RSTART - 1); gsub(/^[ \t]+|[ \t]+$/, "", name)
      print substr($0, RSTART + 1, 36) "\t" name }')
}

# outermost git repo above a directory (a worktree resolves to its main repo)
[[ "$DEV_PASS_OK" -eq 1 ]] && declare -A DEV_PKEY=()
project_key() {
  local d="$1" best=""
  [[ -z "$d" ]] && return 0
  if [[ -n "${DEV_PKEY[$d]+x}" ]]; then echo "${DEV_PKEY[$d]}"; return 0; fi
  local x="$d"
  while [[ -n "$x" && "$x" != "/" && "$x" != "$HOME" ]]; do
    [[ -e "$x/.git" ]] && best="$x"
    x="${x%/*}"
  done
  DEV_PKEY[$d]="$best"; echo "$best"
}

# cpu_grew <key> <start_epoch> <cpu_s> <pcpu> — 1 if CPU time grew faster than
# DEV_BUSY_CPU_PCT since the last pass (first sighting: ps's own %CPU). Sets
# PREV_IDLE to the remembered first-idle time when it is the same process.
cpu_grew() {
  local key="$1" start="$2" cpu="$3" pcpu="${4%.*}" ps_start ps_ts ps_cpu dt dcpu
  PREV_IDLE=""
  ps_start="${S_START[$key]:-}"; ps_ts="${S_TS[$key]:-}"; ps_cpu="${S_CPU[$key]:-0}"
  if [[ -n "$ps_ts" && $((start - ps_start)) -le 5 && $((ps_start - start)) -le 5 ]]; then
    [[ "${S_IDLE[$key]}" != "-" ]] && PREV_IDLE="${S_IDLE[$key]}"
    dt=$((NOW_TS - ps_ts)); dcpu=$((cpu - ps_cpu)); [[ $dcpu -lt 0 ]] && dcpu=0
    [[ $dt -gt 0 && $((dcpu * 100)) -gt $((DEV_BUSY_CPU_PCT * dt)) ]] && return 0
    return 1
  fi
  [[ "${pcpu:-0}" -gt $((DEV_BUSY_CPU_PCT * 2)) ]]
}

# session_dir_live <dir> — 1 if the folder belongs to an agent session that is still
# working: a session UUID in the path (scratchpads live under …/<session-uuid>/…)
# whose Claude Code transcript was written within ANALYZERS_DEV_SERVER_IDLE_MIN.
[[ "$DEV_PASS_OK" -eq 1 ]] && declare -A DEV_SDIR=()
session_dir_live() {
  local d="$1" u
  [[ -z "$d" ]] && return 1
  if [[ -n "${DEV_SDIR[$d]+x}" ]]; then return "${DEV_SDIR[$d]}"; fi
  DEV_SDIR[$d]=1
  for u in $(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$d" | sort -u); do
    if [[ -n "$(find "$HOME/.claude/projects" -maxdepth 2 -name "$u.jsonl" -mmin "-${DEV_SERVER_IDLE_MIN}" 2>/dev/null | head -1)" ]]; then
      DEV_SDIR[$d]=0; break
    fi
  done
  return "${DEV_SDIR[$d]}"
}

dev_evaluate() {
  local cls key start first_idle cpubusy busy grace idle_s pk i n=0 metro_active=0
  local -a metro_lines=()
  # previous observations: key \t start \t first_idle ("-" = busy) \t cpu_s \t seen_at
  if [[ -f "$DEV_STATE_FILE" ]]; then
    while IFS=$'\t' read -r key start first_idle cpubusy idle_s; do
      [[ -z "$key" ]] && continue
      S_START[$key]="$start"; S_IDLE[$key]="$first_idle"; S_CPU[$key]="$cpubusy"; S_TS[$key]="$idle_s"
    done < "$DEV_STATE_FILE"
  fi
  while IFS=$'\t' read -r tag c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11; do
    if [[ "$tag" == "F" ]]; then DEV_FLAG[$c1]="$c2"; continue; fi
    if [[ "$tag" == "M" ]]; then metro_lines+=("$c1 $c2 $c3"); continue; fi
    [[ "$tag" == "U" ]] || continue
    U_CLASS[n]="$c1"; U_ROOT[n]="$c2"; U_MEMBERS[n]="$c3"; U_RSS[n]="$c4"; U_CPU[n]="$c5"
    U_PCPU[n]="$c6"; U_OWNER[n]="$c7"; U_CONN[n]="$c8"; U_AGE[n]="$c9"; U_LABEL[n]="$c10"; U_ARGS[n]="$c11"
    n=$((n + 1))
  done < <(dev_build_units)
  while IFS=$'\t' read -r c1 c2 c3 c4; do
    U_CLASS[n]="simulator"; U_ROOT[n]="$c3"; U_MEMBERS[n]="$c3"; U_RSS[n]="$c4"; U_CPU[n]=0; U_PCPU[n]=0
    U_OWNER[n]="system"; U_CONN[n]=0; U_AGE[n]=0; U_LABEL[n]="$c2"; U_ARGS[n]="$c1"   # ARGS carries the udid
    n=$((n + 1))
  done < <(dev_booted_sims)
  DEV_N=$n

  # which projects are open (a session or terminal sits in them), and the cwd of each unit root
  local pids="" p cwd
  for p in $DEV_SESSION_ROOTS; do pids+="$p,"; done
  for p in $(echo "$DSNAP" | awk -F'\t' '$3 != "??" && $8 ~ /^-?(zsh|bash|fish|sh)( |$)|^\/bin\/(zsh|bash|sh)( |$)/ {print $1}'); do pids+="$p,"; done
  for ((i = 0; i < n; i++)); do [[ "${U_CLASS[i]}" == server || "${U_CLASS[i]}" == orphan ]] && pids+="${U_ROOT[i]},"; done
  declare -gA DEV_CWD=() DEV_LIVE_PROJECT=()
  if [[ -n "$pids" ]]; then
    while IFS=$'\t' read -r p cwd; do DEV_CWD[$p]="$cwd"; done < <(lsof -a -d cwd -p "${pids%,}" -Fpn 2>/dev/null | awk '/^p/ {p=substr($0,2)} /^n/ {print p "\t" substr($0,2)}')
  fi
  for p in $DEV_SESSION_ROOTS $(echo "$DSNAP" | awk -F'\t' '$3 != "??" && $8 ~ /^-?(zsh|bash|fish|sh)( |$)|^\/bin\/(zsh|bash|sh)( |$)/ {print $1}'); do
    pk="$(project_key "${DEV_CWD[$p]:-}")"; [[ -n "$pk" ]] && DEV_LIVE_PROJECT[$pk]=1
  done
  DEV_FRONT="$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null | awk -F'"' 'NR==1 {print $2}')"

  local state_tmp="${DEV_STATE_FILE}.tmp.$$" m mpid mcpu mage pass
  : > "$state_tmp"
  # Metro activity (any Metro, a live session's included) feeds the device check
  for m in "${metro_lines[@]}"; do
    read -r mpid mcpu mage <<<"$m"
    key="metro:${mpid}"; start=$((NOW_TS - mage))
    cpu_grew "$key" "$start" "$mcpu" 0 && metro_active=1
    printf '%s\t%s\t-\t%s\t%s\n' "$key" "$start" "$mcpu" "$NOW_TS" >> "$state_tmp"
  done

  # judge: everything but devices first (a Metro unit's CPU feeds metro_active too)
  for pass in other device; do
    for ((i = 0; i < n; i++)); do
      cls="${U_CLASS[i]}"
      if [[ "$pass" == other && ( "$cls" == emulator || "$cls" == simulator ) ]]; then continue; fi
      if [[ "$pass" == device && "$cls" != emulator && "$cls" != simulator ]]; then continue; fi
      key="${cls}:${U_ROOT[i]}"; start=$((NOW_TS - U_AGE[i])); cpubusy=0
      [[ "$cls" == simulator ]] && { key="simulator:${U_ARGS[i]}"; start=0; }
      cpu_grew "$key" "$start" "${U_CPU[i]}" "${U_PCPU[i]}" && cpubusy=1
      first_idle="$PREV_IDLE"
      busy=0; grace=0; U_NOTE[i]=""
      cwd="${DEV_CWD[${U_ROOT[i]}]:-}"
      case "$cls" in
        emulator)
          [[ "${DEV_FLAG[android]:-0}" == 1 || $metro_active -eq 1 || "$DEV_FRONT" == *qemu* || "$DEV_FRONT" == *Emulator* ]] && busy=1
          grace=$DEV_DEVICE_IDLE_MIN; [[ "${U_LABEL[i]}" == *windowed ]] && grace=$((grace * 2)) ;;
        simulator)
          [[ "${DEV_FLAG[ios]:-0}" == 1 || $metro_active -eq 1 || "$DEV_FRONT" == Simulator ]] && busy=1
          grace=$DEV_DEVICE_IDLE_MIN ;;
        daemon)
          if [[ "${DEV_FLAG[studio]:-0}" == 1 ]]; then U_VERDICT[i]="skip"; U_NOTE[i]="Android Studio is open"; continue; fi
          [[ "${DEV_FLAG[gradle]:-0}" == 1 || $cpubusy -eq 1 ]] && busy=1   # IDE/Tooling-API builds have no gradlew client
          grace=$([[ $DEV_NOW -eq 1 ]] && echo 0 || echo "$DEV_DAEMON_IDLE_MIN") ;;
        buildleft)
          if [[ "${DEV_FLAG[xcodegui]:-0}" == 1 ]]; then U_VERDICT[i]="skip"; U_NOTE[i]="Xcode is open"; continue; fi
          [[ "${DEV_FLAG[xcodebuild]:-0}" == 1 || $cpubusy -eq 1 ]] && busy=1
          grace=$([[ $DEV_NOW -eq 1 ]] && echo 0 || echo "$DEV_ORPHAN_IDLE_MIN") ;;
        plumbing)
          if [[ "${DEV_FLAG[qemu]:-0}" -gt 0 ]]; then U_VERDICT[i]="skip"; U_NOTE[i]="an emulator is running"; continue; fi
          grace=0 ;;
        server)
          [[ "${U_CONN[i]}" == 1 || $cpubusy -eq 1 ]] && busy=1
          if [[ -n "$cwd" && "$cwd" != *'\x'* && ! -d "$cwd" ]]; then grace=0; U_NOTE[i]="its folder was deleted"
          elif [[ "${U_OWNER[i]}" == session ]]; then grace=$DEV_SERVER_IDLE_MIN; U_NOTE[i]="inside a live session"
          else
            pk="$(project_key "$cwd")"
            if [[ -n "$pk" && -n "${DEV_LIVE_PROJECT[$pk]+x}" ]]; then grace=$DEV_SERVER_IDLE_MIN
            elif session_dir_live "$cwd"; then grace=$DEV_SERVER_IDLE_MIN; U_NOTE[i]="in an active session's folder"
            else grace=$DEV_ORPHAN_IDLE_MIN; U_NOTE[i]="no session or terminal in its project"; fi
          fi
          [[ "${U_LABEL[i]}" == metro && $cpubusy -eq 1 ]] && metro_active=1 ;;
        orphan)
          [[ "${U_CONN[i]}" == 1 || $cpubusy -eq 1 || "${U_AGE[i]}" -lt 60 ]] && busy=1
          grace=$DEV_ORPHAN_IDLE_MIN
          [[ $DEV_NOW -eq 1 ]] && grace=0
          [[ -n "$cwd" && "$cwd" != *'\x'* && ! -d "$cwd" ]] && { grace=0; U_NOTE[i]="its folder was deleted"; } ;;
      esac
      if [[ $busy -eq 1 ]]; then
        U_VERDICT[i]="busy"; first_idle=""
      else
        first_idle="${first_idle:-$NOW_TS}"; idle_s=$((NOW_TS - first_idle))
        if (( idle_s >= grace * 60 )); then U_VERDICT[i]="reap"; else U_VERDICT[i]="wait"; fi
        U_NOTE[i]="idle $((idle_s / 60))m of ${grace}m${U_NOTE[i]:+ — ${U_NOTE[i]}}"
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$key" "$start" "${first_idle:--}" "${U_CPU[i]}" "$NOW_TS" >> "$state_tmp"
    done
  done
  mv -f "$state_tmp" "$DEV_STATE_FILE"
}

# adb for the emulator a qemu belongs to: config → PATH → that emulator's own SDK → default SDK
dev_adb() {
  local q="${1%% *}" sdk
  [[ -n "${ANALYZERS_ADB:-}" && -x "${ANALYZERS_ADB}" ]] && { echo "$ANALYZERS_ADB"; return; }
  command -v adb 2>/dev/null && return
  sdk="${q%%/emulator/*}"; [[ "$sdk" != "$q" && -x "$sdk/platform-tools/adb" ]] && { echo "$sdk/platform-tools/adb"; return; }
  [[ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]] && echo "$HOME/Library/Android/sdk/platform-tools/adb"
}

# quit_emulator <i> — graceful `adb emu kill` (keeps the quick-boot snapshot), then TERM → KILL
quit_emulator() {
  local i="$1" pid="${U_ROOT[$1]}" avd="${U_LABEL[$1]%% *}" desc adb s serial="" w=0
  desc="idle-emulator (${U_NOTE[i]}): ${U_LABEL[i]}"
  if ! approved_pid "$pid"; then log "  [SKIP]    not in approved set  pid=$pid  $desc"; return 0; fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "  [DRY]     $(printf '%7s' "$((U_RSS[i]/1024)) MB")  pid=$pid  $desc"
    FREED_KB=$((FREED_KB + U_RSS[i])); KILL_COUNT=$((KILL_COUNT + 1)); return 0
  fi
  same_args "$pid" "${U_ARGS[i]}" || { log "  [GONE]    pid=$pid  $desc"; return 0; }
  adb="$(dev_adb "${U_ARGS[i]}")"
  if [[ -n "$adb" ]]; then
    for s in $(with_timeout 10 "$adb" devices 2>/dev/null | awk '/^emulator-[0-9]+[[:space:]]+device/ {print $1}'); do
      [[ "$(with_timeout 5 "$adb" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')" == "$avd" ]] && { serial="$s"; break; }
    done
    [[ -n "$serial" ]] && with_timeout 10 "$adb" -s "$serial" emu kill >/dev/null 2>&1
  fi
  while kill -0 "$pid" 2>/dev/null && [[ $w -lt 40 ]]; do sleep 1; w=$((w + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -TERM "$pid" 2>/dev/null; sleep 10; fi
  kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  log "  [QUIT]    $(printf '%7s' "$((U_RSS[i]/1024)) MB")  pid=$pid  $desc"
  FREED_KB=$((FREED_KB + U_RSS[i])); KILL_COUNT=$((KILL_COUNT + 1))
}

# quit_simulator <i> — `simctl shutdown` (the device and its data stay; it just stops running)
DEV_SIMS_SHUT=0
quit_simulator() {
  local i="$1" pid="${U_ROOT[$1]}" desc
  desc="idle-simulator (${U_NOTE[i]}): ${U_LABEL[i]}"
  if ! approved_pid "$pid"; then log "  [SKIP]    not in approved set  pid=$pid  $desc"; return 0; fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "  [DRY]     $(printf '%7s' "$((U_RSS[i]/1024)) MB")  pid=$pid  $desc"
    FREED_KB=$((FREED_KB + U_RSS[i])); KILL_COUNT=$((KILL_COUNT + 1)); return 0
  fi
  with_timeout 60 xcrun simctl shutdown "${U_ARGS[i]}" >/dev/null 2>&1
  log "  [QUIT]    $(printf '%7s' "$((U_RSS[i]/1024)) MB")  pid=$pid  $desc"
  FREED_KB=$((FREED_KB + U_RSS[i])); KILL_COUNT=$((KILL_COUNT + 1)); DEV_SIMS_SHUT=1
}

# dev_section <class…> — act on the judged units of these classes
dev_section() {
  local i cls found=0 want=" $* " desc
  for ((i = 0; i < DEV_N; i++)); do
    cls="${U_CLASS[i]}"; [[ "$want" == *" $cls "* ]] || continue
    found=1
    desc="${U_LABEL[i]} (${U_NOTE[i]:-busy}): ${U_ARGS[i]}"
    case "${U_VERDICT[i]}" in
      reap)
        case "$cls" in
          emulator)  quit_emulator "$i" ;;
          simulator) quit_simulator "$i" ;;
          daemon)    reap_tree "${U_ROOT[i]}" "${U_MEMBERS[i]}" "${U_RSS[i]}" "idle-$desc" "${U_ARGS[i]}" 10 ;;
          *)         reap_tree "${U_ROOT[i]}" "${U_MEMBERS[i]}" "${U_RSS[i]}" "idle-$desc" "${U_ARGS[i]}" ;;
        esac ;;
      busy)
        if [[ "$cls" == orphan && "$ORPHANS_ALL" -eq 1 && "${U_AGE[i]}" -ge 1800 ]]; then
          reap_tree "${U_ROOT[i]}" "${U_MEMBERS[i]}" "${U_RSS[i]}" "orphan: $desc" "${U_ARGS[i]}"
        else
          log "  [REPORT]  $(printf '%7s' "$((U_RSS[i]/1024)) MB")  pid=${U_ROOT[i]}  in use — $desc"
        fi ;;
      *)
        log "  [REPORT]  $(printf '%7s' "$((U_RSS[i]/1024)) MB")  pid=${U_ROOT[i]}  $desc" ;;
    esac
  done
  [[ $found -eq 0 ]] && log "  none found."
  return 0
}

[[ "$DEV_PASS_OK" -eq 1 ]] && dev_evaluate

# ---------- header ----------
log "=================================================================="
log " memory auto-clean  |  $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY')$([[ $DEV_ONLY -eq 1 ]] && echo '  |  dev pass')  |  ${TS_NOW}"
if [[ "$DEV_ONLY" -eq 1 ]]; then
  log " idle grace: devices ${DEV_DEVICE_IDLE_MIN}m  daemons $([[ $DEV_NOW -eq 1 ]] && echo 0 || echo "$DEV_DAEMON_IDLE_MIN")m  servers ${DEV_SERVER_IDLE_MIN}m/${DEV_ORPHAN_IDLE_MIN}m  orphans $([[ $DEV_NOW -eq 1 ]] && echo 0 || echo "$DEV_ORPHAN_IDLE_MIN")m$([[ "$DEV_STOP_IDLE_STACKS" == 1 ]] && echo "  stacks ${STACK_IDLE_MIN}m")"
else
  log " dev-age>${DEV_AGE_HOURS}h  pw-age>${PW_AGE_HOURS}h  orphans-all=${ORPHANS_ALL}"
fi
log " input: ${INVOKED}"
log "=================================================================="
BEFORE=""; [[ "$QUIET" -eq 0 ]] && BEFORE="$(before_state)"

# ---------- 1. Orphaned MCP servers (PPID=1 — parent session is gone) ----------
group "1. Orphaned MCP servers (parent Claude/VS Code session died)"
FOUND=0
while IFS=$'\t' read -r pid ppid rss age args; do
  [[ -z "${pid:-}" ]] && continue
  [[ "$ppid" -eq 1 ]] || continue
  reap "$pid" "$rss" "orphan-mcp: $args"; FOUND=1
done < <(candidates "$MCP_RE")
[[ "$FOUND" -eq 0 ]] && log "  none found — all MCP servers belong to live sessions."

# ---------- 2. Orphaned dev tooling (parent gone) ----------
group "2. Orphaned dev tooling (parent gone) — idle ≥$([[ $DEV_NOW -eq 1 ]] && echo 0 || echo "$DEV_ORPHAN_IDLE_MIN")m reaped, busy ones reported$([[ $ORPHANS_ALL -eq 1 ]] && echo '; --orphans-all: busy ones up >30min too')"
if [[ "$DEV_PASS_OK" -eq 1 ]]; then dev_section orphan; else log "  ${DEV_PASS_SKIPPED}"; fi

if [[ "$DEV_ONLY" -eq 0 ]]; then
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
fi   # end of the full-run-only sections 3–6

if [[ "$DEV_PASS_OK" -eq 1 ]]; then
# ---------- 7. Idle emulators & simulators ----------
group "7. Emulators & simulators idle ≥${DEV_DEVICE_IDLE_MIN}m (no build, test, driver, Metro activity or window focus) — shut down, data kept"
dev_section emulator simulator
# Simulator.app with no device left running holds memory for nothing
if [[ "$DEV_SIMS_SHUT" -eq 1 && -n "${DEV_FLAG[simapp]:-}" && "$DEV_FRONT" != Simulator ]] \
   && ! with_timeout 20 xcrun simctl list devices booted 2>/dev/null | grep -q '(Booted)'; then
  simapp_pid="${DEV_FLAG[simapp]}"
  simapp_kb="$(ps -o rss= -p "$simapp_pid" 2>/dev/null | tr -d ' ')"
  simapp_args="$(ps -o args= -p "$simapp_pid" 2>/dev/null)"
  if [[ "$simapp_args" == *Simulator.app/Contents/MacOS/Simulator* ]] \
     && ! grep -qE -- "$PROTECT_RE" <<<"$simapp_args" \
     && approved_pid "$simapp_pid" && kill -TERM "$simapp_pid" 2>/dev/null; then
    log "  [QUIT]    $(printf '%7s' "$(( ${simapp_kb:-0} / 1024 )) MB")  pid=$simapp_pid  Simulator app (no simulator left running)"
  fi
fi

# ---------- 8. Build daemons with no build running ----------
group "8. Gradle / Kotlin daemons idle ≥$([[ $DEV_NOW -eq 1 ]] && echo 0 || echo "$DEV_DAEMON_IDLE_MIN")m with NO Gradle build running anywhere"
dev_section daemon

# ---------- 9. Leftovers of finished / failed native builds ----------
group "9. Native-build leftovers (Xcode build helpers, emulator plumbing) — parent gone, idle"
dev_section buildleft plumbing

# ---------- 10. Idle dev servers ----------
group "10. Dev servers with no client and no activity — ${DEV_SERVER_IDLE_MIN}m while their project is open, ${DEV_ORPHAN_IDLE_MIN}m once not"
dev_section server
else
group "7–10. Idle emulators, build daemons, build leftovers and dev servers"
log "  ${DEV_PASS_SKIPPED}"
fi   # end of the sections that need bash 4+

# =================== 11. idle Docker / Supabase stacks (opt-in) ===================
# ANALYZERS_DEV_STOP_IDLE_STACKS=1: `docker stop` the containers of a stack whose project has had NO live
# claude/codex session for ANALYZERS_STACK_IDLE_MIN. Only stacks that map to a project are ever considered:
#   (a) Supabase CLI containers — label com.supabase.cli.project = the project_id of some repo's
#       supabase/config.toml (repos of live sessions first, then repos under ANALYZERS_STACK_REPO_ROOTS);
#   (b) Compose — label com.docker.compose.project.working_dir, resolved to its repo;
#   (c) ANALYZERS_STACK_OWNER_MAP (config.local.sh) for custom isolated stacks, "glob=project" entries.
# "Live" is a claude/codex session OR an interactive terminal shell whose cwd is in the project (a shell
# left in a repo keeps its stack up). It is the PROCESS cwd: a session rooted in repo A that drives repo B's
# stack by absolute path leaves B looking idle — map B to A in ANALYZERS_STACK_OWNER_MAP, or protect B.
# A stack can have several owners — the repo (a)/(b) finds AND every owner-map project; it is kept while ANY of
# them has a live session.
# A stack that maps to nothing (OrbStack's own Kubernetes containers included) is reported, never stopped.
# ANALYZERS_STACK_PROTECT always wins. Containers are stopped one at a time and are never removed; volumes,
# images and networks are never touched, Docker itself is never signalled or started.

# main_worktree <dir> — the main worktree's top level for a dir inside a repo or any of its linked
# worktrees (via the git common dir); empty when the dir is not in a repo
main_worktree() {
  local d="$1" common
  [[ -n "$d" && -d "$d" ]] || return 0
  common="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  [[ -n "$common" ]] || return 0
  case "$common" in */.git) printf '%s\n' "${common%/.git}" ;; *) printf '%s\n' "$common" ;; esac
}

# stack_scan_configs <root> — "project_id<TAB>root" for each supabase/config.toml inside a repo
stack_scan_configs() {
  local root="$1" cfg pid
  while IFS= read -r cfg; do
    [[ -n "$cfg" ]] || continue
    pid="$(awk -F'"' '/^project_id[[:space:]]*=/ { print $2; exit }' "$cfg" 2>/dev/null)"
    [[ -n "$pid" ]] && printf '%s\t%s\n' "$pid" "$root"
  done < <(find "$root" -maxdepth 4 -path '*/supabase/config.toml' -type f \
             -not -path '*/node_modules/*' -not -path '*/.composure/*' -not -path '*/.git/*' 2>/dev/null)
}

# stack_owners_for <id> — every owner project ANALYZERS_STACK_OWNER_MAP names for this stack id, one per line
stack_owners_for() {
  local id="$1" entry pat
  for entry in ${STACK_OWNER_MAP//,/ }; do
    pat="${entry%%=*}"; [[ "$entry" == *=* && -n "$pat" ]] || continue
    # shellcheck disable=SC2053
    [[ "$id" == $pat ]] && printf '%s\n' "${entry#*=}"
  done
  return 0
}

# stack_protected <id…> — 0 when any argument matches an ANALYZERS_STACK_PROTECT pattern
stack_protected() {
  local entry arg
  for entry in ${STACK_PROTECT//,/ }; do
    for arg in "$@"; do
      # shellcheck disable=SC2053
      [[ -n "$arg" && "$arg" == $entry ]] && return 0
    done
  done
  return 1
}

dev_idle_stacks() {
  if [[ "$DEV_STOP_IDLE_STACKS" != 1 ]]; then
    log "  off — opt in with ANALYZERS_DEV_STOP_IDLE_STACKS=1 (config.local.sh)."; return 0
  fi
  command -v docker >/dev/null 2>&1 || { log "  docker is not installed — nothing to do."; return 0; }
  # never start Docker: only look when its socket exists
  [[ -S "$HOME/.orbstack/run/docker.sock" || -S /var/run/docker.sock ]] \
    || { log "  Docker is not running — nothing to do."; return 0; }
  local ps_out
  ps_out="$(with_timeout 15 docker ps --format '{{.ID}}|{{.Names}}|{{.Label "com.supabase.cli.project"}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}|{{.Label "io.kubernetes.pod.name"}}' 2>/dev/null)" \
    || { log "  Docker is not answering — nothing to do."; return 0; }
  if [[ -z "$ps_out" ]]; then log "  no containers running."; return 0; fi

  # ---- live projects: the main worktree of each live claude/codex session's cwd AND of each interactive
  # terminal shell's cwd (a linked worktree counts as its repo). Who is looking is kept for the report.
  local -A LIVE_PATH=() LIVE_SRC=() LIVE_NSRC=() PID_ROOT=() ST_KIND=() ST_ID=() ST_WD=() ST_CIDS=() ST_N=()
  local -a ST_KEYS=()
  local sroot cwd root unresolved=0
  stack_mark_live() {  # <root> <source>
    local r="$1" src="$2" nm="${1##*/}"
    LIVE_PATH[$r]=1
    [[ " ${LIVE_SRC[$r]:-} " == *" $src "* ]] || LIVE_SRC[$r]="${LIVE_SRC[$r]:+${LIVE_SRC[$r]} }$src"
    [[ " ${LIVE_NSRC[$nm]:-} " == *" $src "* ]] || LIVE_NSRC[$nm]="${LIVE_NSRC[$nm]:+${LIVE_NSRC[$nm]} }$src"
  }
  for sroot in $DEV_SESSION_ROOTS; do
    cwd="${DEV_CWD[$sroot]:-}"
    if [[ -z "$cwd" ]]; then unresolved=$((unresolved + 1)); continue; fi   # lookup failed: unknown project
    root="$(main_worktree "$cwd")"
    [[ -n "$root" ]] && stack_mark_live "$root" claude
  done
  # a plain terminal with no AI session: `supabase start` run by hand keeps its stack alive
  for sroot in $(echo "$DSNAP" | awk -F'\t' '$3 != "??" && $8 ~ /^-?(zsh|bash|fish|sh)( |$)|^\/bin\/(zsh|bash|sh)( |$)/ {print $1}'); do
    cwd="${DEV_CWD[$sroot]:-}"; [[ -n "$cwd" ]] || continue
    root="$(main_worktree "$cwd")"
    [[ -n "$root" ]] && stack_mark_live "$root" terminal
  done

  # ---- group containers into stacks
  local cid name sb cp wd k8s key kind id
  while IFS='|' read -r cid name sb cp wd k8s; do
    [[ -n "$cid" ]] || continue
    if [[ -n "$sb" ]]; then key="supabase:$sb"; kind=supabase; id="$sb"
    elif [[ -n "$cp" ]]; then key="compose:$cp"; kind=compose; id="$cp"
    elif [[ -n "$k8s" || "$name" == k8s_* ]]; then key="orbstack-k8s"; kind=k8s; id="orbstack-k8s"
    else key="container:$name"; kind=container; id="$name"; fi
    if [[ -z "${ST_KIND[$key]+x}" ]]; then ST_KEYS+=("$key"); ST_KIND[$key]="$kind"; ST_ID[$key]="$id"; ST_WD[$key]="$wd"; ST_N[$key]=0; ST_CIDS[$key]=""; fi
    ST_CIDS[$key]+=" $cid"; ST_N[$key]=$((ST_N[$key] + 1))
  done <<< "$ps_out"

  # ---- supabase project_id -> repo: live sessions' repos first, the configured roots only if still needed
  local need=0 pid r d
  for key in "${ST_KEYS[@]}"; do [[ "${ST_KIND[$key]}" == supabase ]] && need=1; done
  if [[ $need -eq 1 ]]; then
    for root in "${!LIVE_PATH[@]}"; do
      while IFS=$'\t' read -r pid r; do [[ -n "$pid" && -z "${PID_ROOT[$pid]+x}" ]] && PID_ROOT[$pid]="$r"; done < <(stack_scan_configs "$root")
    done
    local unresolved_pid=0
    for key in "${ST_KEYS[@]}"; do
      [[ "${ST_KIND[$key]}" == supabase && -z "${PID_ROOT[${ST_ID[$key]}]+x}" ]] && unresolved_pid=1
    done
    if [[ $unresolved_pid -eq 1 ]]; then
      for r in ${STACK_REPO_ROOTS}; do
        [[ -d "$r" ]] || continue
        while IFS= read -r d; do
          d="${d%/.git}"
          while IFS=$'\t' read -r pid root; do [[ -n "$pid" && -z "${PID_ROOT[$pid]+x}" ]] && PID_ROOT[$pid]="$root"; done < <(stack_scan_configs "$d")
        done < <(find "$r" -maxdepth 3 -name .git -type d -prune 2>/dev/null)
      done
    fi
  fi

  # ---- judge each stack; remember when it was first seen orphaned
  declare -A PREV=()
  local first state_tmp="${STACK_STATE_FILE}.tmp.$$" ts_key ts_val
  if [[ -f "$STACK_STATE_FILE" ]]; then
    while IFS=$'\t' read -r ts_key ts_val; do [[ -n "$ts_key" && -n "$ts_val" ]] && PREV[$ts_key]="$ts_val"; done < "$STACK_STATE_FILE"
  fi
  : > "$state_tmp"
  local live n idle_s stopped failed left budget_end c shown auto auto_how owner owners_txt names isl i
  local -a o_name=() o_how=() o_live=()
  for key in "${ST_KEYS[@]}"; do
    id="${ST_ID[$key]}"; kind="${ST_KIND[$key]}"; n="${ST_N[$key]}"
    o_name=(); o_how=(); o_live=(); live=0; auto=""; auto_how=""
    # a stack can have several owners — the repo discovery finds (project_id / compose working_dir) AND every
    # ANALYZERS_STACK_OWNER_MAP project; it is kept while ANY of them has a live session
    case "$kind" in
      supabase) [[ -n "${PID_ROOT[$id]+x}" ]] && { auto="${PID_ROOT[$id]}"; auto_how="project_id in ${auto##*/}/supabase/config.toml"; } ;;
      compose)  [[ -n "${ST_WD[$key]}" ]] && { auto="$(main_worktree "${ST_WD[$key]}")"; [[ -n "$auto" ]] && auto_how="compose working_dir"; } ;;
    esac
    if [[ -n "$auto" ]]; then
      o_name+=("${auto##*/}"); o_how+=("$auto_how"); o_live+=("${LIVE_SRC[$auto]:-}")
    fi
    if [[ "$kind" != k8s ]]; then
      while IFS= read -r owner; do
        [[ -n "$owner" ]] || continue
        [[ "${owner##*/}" == "${auto##*/}" ]] && continue          # the same project twice
        isl="${LIVE_SRC[$owner]:-${LIVE_NSRC[${owner##*/}]:-}}"
        o_name+=("${owner##*/}"); o_how+=("owner map"); o_live+=("$isl")
      done < <(stack_owners_for "$id")
    fi
    owners_txt=""; names=""
    for ((i = 0; i < ${#o_name[@]}; i++)); do
      owners_txt+="${owners_txt:+; }${o_name[i]} (${o_how[i]}): $([[ -n "${o_live[i]}" ]] && echo "live (${o_live[i]// /, })" || echo 'no session')"
      names+=" ${o_name[i]}"; [[ -n "${o_live[i]}" ]] && live=1
    done
    shown="$key  ${n} container$([[ $n -ne 1 ]] && echo s)"

    # shellcheck disable=SC2086
    if stack_protected "$id" "$key" $names; then
      log "  [REPORT]  ${shown}  owners=${owners_txt:-(none)}  — keep: on ANALYZERS_STACK_PROTECT"; continue
    fi
    if [[ ${#o_name[@]} -eq 0 ]]; then
      log "  [REPORT]  ${shown}  owners=(unmapped)  — keep: an unmapped stack is never stopped"; continue
    fi
    if [[ $live -eq 1 ]]; then
      log "  [REPORT]  ${shown}  owners=${owners_txt}  — keep: an owner has a live session"; continue
    fi
    if [[ $unresolved -gt 0 ]]; then
      log "  [REPORT]  ${shown}  owners=${owners_txt}  live session: unknown  — keep: ${unresolved} live session(s) could not be placed in a project"; continue
    fi
    first="${PREV[$key]:-$NOW_TS}"
    [[ "$DRY_RUN" -eq 1 ]] || printf '%s\t%s\n' "$key" "$first" >> "$state_tmp"   # a preview never starts the clock
    idle_s=$((NOW_TS - first))
    local since; since="$(date -r "$first" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    if (( idle_s < STACK_IDLE_MIN * 60 )); then
      log "  [REPORT]  ${shown}  owners=${owners_txt}  orphaned since ${since}$([[ -z "${PREV[$key]:-}" && "$DRY_RUN" -eq 1 ]] && echo ' (first sighting; a dry run does not start the clock)') ($((idle_s / 60))m of ${STACK_IDLE_MIN}m)  — keep: grace"; continue
    fi
    # a stack is reviewed as a row keyed `stack:<key>` (never a pid); with a list it is
    # stopped only when that key is in it, with no list (the guard, a Terminal run) as always
    if ! approved_pid "stack:${key}"; then
      log "  [SKIP]    not in approved set  stack=${key}  ${shown}  owners=${owners_txt}"; continue
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [DRY]     stack=${key}  ${shown}  owners=${owners_txt}  orphaned since ${since} ($((idle_s / 60))m)  — would stop (containers kept, volumes untouched)"
      KILL_COUNT=$((KILL_COUNT + 1)); continue
    fi
    stopped=0; failed=0; left=0; budget_end=$((SECONDS + STACK_STOP_BUDGET_S))
    for c in ${ST_CIDS[$key]}; do
      # one container at a time (a batched multi-id stop was rejected by OrbStack), 20 s grace each, and a time
      # budget per stack so a wedged container cannot hold the guard's pass for minutes: the rest wait for the next pass
      if (( SECONDS >= budget_end )); then left=$((left + 1)); continue; fi
      if with_timeout 45 docker stop -t 20 "$c" >/dev/null 2>&1; then stopped=$((stopped + 1)); else failed=$((failed + 1)); fi
    done
    log "  [QUIT]    stack=${key}  ${shown}  owners=${owners_txt}  orphaned since ${since} ($((idle_s / 60))m)  — stopped ${stopped}/${n}$([[ $failed -gt 0 ]] && echo ", ${failed} failed")$([[ $left -gt 0 ]] && echo ", ${left} left for the next pass (time budget)") (containers kept, volumes untouched)"
    [[ $stopped -gt 0 ]] && KILL_COUNT=$((KILL_COUNT + 1))
  done
  if [[ "$DRY_RUN" -eq 1 ]]; then rm -f "$state_tmp"; else mv -f "$state_tmp" "$STACK_STATE_FILE"; fi
  return 0
}

if [[ "$DEV_ONLY" -eq 1 && "$DEV_PASS_OK" -eq 1 ]]; then
  group "11. Docker / Supabase stacks of projects with no live session for ${STACK_IDLE_MIN}m — containers stopped, never removed, volumes untouched"
  dev_idle_stacks
fi

# ---------- summary ----------
# --quiet with nothing reaped: no log entry, no notification
if [[ "$QUIET" -eq 1 && "$KILL_COUNT" -eq 0 ]]; then exit 0; fi
log ""
log "=================================================================="
if [[ "$DRY_RUN" -eq 1 ]]; then
  log " DRY RUN — would reap ${KILL_COUNT} process(es), ~$((FREED_KB/1024)) MB resident. Re-run with --apply."
  [[ "$QUIET" -eq 1 ]] || notify "Memory auto-clean (dry run)" "Would reap ${KILL_COUNT} process(es), ~$((FREED_KB/1024)) MB resident."
else
  log " DONE — reaped ${KILL_COUNT} process(es), ~$((FREED_KB/1024)) MB resident."
  if [[ "$QUIET" -eq 0 && "$DEV_ONLY" -eq 1 && "$KILL_COUNT" -eq 0 ]]; then
    :   # nothing stopped — no before/after, no notification
  elif [[ "$QUIET" -eq 0 ]]; then
    log ""
    log " Before: ${BEFORE}"
    sleep 5
    log " After:  $(before_state)"
    log " (compressor + swap held by reaped processes drains over the next minutes)"
    notify "Memory auto-clean" "Reaped ${KILL_COUNT} process(es), ~$((FREED_KB/1024)) MB resident."
  elif [[ "$FREED_KB" -ge 524288 ]] && [[ ! -e "$DEV_NOTIFY_STAMP" || $((NOW_TS - $(stat -f %m "$DEV_NOTIFY_STAMP" 2>/dev/null || echo 0))) -ge 600 ]]; then
    # the frequent dev pass speaks up only for a sizeable reclaim, at most every 10 min
    touch "$DEV_NOTIFY_STAMP"
    notify "Memory auto-clean" "Stopped idle dev tooling — ~$((FREED_KB/1024)) MB back."
  fi
fi
log "=================================================================="
if [[ "$QUIET" -eq 1 ]]; then printf '%s' "$LOG_BUF" | tee -a "$LOG_FILE"; fi

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
