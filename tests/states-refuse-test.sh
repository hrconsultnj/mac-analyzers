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
plant() { local d="$TMP/$1/Sources"; mkdir -p "$d/SettingsFeature/Screens" "$d/SettingsFeature/Shared"; printf '%s\n' "$2" > "$d/SettingsFeature/Screens/$1.swift"; "$SCAN" "$d" 2>&1; }
refused() { [[ -n "$(plant "$2" "$3")" ]] && check "$1" ok || check "$1" "was NOT refused"; }
passes()  { [[ -z "$(plant "$2" "$3")" ]] && check "$1" ok || check "$1" "was refused: $(plant "$2" "$3" | head -1)"; }

refused "a bare ContentUnavailableView is refused" A 'ContentUnavailableView("Nothing", systemImage: "x")'
refused "a bare ContentUnavailableView.search is refused" B 'ContentUnavailableView.search(text: q)'
refused "a bare ProgressView as a screen state is refused" C 'ProgressView("Reading…")'
refused "a bare ProgressView() is refused" D 'ProgressView()'
refused "a ProgressView trailing closure is refused" J 'ProgressView { Text("Reading") }'
refused "a same-line .large screen spinner is refused" K 'ProgressView().controlSize(.large)'
refused "a spinner whose .controlSize is three lines away is refused" L 'ProgressView()
Text("a")
Text("b")
    .controlSize(.small)'
passes  "an inline spinner with .controlSize(.small) on the next line passes" M 'ProgressView()
    .controlSize(.small)'
passes  "an inline spinner with .controlSize(.mini) two lines on passes" N 'ProgressView("x")
    .padding()
    .controlSize(.mini)'
passes  "a ProgressView inside a string passes" O 'let text = "a ProgressView() in a string"'
passes  "a spinner with a states-allow comment on the line above passes" P '// states-allow: centred by its own ZStack
ProgressView()'
refused "a states-allow comment two lines above does not count" Q '// states-allow: nope

ProgressView()'
passes  "EmptyState and LoadingState pass" E 'EmptyState("Nothing", systemImage: "x"); LoadingState("Reading…")'
passes  "a gauge passes" F 'ProgressView(value: 0.5, total: 1)'
passes  "an inline spinner passes" G 'ProgressView().controlSize(.small)'
passes  "a mention in a comment passes" H '// a ContentUnavailableView or ProgressView() would sit at the top left'
# the shared piece itself is exempt
d="$TMP/I/Sources"; mkdir -p "$d/SettingsFeature/Shared"; printf '%s\n' 'ContentUnavailableView("x", systemImage: "y"); ProgressView()' > "$d/SettingsFeature/Shared/ScreenState.swift"
[[ -z "$("$SCAN" "$d" 2>&1)" ]] && check "the shared piece may use them" ok || check "the shared piece may use them" "was refused"
# the other targets are scanned too
for target in UIComponents MenuBarFeature; do
  d="$TMP/T-$target/Sources"; mkdir -p "$d/$target"; printf '%s\n' 'ContentUnavailableView("x", systemImage: "y")' > "$d/$target/X.swift"
  [[ -n "$("$SCAN" "$d" 2>&1)" ]] && check "$target is scanned" ok || check "$target is scanned" "a bare state there was NOT refused"
done
exit "$fail"
