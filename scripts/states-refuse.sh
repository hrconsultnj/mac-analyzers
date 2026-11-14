#!/usr/bin/env bash
# states-refuse.sh <sources folder> — prints "file:line  what" for every screen state drawn without the shared piece, and
# nothing when there is none. `scripts/check.sh states` runs it on app/Sources (every target).
#
# A screen's empty, failed or loading state is `EmptyState` / `LoadingState` (SettingsFeature/Shared/ScreenState.swift),
# which fill the space the screen has and centre themselves. A bare one takes only its own size and lands at the top left
# under whatever else is in a stack.
#
# Refused (everywhere but the one file SettingsFeature/Shared/ScreenState.swift, exempt by its PATH — a file of that name
# anywhere else is checked):
#   ContentUnavailableView                  — use EmptyState (same arguments)
#   ProgressView — any form: `ProgressView()`, `ProgressView("…")`, `ProgressView { … }` — use LoadingState.
#                  Allowed: a gauge (`value:` among its arguments); an INLINE spinner, that is one whose OWN modifier chain
#                  (the `.modifier(…)` calls that follow it, on the same line or the lines below, up to the next thing that
#                  is not a modifier) has `.controlSize(.small)` or `.controlSize(.mini)` — a `.controlSize` on a Button
#                  below it is not its own, and a `.large` one is a screen spinner; a type annotation (`ProgressView<…>` not
#                  followed by a call); and a spinner with a `// states-allow: <why>` COMMENT, with a reason, on its own line
#                  above it or after it on the same line.
# The scan reads CODE: `//` and `/* */` comments (nested too) and the inside of string literals — single-line, """ blocks and
# raw strings (`#"…"#`, `#"""…"""#`, inner quotes and all) — are blanked first, so a mention in a comment or a string is
# never a state, and the allow marker counts only where it is a comment.
set -u
root="${1:-app/Sources}"
[ -d "$root" ] || { echo "states-refuse: no folder $root" >&2; exit 2; }
find "$root" -name '*.swift' -not -path "$root/SettingsFeature/Shared/ScreenState.swift" -print0 | xargs -0 -n1 awk '
# blanks comments and string contents; leaves the text of a trailing // comment in lastComment
function strip(line,   out, i, n, c, d, t, c2, h, j, ok) {
  out = ""; n = length(line); i = 1; lastComment = ""
  while (i <= n) {
    c = substr(line, i, 1); d = substr(line, i, 2); t = substr(line, i, 3)
    if (block > 0) {
      if (d == "*/") { block--; i += 2 } else if (d == "/*") { block++; i += 2 } else i++
      continue
    }
    if (triple) {
      # a """ block ends at three quotes followed by the hashes it opened with (none for a plain block)
      if (t == "\"\"\"" && substr(line, i + 3, rawHashes) == hashes) { triple = 0; i += 3 + rawHashes } else i++
      continue
    }
    if (d == "//") { lastComment = substr(line, i + 2); break }
    if (d == "/*") { block++; i += 2; out = out " "; continue }
    if (c == "#") {
      # a raw string: #"…"# or #"""…"""# (any number of #), where a bare quote does not end it
      h = 0; j = i
      while (substr(line, j, 1) == "#") { h++; j++ }
      if (substr(line, j, 1) == "\"") {
        hashes = substr(line, i, h)
        if (substr(line, j, 3) == "\"\"\"") { triple = 1; rawHashes = h; i = j + 3; out = out "\"\""; continue }
        i = j + 1
        while (i <= n) {
          if (substr(line, i, 1) == "\"" && substr(line, i + 1, h) == hashes) { i += 1 + h; break }
          i++
        }
        out = out "\"\""; continue
      }
    }
    if (t == "\"\"\"") { triple = 1; rawHashes = 0; hashes = ""; i += 3; out = out "\"\""; continue }
    if (c == "\"") {
      i++
      while (i <= n) { c2 = substr(line, i, 1); if (c2 == "\\") { i += 2; continue } if (c2 == "\"") { i++; break } i++ }
      out = out "\"\""; continue
    }
    out = out c; i++
  }
  return out
}
# the index of the first character after the balanced bracket that opens at position p of s (open is ( or {), or 0
function closeAt(s, p,   opener, closer, depth, k, ch) {
  opener = substr(s, p, 1); closer = (opener == "(") ? ")" : "}"; depth = 0
  for (k = p; k <= length(s); k++) {
    ch = substr(s, k, 1)
    if (ch == opener) depth++
    else if (ch == closer) { depth--; if (depth == 0) return k + 1 }
  }
  return 0
}
function skipSpace(s, p) { while (p <= length(s) && substr(s, p, 1) ~ /[ \t\n]/) p++; return p }
BEGIN { block = 0; triple = 0; rawHashes = 0; hashes = ""; all = ""; nl = 0 }
{ code[NR] = strip($0); comment[NR] = lastComment; start[NR] = length(all); all = all code[NR] "\n" }
function lineOf(pos,   lo, hi, mid) {
  lo = 1; hi = NR
  while (lo < hi) { mid = int((lo + hi + 1) / 2); if (start[mid] + 1 <= pos) lo = mid; else hi = mid - 1 }
  return lo
}
function hasReason(text) { return text ~ /^[ \t]*states-allow:[ \t]*[^ \t]/ }
END {
  for (i = 1; i <= NR; i++) {
    if (code[i] ~ /(^|[^A-Za-z0-9_])ContentUnavailableView([^A-Za-z0-9_]|$)/)
      print FILENAME ":" i "  ContentUnavailableView — use EmptyState"
  }
  pos = 1
  while (match(substr(all, pos), /(^|[^A-Za-z0-9_])ProgressView([^A-Za-z0-9_]|$)/)) {
    at = pos + RSTART - 1
    if (substr(all, at, 1) !~ /[A-Za-z]/) at++              # the character before the name was matched too
    p = at + length("ProgressView")
    pos = p
    line = lineOf(at)
    q = skipSpace(all, p)
    # a generic type annotation (`ProgressView<Text, EmptyView>`) that is not then called is a type, not a state
    if (substr(all, p, 1) == "<") {
      g = p; depth = 0
      for (; g <= length(all); g++) { ch = substr(all, g, 1); if (ch == "<") depth++; else if (ch == ">") { depth--; if (depth == 0) { g++; break } } }
      if (substr(all, g, 1) != "(" && substr(all, g, 1) != "{") continue
      q = g
    }
    gauge = 0
    if (substr(all, q, 1) == "(") {
      e = closeAt(all, q); if (e == 0) e = length(all) + 1
      if (substr(all, q, e - q) ~ /(^|[^A-Za-z0-9_])value:/) gauge = 1
      q = e
    }
    if (gauge) continue
    q2 = skipSpace(all, q)
    if (substr(all, q2, 1) == "{") { e = closeAt(all, q2); if (e == 0) e = length(all) + 1; q = e }
    # its own modifier chain: .name(...) calls, on this line or the next lines
    inline = 0
    while (1) {
      q2 = skipSpace(all, q)
      if (substr(all, q2, 1) != "." || substr(all, q2 + 1, 1) !~ /[A-Za-z]/) break
      r = q2 + 1
      while (substr(all, r, 1) ~ /[A-Za-z0-9_]/) r++
      name = substr(all, q2 + 1, r - q2 - 1)
      args = ""
      if (substr(all, r, 1) == "(") { e = closeAt(all, r); if (e == 0) e = length(all) + 1; args = substr(all, r, e - r); r = e }
      if (name == "controlSize" && args ~ /^\([ \t]*\.(small|mini)[ \t]*\)$/) inline = 1
      q = r
    }
    if (inline) continue
    # allowed, with a reason, by a comment on the line above (a whole-line comment) or after it on the same line
    code_above = (line > 1) ? code[line - 1] : "x"
    allow = hasReason(comment[line]) || (line > 1 && code_above ~ /^[ \t]*$/ && hasReason(comment[line - 1]))
    if (allow) continue
    print FILENAME ":" line "  ProgressView as a screen state — use LoadingState"
  }
}'
exit 0
