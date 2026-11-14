#!/usr/bin/env bash
# guard-exemption-test.sh — the memory guard's live-session exemption covers EVERY agent in lib/coding-agents.tsv, fails
# closed when that list cannot be read, and honours what the rules engine writes for it (Never Close paths, matched as
# plain text). Judged on a stand-in process table (a fake `ps`); it signals nothing except one `sleep` it starts itself.
# Runs under bash and /bin/bash (3.2).   Usage: memory-analyzer/tests/guard-exemption-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TMP="$(mktemp -d)"; CHILD=""
cleanup() { [[ -n "$CHILD" ]] && kill "$CHILD" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }

# the guard's own patterns, read from the script (never copied here)
KILLABLE_RE="$(sed -n "s/^KILLABLE_RE='\(.*\)'$/\1/p" "$ROOT/memory-analyzer/memory-guard.sh")"
PROTECT_RE="$(sed -n "s/^PROTECT_RE='\(.*\)'$/\1/p" "$ROOT/memory-analyzer/memory-guard.sh")"
[[ -n "$KILLABLE_RE" && -n "$PROTECT_RE" ]] || { echo "FAIL  could not read the guard's patterns"; exit 1; }

# a fake process table: ps axo pid=,args= / pid=,ppid= / pid=,rss=,args=
ARGS="$TMP/args.txt"; PPID_T="$TMP/ppid.txt"; RSS="$TMP/rss.txt"
ps() {
  case "$*" in
    "axo pid=,args=") cat "$ARGS" ;;
    "axo pid=,ppid=") cat "$PPID_T" ;;
    "axo pid=,rss=,args=") cat "$RSS" ;;
    *) command ps "$@" ;;
  esac
}

# shellcheck source=../../lib/live-sessions.sh
source "$ROOT/lib/live-sessions.sh" || { echo "FAIL  live-sessions.sh did not load"; exit 1; }
# shellcheck source=../../lib/guard-select.sh
source "$ROOT/lib/guard-select.sh"

: > "$ARGS"; : > "$PPID_T"; : > "$RSS"
add() { # pid ppid rss_kb args...
  local pid="$1" parent="$2" rss="$3"; shift 3
  echo "$pid $*" >> "$ARGS"; echo "$pid $parent" >> "$PPID_T"; echo "$pid $rss $*" >> "$RSS"
}

# one session per agent line of the list: its root, an MCP server it started (a node program), and a command below that
pid=1000; roots=""
while IFS=$'\t' read -r agent kind text also; do
  case "$agent" in "#"*|"") continue ;; esac
  [[ "$kind" == "exe" || "$kind" == "fragment" ]] || continue
  case "$kind" in
    exe) line="/opt/tools/bin/$text --session abc" ;;
    *) if [[ "$text" == *.app* ]]; then line="/Applications/$text/Contents/MacOS/zz ${also:-} --x"
       elif [[ "$text" == *" "* ]]; then line="/Users/x/Library/${text}zz.app/Contents/MacOS/zz ${also:-} --x"   # an app path holds spaces
       else line="/opt/x/$text/zz ${also:-} --x"; fi ;;
  esac
  root=$pid; add "$root" 1 400000 "$line"
  add $((pid + 1)) "$root" 800000 node /opt/mcp/server-for-"$root"/index.js
  add $((pid + 2)) $((pid + 1)) 900000 /bin/zsh -c "sleep 1000 # below $root"
  add $((pid + 3)) $((pid + 2)) 900000 node /opt/work/dev-server-for-"$root".js
  roots="$roots $root"
  pid=$((pid + 10))
done < "$ROOT/lib/coding-agents.tsv"

# the same program with no session above it, and others
add 9000 1 700000 node /Users/x/orphan/server.js
add 9001 1 700000 npx vite
add 9002 1 400000 /Applications/Visual\ Studio\ Code.app/Contents/MacOS/Electron
add 9003 1 400000 /usr/sbin/mds

sessions="$(awk -F'\t' '/^#/ || NF < 3 {next} $2 == "exe" || $2 == "fragment" {print $1}' "$ROOT/lib/coding-agents.tsv" | sort -u | wc -l | tr -d ' ')"
found_roots="$(live_session_roots)"
missing=""
for r in $roots; do case " $found_roots " in *" $r "*) ;; *) missing="$missing $r" ;; esac; done
check "every line of the agent list gives a session root ($sessions agents)" "$([[ -z "$missing" ]] && echo ok || echo "not recognised:$missing")"

exempt="$(live_session_exempt | tr '\n' ' ')"
cand="$(command -v cat >/dev/null; cat "$RSS" | guard_select_candidates "$KILLABLE_RE" "$PROTECT_RE" 1 "$exempt" "")"
leaked=""
for r in $roots; do
  for off in 0 1 2 3; do
    printf '%s\n' "$cand" | cut -f1 | grep -qx "$((r + off))" && leaked="$leaked $((r + off))"
  done
