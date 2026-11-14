#!/usr/bin/env bash
# states-refuse-test.sh — scripts/states-refuse.sh refuses a screen state drawn without the shared piece and passes the
# allowed forms. Each case plants one Swift file in a scratch folder and asks the real script. Runs under bash and /bin/bash.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/../scripts/states-refuse.sh"
[[ -x "$SCAN" ]] || { echo "SKIP: no scripts/states-refuse.sh"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }
plant() { local d="$TMP/$1/Sources"; mkdir -p "$d/Screens" "$d/Shared"; printf '%s\n' "$2" > "$d/Screens/$1.swift"; "$SCAN" "$d" 2>&1; }
refused() { [[ -n "$(plant "$2" "$3")" ]] && check "$1" ok || check "$1" "was NOT refused"; }
passes()  { [[ -z "$(plant "$2" "$3")" ]] && check "$1" ok || check "$1" "was refused: $(plant "$2" "$3" | head -1)"; }

refused "a bare ContentUnavailableView is refused" A 'ContentUnavailableView("Nothing", systemImage: "x")'
refused "a bare ContentUnavailableView.search is refused" B 'ContentUnavailableView.search(text: q)'
refused "a bare ProgressView as a screen state is refused" C 'ProgressView("Reading…")'
refused "a bare ProgressView() is refused" D 'ProgressView()'
passes  "EmptyState and LoadingState pass" E 'EmptyState("Nothing", systemImage: "x"); LoadingState("Reading…")'
passes  "a gauge passes" F 'ProgressView(value: 0.5, total: 1)'
passes  "an inline spinner passes" G 'ProgressView().controlSize(.small)'
passes  "a mention in a comment passes" H '// a ContentUnavailableView or ProgressView() would sit at the top left'
# the shared piece itself is exempt
d="$TMP/I/Sources"; mkdir -p "$d/Shared"; printf '%s\n' 'ContentUnavailableView("x", systemImage: "y"); ProgressView()' > "$d/Shared/ScreenState.swift"
[[ -z "$("$SCAN" "$d" 2>&1)" ]] && check "the shared piece may use them" ok || check "the shared piece may use them" "was refused"
exit "$fail"
