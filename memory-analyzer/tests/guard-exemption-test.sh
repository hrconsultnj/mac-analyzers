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

# kill_proc asks again AT THE MOMENT of the stop: the list was readable at start and is gone now
command sleep 300 & CHILD=$!
export LIVE_SESSIONS_OK=1
REAL_LIST="$_LIVE_SESSION_LIST"
_LIVE_SESSION_LIST="$TMP/vanished.tsv"
: > "$LOGOUT"
kill_proc "$CHILD" 100000 "hard-cap test" "node stand-in" >/dev/null 2>&1
check "a list that is gone at the moment of the stop stops nothing, though it was readable at start" \
  "$(kill -0 "$CHILD" 2>/dev/null && grep -q 'KILL-SKIPPED' "$LOGOUT" && echo ok || echo "child gone or no log line")"
printf '# no agent here\n' > "$TMP/empty.tsv"; _LIVE_SESSION_LIST="$TMP/empty.tsv"; : > "$LOGOUT"
kill_proc "$CHILD" 100000 "hard-cap test" "node stand-in" >/dev/null 2>&1
check "a list that names no agent at the moment of the stop stops nothing" \
  "$(kill -0 "$CHILD" 2>/dev/null && grep -q 'KILL-SKIPPED' "$LOGOUT" && echo ok || echo "child gone or no log line")"
_LIVE_SESSION_LIST="$REAL_LIST"
kill_proc "$CHILD" 100000 "hard-cap test" "node stand-in" >/dev/null 2>&1
wait "$CHILD" 2>/dev/null
check "with the list readable the same call stops the stand-in" "$(kill -0 "$CHILD" 2>/dev/null && echo "still running" || echo ok)"
CHILD=""

# what the app writes for the scripts: the Never Close list (names and paths, plain text) and a pause. It can only narrow.
FB="$TMP/fallback.tsv"
printf 'neverClosePath\t/Users/x/bin/my.server[1](x)+\nneverClosePath\t/Users/x/bin/other\nneverCloseName\tserver\nneverCloseName\tFoo\nneverCloseName\ta.b[1]\nneverCloseName\tsvc\nneverCloseName\tapi\nneverClosePath\t/Users/x/web/Server.ts\npause\t0\n' > "$FB"
: > "$RSS"
add 7000 1 700000 node '/Users/x/bin/my.server[1](x)+' --serve
add 7001 1 700000 node /Users/x/bin/myXserver1 --serve
add 7002 1 700000 /Users/x/bin/other --run jest
add 7003 1 700000 node /Users/x/bin/not-listed.js
add 7004 1 700000 /Users/x/bin/runner jest --watch tests /Users/x/bin/other
add 7005 1 700000 node /Users/x/web/server.js
add 7006 1 700000 node /Applications/Foo.app/Contents/Resources/work.js
add 7007 1 700000 node /x/a.b[1]
add 7008 1 700000 node /x/aXb1
add 7009 1 700000 node /Users/x/other/app.js
add 7010 1 700000 node --inspect-brk=9229 --max-old-space-size=4096 /x/svc.js
add 7011 1 700000 bun run /x/api.ts
add 7012 1 700000 node --inspect /Users/x/web/Server.ts
add 7013 1 700000 node --trace-warnings /x/unlisted.js
pids() { cut -f1 | tr '\n' ' '; }
with="$(cat "$RSS" | guard_select_candidates "$KILLABLE_RE" "$PROTECT_RE" 1 "" "$FB" | pids)"
check "a Never Close path holding regex characters protects exactly that path" \
  "$([[ "$with" != *7000* && "$with" == *7001* ]] && echo ok || echo "candidates: $with")"
check "a path with its arguments is protected; a command that only mentions it, and an unlisted program, are not" \
  "$([[ "$with" != *7002* && "$with" == *7003* && "$with" == *7004* ]] && echo ok || echo "candidates: $with")"
check "a Never Close NAME protects the program (or the script an interpreter runs) of that name" \
  "$([[ "$with" != *7005* && "$with" == *7009* ]] && echo ok || echo "candidates: $with")"
check "the script is found after interpreter flags and a subcommand (node --inspect x.js, bun run x.ts), by name and by path" \
  "$([[ "$with" != *7010* && "$with" != *7011* && "$with" != *7012* && "$with" == *7013* ]] && echo ok || echo "candidates: $with")"
check "a name protects an app bundle of that name" "$([[ "$with" != *7006* ]] && echo ok || echo "candidates: $with")"
check "a name holding regex characters protects exactly itself" "$([[ "$with" != *7007* && "$with" == *7008* ]] && echo ok || echo "candidates: $with")"
without="$(cat "$RSS" | guard_select_candidates "$KILLABLE_RE" "$PROTECT_RE" 1 "" "$TMP/nothing.tsv" | pids)"
check "with no file every one of them is a candidate, as before" \
  "$([[ "$without" == *7000* && "$without" == *7002* && "$without" == *7005* && "$without" == *7006* && "$without" == *7010* && "$without" == *7011* && "$without" == *7012* ]] && echo ok || echo "candidates: $without")"