done
check "no session root and nothing below it is a candidate, for any agent" "$([[ -z "$leaked" ]] && echo ok || echo "still candidates:$leaked")"
check "the MCP server and dev server of a session are candidates WITHOUT the exemption (the test is not vacuous)" \
  "$(cat "$RSS" | guard_select_candidates "$KILLABLE_RE" "$PROTECT_RE" 1 "" "" | cut -f1 | grep -qx "1001" && echo ok || echo "1001 not a candidate")"
check "an orphaned node and an orphaned vite are still candidates" \
  "$(printf '%s\n' "$cand" | cut -f1 | grep -cE '^(9000|9001)$' | grep -qx 2 && echo ok || echo "got: $(printf '%s' "$cand" | cut -f1 | tr '\n' ' ')")"
check "a protected app and a system process are not candidates" \
  "$(printf '%s\n' "$cand" | cut -f1 | grep -qE '^(9002|9003)$' && echo "a protected process is a candidate" || echo ok)"

# an unreadable list: sourcing the exemption refuses, and the guard must stop nothing
mkdir -p "$TMP/lib2"; cp "$ROOT/lib/live-sessions.sh" "$TMP/lib2/"
( source "$TMP/lib2/live-sessions.sh" ) >/dev/null 2>&1; rc=$?
check "without lib/coding-agents.tsv the exemption refuses to load" "$([[ $rc -ne 0 ]] && echo ok || echo "loaded")"
printf '# only comments\n' > "$TMP/lib2/coding-agents.tsv"
( source "$TMP/lib2/live-sessions.sh" ) >/dev/null 2>&1; rc=$?
check "a list that names no agent refuses to load" "$([[ $rc -ne 0 ]] && echo ok || echo "loaded")"

# kill_proc fails closed: taken from the guard script itself, run against one sleep this test started
eval "$(sed -n '/^kill_proc() {/,/^}/p' "$ROOT/memory-analyzer/memory-guard.sh")"
eval "$(sed -n '/^short_name() {/,/^}/p' "$ROOT/memory-analyzer/memory-guard.sh")"
LOGOUT="$TMP/log.txt"; : > "$LOGOUT"
log() { echo "$*" >> "$LOGOUT"; }
notify() { :; }
command sleep 300 & CHILD=$!
export LIVE_SESSIONS_OK=0   # read by kill_proc, which is evaluated from the guard script
kill_proc "$CHILD" 100000 "hard-cap test" "node stand-in" >/dev/null 2>&1
check "with the agent list unreadable the guard stops nothing and says so" \
  "$(kill -0 "$CHILD" 2>/dev/null && grep -q 'KILL-SKIPPED' "$LOGOUT" && echo ok || echo "child gone or no log line")"
export LIVE_SESSIONS_OK=1
kill_proc "$CHILD" 100000 "hard-cap test" "node stand-in" >/dev/null 2>&1
wait "$CHILD" 2>/dev/null
check "with the list readable the same call stops the stand-in (the exemption was the only difference)" \
  "$(kill -0 "$CHILD" 2>/dev/null && echo "still running" || echo ok)"
CHILD=""

# what the rules engine writes: Never Close paths are plain text, tunables are read back, a missing file changes nothing
FB="$TMP/fallback.tsv"
printf 'hardCapMB\t8192\nhardCapStop\t1\npressureStop\t0\nneverClosePath\t/Users/x/bin/my.server[1](x)+\nneverClosePath\t/Users/x/bin/other\npause\t0\n' > "$FB"
: > "$RSS"
add 7000 1 700000 node '/Users/x/bin/my.server[1](x)+' --serve
add 7001 1 700000 node /Users/x/bin/myXserver1 --serve
add 7002 1 700000 /Users/x/bin/other --run jest
add 7003 1 700000 node /Users/x/bin/not-listed.js
# the Never Close path is where the program IS (its own path starts the command), so a command that merely mentions it is not protected
add 7004 1 700000 /Users/x/bin/runner jest /Users/x/bin/other
pids() { cut -f1 | tr '\n' ' '; }
with="$(cat "$RSS" | guard_select_candidates "$KILLABLE_RE" "$PROTECT_RE" 1 "" "$FB" | pids)"
check "a Never Close path holding regex characters protects exactly that path" \
  "$([[ "$with" != *7000* && "$with" == *7001* ]] && echo ok || echo "candidates: $with")"
check "a Never Close path with its arguments is protected, an unlisted program is not" \
  "$([[ "$with" != *7002* && "$with" == *7003* && "$with" == *7004* ]] && echo ok || echo "candidates: $with")"
without="$(cat "$RSS" | guard_select_candidates "$KILLABLE_RE" "$PROTECT_RE" 1 "" "$TMP/nothing.tsv" | pids)"
check "with no fallback file every one of them is a candidate, as before" \
  "$([[ "$without" == *7000* && "$without" == *7002* ]] && echo ok || echo "candidates: $without")"
check "the guard reads back the values the engine wrote" \
  "$([[ "$(guard_fallback_value "$FB" hardCapMB)" == 8192 && "$(guard_fallback_value "$FB" pressureStop)" == 0 && -z "$(guard_fallback_value "$FB" nosuchkey)" && -z "$(guard_fallback_value "$TMP/none" hardCapMB)" ]] && echo ok || echo "wrong values")"
exit "$fail"
