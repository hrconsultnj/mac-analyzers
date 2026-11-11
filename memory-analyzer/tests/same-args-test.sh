#!/usr/bin/env bash
# same-args-test.sh — regression test for the same_args pid-recycling guard in
# memory-auto-clean.sh. Starts harmless stand-in processes of its own (a node
# that rewrites process.title like npm does) and never touches anything else.
# Usage: memory-analyzer/tests/same-args-test.sh
# macOS only: it asserts what macOS `ps` prints for a process that renamed
# itself. scripts/check.sh reports it as "not run" anywhere else.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../memory-auto-clean.sh"
command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
eval "$(sed -n '/^same_args() {/,/^}/p' "$SCRIPT")"

TMP="$(mktemp -d)"; PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
fail=0
check() { # name expected(0=match) actual-rc
  if { [[ $2 -eq 0 && $3 -eq 0 ]] || [[ $2 -ne 0 && $3 -ne 0 ]]; }; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi
}

TITLE='npm exec expo start --port 8081 --dev-client'
# 1. padded title (script name longer than the title → trailing space in ps)
LONG="$TMP/a_long_script_name_to_make_room_for_the_title_abcdefghijklmnopqrstuvwxyz_0123456789.js"
# 2. short argv area → title cut short, env strings follow in ps
SHORT="$TMP/t.js"
for f in "$LONG" "$SHORT"; do echo "process.title='$TITLE'; setInterval(()=>{},1000);" > "$f"; done
FOO=barbarbarbarbarbar node "$LONG" & P1=$!; PIDS="$PIDS $P1"
TERM_SESSION_ID=abcdefabcdefabcdefabcdef node "$SHORT" & P2=$!; PIDS="$PIDS $P2"
sleep 1

# snapshot as dev_build_units sees it: awk-rebuilt (trimmed) args
snap() { ps -o args= -p "$1" | awk '{$1=$1; print}' | cut -c1-200; }
S1="$(snap "$P1")"; S2="$(snap "$P2")"
echo "live#1=[$(ps -o args= -p "$P1")]  snap#1=[$S1]"
echo "live#2=[$(ps -o args= -p "$P2")]  snap#2=[$S2]"

same_args "$P1" "$S1"; check "live process, trailing-space title, recognised" 0 $?
same_args "$P2" "$S2"; check "live process, env tail after title, recognised" 0 $?
same_args "$P2" "$TITLE"; check "live process, snapshot shorter than live (env tail), recognised" 0 $?
same_args "$P1" "node /some/other/server.js --port 3000"; check "recycled pid, different args -> GONE" 1 $?
same_args "$P1" "npm exec expo start --port 9999 --dev-client"; check "recycled pid, differing flag -> GONE" 1 $?
same_args "$P2" "npm exe"; check "mid-word prefix rejected" 1 $?
kill "$P1"; wait "$P1" 2>/dev/null
same_args "$P1" "$S1"; check "dead pid -> GONE" 1 $?
exit $fail
