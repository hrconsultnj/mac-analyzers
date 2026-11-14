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
#                  Allowed: a gauge (`value:` among its arguments, but `value: nil` is an indeterminate bar, which is a state);
#                  an INLINE spinner, that is one whose OWN modifier chain (the `.modifier(…)` calls that follow it, on the same
#                  line or the lines below, up to the next thing that is not a modifier) has `.controlSize(.small)` or
#                  `.controlSize(.mini)` — or a ternary whose every branch is one of those — or whose immediate container
#                  (`HStack { ProgressView() … }.controlSize(.small)`) has one. A `.controlSize` on a Button below it is not
#                  its own, a `.large` or `.regular` one is a screen spinner, and a small spinner that is the WHOLE content of a
#                  view body (`var body: some View { ProgressView().controlSize(.small) }`) is the screen state itself, which
#                  lands at the top left: use LoadingState. A type annotation (`ProgressView<…>` not followed by a call) is not a state. A spinner with a
#                  `// states-allow: <why>` COMMENT, with a reason, on its own line above it or after it on the same line is allowed.
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
# 1 when args (the text of a controlSize call, parentheses included) is .small or .mini, or a ternary of nothing but those
function sizeOk(args,   inner, n, parts, k, member) {
  inner = args; sub(/^\([ \t]*/, "", inner); sub(/[ \t]*\)$/, "", inner)
  if (inner ~ /^\.(small|mini)$/) return 1
  if (inner !~ /\?/ || inner !~ /:/) return 0
  # every member named after the ? or the : must be small or mini
  n = 0
  rest = inner; sub(/^[^?]*\?/, "", rest)
  while (match(rest, /\.[A-Za-z]+/)) { member = substr(rest, RSTART + 1, RLENGTH - 1); n++; if (member != "small" && member != "mini") return 0; rest = substr(rest, RSTART + RLENGTH) }
  return n >= 2
}
# 1 when the modifier chain that starts at position q of s has a small or mini .controlSize of its own; chainEnd is where it ends
function chainInline(s, q,   q2, r, e, name, args, found) {
  found = 0
  while (1) {
    q2 = skipSpace(s, q)
    if (substr(s, q2, 1) != "." || substr(s, q2 + 1, 1) !~ /[A-Za-z]/) break
    r = q2 + 1
    while (substr(s, r, 1) ~ /[A-Za-z0-9_]/) r++
    name = substr(s, q2 + 1, r - q2 - 1)
    args = ""
    if (substr(s, r, 1) == "(") { e = closeAt(s, r); if (e == 0) e = length(s) + 1; args = substr(s, r, e - r); r = e }
    if (name == "controlSize" && sizeOk(args)) found = 1
    q = r
  }
  chainEnd = q
  return found
}
# the position of the { that opens the braces around position p of s, or 0
function opener(s, p,   depth, k, ch) {
  depth = 0
  for (k = p - 1; k >= 1; k--) {
    ch = substr(s, k, 1)
    if (ch == "}") depth++
    else if (ch == "{") { if (depth == 0) return k; depth-- }
  }
  return 0
}
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
      args = substr(all, q, e - q)
      if (args ~ /(^|[^A-Za-z0-9_])value:/ && args !~ /(^|[^A-Za-z0-9_])value:[ \t\n]*nil([^A-Za-z0-9_]|$)/) gauge = 1
      q = e
    }
    if (gauge) continue
    q2 = skipSpace(all, q)
    if (substr(all, q2, 1) == "{") { e = closeAt(all, q2); if (e == 0) e = length(all) + 1; q = e }
    # an inline spinner: a small or mini size in its OWN modifier chain, or in the chain of the container that holds it
    inline = chainInline(all, q)
    sole = 0
    if (inline) {
      # the whole content of a view body is the screen state itself, not a spinner inside something (a spinner that is all
      # of an if branch is an indicator that comes and goes: a toolbar item, a glyph tile, a strip, so it stays allowed)
      b = opener(all, at)
      if (b > 0) {
        before = substr(all, 1, at - 1); sub(/[ \t\n]+$/, "", before)
        after = skipSpace(all, chainEnd)
        if (length(before) == b && substr(all, after, 1) == "}") {
          ls = b; while (ls > 1 && substr(all, ls - 1, 1) != "\n") ls--
          head = substr(all, ls, b - ls)
          if (head ~ /some View[ \t]*$/) sole = 1
        }
      }
    } else {
      b = opener(all, at)
      if (b > 0) { e = closeAt(all, b); if (e > 0 && chainInline(all, e)) inline = 1 }
    }
    if (inline && !sole) continue
    # allowed, with a reason, by a comment on the line above (a whole-line comment) or after it on the same line
    code_above = (line > 1) ? code[line - 1] : "x"
    allow = hasReason(comment[line]) || (line > 1 && code_above ~ /^[ \t]*$/ && hasReason(comment[line - 1]))
    if (allow) continue
    print FILENAME ":" line "  ProgressView as a screen state — use LoadingState"
  }
}'
exit 0
