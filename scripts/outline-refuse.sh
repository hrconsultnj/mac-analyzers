#!/usr/bin/env bash
# outline-refuse.sh <sources folder> — prints "file:line  what" for every SwiftUI hierarchical control outside
# the OutlineTable component, and nothing when there is none. `scripts/check.sh outline` runs it on app/Sources.
#
# Refused:
#   DisclosureTableRow, OutlineGroup, Section(isExpanded:)
#   List(…, children: …) and Table(…, children: …): the call is read across lines, and `children:` counts when it
#       is an argument of the call itself (not inside a closure or a nested call within its parentheses)
#   DisclosureGroup, unless the line directly above is a comment line of its own holding the marker
#       // one disclosed block, not rows
#   (a marker two lines up, in a trailing comment after code, or on the same line does not count)
# The scan reads CODE: `//` and `/* */` comments (nested too) and the inside of string literals, single-line and
# """ blocks, are blanked first, so a mention in a comment or a string is never a control, and a `)` inside a
# string does not end a call early.
set -u
root="${1:-app/Sources}"
marker='// one disclosed block, not rows'
[ -d "$root" ] || { echo "outline-refuse: no folder $root" >&2; exit 2; }
find "$root" -name '*.swift' -not -path "$root/UIComponents/OutlineTable/*" -print0 | xargs -0 awk -v marker="$marker" '
# the line without comments and without what is inside string literals (state carries across lines)
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
# feed text of a call to the reader; sets found when children: is an argument of the call, done when its parentheses close
function feed(text,   i, n, ch) {
  n = length(text)
  for (i = 1; i <= n; i++) {
    ch = substr(text, i, 1)
    if (ch == "(") pd++
    else if (ch == ")") { pd--; if (pd <= 0) { done = 1; return } }
    else if (ch == "{") bd++
    else if (ch == "}") bd--
    else if (ch == "c" && pd == 1 && bd == 0 && substr(text, i, 9) == "children:" && (i == 1 || substr(text, i - 1, 1) !~ /[A-Za-z0-9_]/)) found = 1
  }
}
FNR == 1 { prevmarker = 0; reading = 0; block = 0; triple = 0 }
{
  raw = $0; trimmed = raw; sub(/^[ \t]+/, "", trimmed)
  c = strip(raw)
  if (reading) {
    feed(c " ")
    if (done) { if (found) print FILENAME ":" start "  " kind "(…, children:) is a SwiftUI hierarchical control"; reading = 0 }
  } else if (match(c, /(^|[^A-Za-z0-9_])(List|Table)\(/)) {
    s = substr(c, RSTART); if (s !~ /^(List|Table)/) s = substr(s, 2)
    kind = (s ~ /^List/) ? "List" : "Table"
    pd = 0; bd = 0; found = 0; done = 0; start = FNR
    feed(s " ")
    if (done) { if (found) print FILENAME ":" start "  " kind "(…, children:) is a SwiftUI hierarchical control" }
    else reading = 1
  }
  if (c ~ /(^|[^A-Za-z0-9_])(DisclosureTableRow|OutlineGroup)([^A-Za-z0-9_]|$)/ || c ~ /Section\(isExpanded:/)
    print FILENAME ":" FNR "  DisclosureTableRow, OutlineGroup and Section(isExpanded:) are SwiftUI hierarchical controls"
  if (c ~ /(^|[^A-Za-z0-9_])DisclosureGroup([^A-Za-z0-9_]|$)/ && !prevmarker)
    print FILENAME ":" FNR "  DisclosureGroup without the marker comment on the line above (" marker ")"
  prevmarker = (substr(trimmed, 1, 2) == "//" && index(raw, marker) > 0)
}'
exit 0