# a hostile or stale file cannot widen anything: no line with a stray field, a carriage return or a key it does not know counts
printf 'neverClosePath\t/Users/x/bin/other\textra\nneverCloseName\tserver\r\nhardCapStop\t1\nneverClosePath\n  neverCloseName\tFoo\nneverClosePath\trelative/path\n' > "$TMP/hostile.tsv"
hostile="$(cat "$RSS" | guard_select_candidates "$KILLABLE_RE" "$PROTECT_RE" 1 "" "$TMP/hostile.tsv" | pids)"
check "a line with a stray field, a carriage return, an unknown key or a path that is not full protects nothing" \
  "$([[ "$hostile" == "$without" ]] && echo ok || echo "candidates: $hostile (expected $without)")"

# the numbers come from config.local.sh alone: a file that lowers the cap or switches a stop on loses
eval "$(sed -n '/^read_fallback() {/,/^}/p' "$ROOT/memory-analyzer/memory-guard.sh")"
printf 'hardCapMB\t1\nhardCapStop\t1\npressureStop\t1\npause\t0\nneverClosePath\t/x\n' > "$TMP/tries.tsv"
export FALLBACK_FILE="$TMP/tries.tsv" GUARD_SELECT_OK=1   # read by read_fallback, which is evaluated from the guard script
HARD_CAP_MB=6144; HARDCAP_KILL=0; PRESSURE_KILL=0; FALLBACK_PAUSE=0
read_fallback
check "a file that tries to lower the cap to 1 MB and switch both stops on changes none of them" \
  "$([[ "$HARD_CAP_MB" == 6144 && "$HARDCAP_KILL" == 0 && "$PRESSURE_KILL" == 0 ]] && echo ok || echo "cap=$HARD_CAP_MB hardcap=$HARDCAP_KILL pressure=$PRESSURE_KILL")"
printf 'pause\t1\n' > "$TMP/pause.tsv"; export FALLBACK_FILE="$TMP/pause.tsv"; read_fallback
check "a pause in the file pauses the guard" "$([[ "$FALLBACK_PAUSE" == 1 ]] && echo ok || echo "not paused")"
printf 'pause\t0\n' > "$TMP/pause.tsv"; read_fallback
check "and no pause in the file lifts it again" "$([[ "$FALLBACK_PAUSE" == 0 ]] && echo ok || echo "still paused")"
printf 'pause\t1\r\n' > "$TMP/pause.tsv"; read_fallback
check "a pause line with a carriage return is not a pause" "$([[ "$FALLBACK_PAUSE" == 0 ]] && echo ok || echo "paused")"
check "the guard reads back what the app wrote, and nothing for a missing key or file" \
  "$([[ "$(guard_fallback_value "$FB" pause)" == 0 && -z "$(guard_fallback_value "$FB" nosuchkey)" && -z "$(guard_fallback_value "$TMP/none" pause)" ]] && echo ok || echo "wrong values")"

# the cleanups honour the same file: memory-auto-clean.sh's own candidates() with the pids the file protects, and the helpers
SNAP="$(printf '7100\t1\t700000\t3600\tnode /Users/x/a/server.js\n7101\t1\t700000\t3600\tnode /Users/x/b/app.js\n7102\t1\t700000\t3600\t/Users/x/bin/other --x node\n')"
eval "$(sed -n '/^candidates() {/,/^}/p' "$ROOT/memory-analyzer/memory-auto-clean.sh")"
NEVER_PIDS="$(echo "$SNAP" | guard_never_pids "$FB" 5 | tr '\n' ' ')"
cleaned="$(candidates 'node' | pids)"
check "the cleanup's candidate list leaves out what the Never Close list protects (by name and by path)" \
  "$([[ "$NEVER_PIDS" == *7100* && "$NEVER_PIDS" == *7102* && "$NEVER_PIDS" != *7101* && "$cleaned" == *7101* && "$cleaned" != *7100* && "$cleaned" != *7102* ]] && echo ok || echo "protected: $NEVER_PIDS, candidates: $cleaned")"
guard_is_never_closed "$FB" "/Users/x/bin/other --run"; yes=$?
guard_is_never_closed "$FB" "/Users/x/bin/else --run"; no=$?
guard_is_never_closed "$TMP/none" "/Users/x/bin/other --run"; nofile=$?
check "a single command line is checked the same way (the cleanups use it for a simulator and for what they quit)" \
  "$([[ $yes -eq 0 && $no -ne 0 && $nofile -ne 0 ]] && echo ok || echo "yes=$yes no=$no nofile=$nofile")"
for script in memory-auto-clean.sh memory-reclaim.sh; do
  check "$script reads the Never Close list" "$(grep -q 'guard-select.sh' "$ROOT/memory-analyzer/$script" && grep -q 'NEVER_FILE' "$ROOT/memory-analyzer/$script" && echo ok || echo "not wired")"
done
exit "$fail"
