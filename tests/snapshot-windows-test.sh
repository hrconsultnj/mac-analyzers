#!/usr/bin/env bash
# snapshot-windows-test.sh — `scripts/check.sh snapshot` refuses a development tool that makes a plain NSWindow or NSPanel
# (AppKit moves it back onto the owner's display) and passes the shared OffscreenWindow. Each case plants one Swift file in a
# scratch tree and asks the real check. Runs under bash and /bin/bash.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/../scripts/check.sh"
[[ -x "$CHECK" ]] || { echo "SKIP: no scripts/check.sh"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
pass() { echo "PASS  $1"; }
bad() { echo "FAIL  $1 ($2)"; fail=1; }
# plant <case> <path under Sources> <line>: the check's exit status for that tree (SnapshotRunner needs a main.swift)
run() {
  local d="$TMP/$1/Sources"; mkdir -p "$d/$(dirname "$2")" "$d/SnapshotRunner"
  printf '%s\n' "$3" > "$d/$2"
  MA_SNAPSHOT_ROOT="$d" "$CHECK" snapshot >/dev/null 2>&1; echo $?
}
refused() { [[ "$(run "$2" "$3" "$4")" == "1" ]] && pass "$1" || bad "$1" "was NOT refused"; }
passes()  { [[ "$(run "$2" "$3" "$4")" == "0" ]] && pass "$1" || bad "$1" "was refused"; }
# the check also reads app/Sources/SnapshotRunner/main.swift of the real tree for top-level await; that part is real, so these
# cases only vary the window code.
refused "NSWindow( in SnapshotRunner is refused" A SnapshotRunner/X.swift 'let w = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
refused "NSPanel( in MenuSnapshot is refused" B MenuSnapshot/X.swift 'let p = NSPanel(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
refused "a window in AgentRunner is refused" C AgentRunner/X.swift 'window = NSWindow(contentRect: r, styleMask: m, backing: .buffered, defer: false)'
refused "a subclass of NSWindow in a tool is refused" D SnapshotRunner/X.swift 'final class ProbeWindow: NSWindow {'
passes  "an OffscreenWindow passes" E SnapshotRunner/X.swift 'let w = OffscreenWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
passes  "a window in the app itself passes" F SettingsFeature/X.swift 'let w = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
exit "$fail"
