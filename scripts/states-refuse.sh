#!/usr/bin/env bash
# states-refuse.sh <sources folder> — prints "file:line  what" for every screen state drawn without the shared piece, and
# nothing when there is none. `scripts/check.sh states` runs it on app/Sources (every target).
#
# A screen's empty, failed or loading state is `EmptyState` / `LoadingState` (SettingsFeature/Shared/ScreenState.swift),
# which fill the space the screen has and centre themselves. A bare one takes only its own size and lands at the top left
# under whatever else is in a stack.
#
# Refused (outside ScreenState.swift):
#   ContentUnavailableView                  — use EmptyState (same arguments)
#   ProgressView — any form: `ProgressView()`, `ProgressView("…")`, `ProgressView { … }` — use LoadingState.
#                  Allowed: a gauge (`value:` in the call) and an INLINE spinner, that is `.controlSize(.small)` or
#                  `.controlSize(.mini)` on the same line or in the next two (a `.large` one is a screen spinner), and a
#                  spinner with `// states-allow: <why>` on its own line or the line above.
# The scan reads CODE: `//` and `/* */` comments (nested too) and the inside of string literals, single-line and """ blocks,
# are blanked first, so a mention in a comment or a string is never a state.
set -u
root="${1:-app/Sources}"
[ -d "$root" ] || { echo "states-refuse: no folder $root" >&2; exit 2; }
find "$root" -name '*.swift' -not -name 'ScreenState.swift' -print0 | xargs -0 -n1 awk '
function strip(line,   out, i, n, c, d, t, c2) {
  out = ""; n = length(line); i = 1
  while (i <= n) {
    c = substr(line, i, 1); d = substr(line, i, 2); t = substr(line, i, 3)
    if (block > 0) {
      if (d == "*/") { block--; i += 2 } else if (d == "/*") { block++; i += 2 } else i++
      continue
    }
    if (triple) { if (t == "\"\"\"") { triple = 0; i += 3 } else i++; continue }
    if (d == "//") break
    if (d == "/*") { block++; i += 2; out = out " "; continue }
    if (t == "\"\"\"") { triple = 1; i += 3; out = out "\"\""; continue }
    if (c == "\"") {
      i++
      while (i <= n) { c2 = substr(line, i, 1); if (c2 == "\\") { i += 2; continue } if (c2 == "\"") { i++; break } i++ }
      out = out "\"\""; continue
    }
    out = out c; i++
  }
  return out
}
BEGIN { block = 0; triple = 0 }
{ raw[NR] = $0; code[NR] = strip($0) }
END {
  for (i = 1; i <= NR; i++) {
    c = code[i]
    if (c ~ /(^|[^A-Za-z0-9_])ContentUnavailableView([^A-Za-z0-9_]|$)/)
      print FILENAME ":" i "  ContentUnavailableView — use EmptyState"
    if (c ~ /(^|[^A-Za-z0-9_])ProgressView([^A-Za-z0-9_]|$)/) {
      if (c ~ /ProgressView\(value:/ || c ~ /ProgressView\([^)]*value:/) continue          # a gauge
      window = c " " code[i + 1] " " code[i + 2]
      if (window ~ /\.controlSize\(\.(small|mini)\)/ && c !~ /\.controlSize\(\.large\)/) continue   # an inline spinner
      allow = (raw[i] ~ /\/\/ states-allow:/) || (i > 1 && raw[i - 1] ~ /^[ \t]*\/\/ states-allow:/)
      if (allow) continue
      print FILENAME ":" i "  ProgressView as a screen state — use LoadingState"
    }
  }
}'
exit 0
