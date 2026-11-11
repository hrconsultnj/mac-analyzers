#!/usr/bin/env bash
# approved-list-process-test.sh — a reviewed list can name a process by pid AND start time
# (`<pid><TAB><start>`), and the engine approves the pid only while the process running under it
# is the one that started then. A pid the system has since given to another program is not
# approved; a bare `<pid>` line (a list from an older app) still is.
#
# Stand-in processes only: two `sleep`s this test starts and ends itself; nothing is stopped
# and nothing is read of the person's. Runs under /bin/bash (3.2) and, when there is one, bash 5.
#
# Usage: tests/approved-list-process-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib/approved-list.sh"
[[ -f "$LIB" ]] || { echo "SKIP: lib/approved-list.sh not found"; exit 0; }

TMP="$(mktemp -d /tmp/mal.XXXXXX)"
# The stand-ins keep no pipe open (a caller reading our output through `tail` would otherwise wait for them),
# and the exit trap ends BOTH and waits, so none is left running after the test.
sleep 300 >/dev/null 2>&1 & ONE=$!
TWO=""
trap 'kill "$ONE" ${TWO:+"$TWO"} 2>/dev/null; wait "$ONE" ${TWO:+"$TWO"} 2>/dev/null; rm -rf "$TMP"' EXIT
sleep 2.2                                   # past the two seconds the comparison allows between starts
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }

run_with() {
  local shell="$1" label="$2" start
  sleep 300 >/dev/null 2>&1 & TWO=$!
  start="$("$shell" -c 'source "$1"; approved_list_process_start "$2"' _ "$LIB" "$ONE")"
  [[ "$start" =~ ^[0-9]+$ ]] && check "$label: the start time of a running process reads as epoch seconds" ok || check "$label: start time" "got '$start'"
  local now; now="$(date +%s)"
  (( now - start >= 2 && now - start <= 6 )) && check "$label: and it is when the process started (about ${#start} digits, $((now - start)) s ago)" ok || check "$label: start is $((now - start)) s ago, expected about 2 to 6" "off"

  has() { # <list text> <pid> -> exit status of approved_list_has_process under $shell
    printf '%b' "$1" > "$TMP/list"
    "$shell" -c 'source "$1"; approved_list_load "$2"; approved_list_has_process "$3"' _ "$LIB" "$TMP/list" "$2"
  }
  has "$ONE\t$start\n" "$ONE" && check "$label: the right start time is approved" ok || check "$label: right start" "refused"
  # The script reads the start again (now minus elapsed time), which can land a second either side of the one
  # read above when a second ticks over between them; a difference at the edge of the allowance would be a coin
  # toss, so these stay a second inside it and a second well outside it.
  has "$ONE\t$((start + 1))\n" "$ONE" && check "$label: a start one second off is still approved" ok || check "$label: +1s" "refused"
  has "$ONE\t$((start - 1))\n" "$ONE" && check "$label: a start one second earlier is still approved" ok || check "$label: -1s" "refused"
  has "$ONE\t$((start + 6))\n" "$ONE" && check "$label: a start six seconds off is refused" "approved" || check "$label: +6s refused" ok
  has "$ONE\t$((start - 100))\n" "$ONE" && check "$label: another start time is refused (a reused pid)" "approved" || check "$label: wrong start refused" ok
  has "$TWO\t$start\n" "$ONE" && check "$label: a line for another pid is not this process" "approved" || check "$label: other pid refused" ok
  has "$ONE\n" "$ONE" && check "$label: a bare pid (an older list) is approved" ok || check "$label: bare pid" "refused"
  has "$ONE\tnot-a-time\n" "$ONE" && check "$label: a start that is not a number is refused" "approved" || check "$label: junk start refused" ok
  has "${ONE}0\t$start\n" "$ONE" && check "$label: a longer pid with the same prefix is not this pid" "approved" || check "$label: prefix pid refused" ok
  has "$ONE\t$((start - 100))\n$ONE\t$start\n$TWO\t1\n" "$ONE" && check "$label: among several lines for the pid the matching one counts" ok || check "$label: several lines" "refused"
  has "" "$ONE" && check "$label: an empty list approves nothing" "approved" || check "$label: empty list" ok
  kill "$TWO" 2>/dev/null; wait "$TWO" 2>/dev/null
  has "$TWO\t$start\n" "$TWO" && check "$label: a process that has ended is refused" "approved" || check "$label: ended process refused" ok
}

run_with /bin/bash "bash 3.2"
for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
  [[ -x "$b" ]] && { run_with "$b" "bash 5"; break; }
done
exit "$fail"
