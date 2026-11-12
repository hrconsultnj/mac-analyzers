#!/usr/bin/env bash
# outline-refuse.sh <sources folder> — prints "file:line  what" for every SwiftUI hierarchical control outside
# the OutlineTable component, and nothing when there is none. `scripts/check.sh outline` runs it on app/Sources.
#
# Refused:
#   DisclosureTableRow, OutlineGroup, Section(isExpanded:)
#   List(…, children: …) and Table(…, children: …), the call read across lines (children: may be on a later line)
#   DisclosureGroup, unless the line directly above is a comment line of its own holding the marker
#       // one disclosed block, not rows
#   (a marker two lines up, in a trailing comment after code, or on the same line does not count)
# Comments are never code: a mention in a `//` comment is ignored.
set -u
root="${1:-app/Sources}"
marker='// one disclosed block, not rows'
[ -d "$root" ] || { echo "outline-refuse: no folder $root" >&2; exit 2; }
find "$root" -name '*.swift' -not -path "$root/UIComponents/OutlineTable/*" -print0 | xargs -0 awk -v marker="$marker" '
function code(line,   t) { t = line; sub(/\/\/.*$/, "", t); return t }
function depth_of(s,   i, d, ch) { d = 0; for (i = 1; i <= length(s); i++) { ch = substr(s, i, 1); if (ch == "(") d++; else if (ch == ")") d-- } return d }
FNR == 1 { prevmarker = 0; reading = 0 }
{
  raw = $0; trimmed = raw; sub(/^[ \t]+/, "", trimmed)
  iscomment = (substr(trimmed, 1, 2) == "//")
  c = iscomment ? "" : code(raw)
  if (reading) {
    buf = buf " " c; depth += depth_of(c)
    if (depth <= 0) { if (buf ~ /children:/) print FILENAME ":" start "  " kind "(…, children:) is a SwiftUI hierarchical control"; reading = 0 }
  } else if (match(c, /(^|[^A-Za-z0-9_])(List|Table)\(/)) {
    s = substr(c, RSTART); if (s !~ /^(List|Table)/) s = substr(s, 2)
    kind = (s ~ /^List/) ? "List" : "Table"
    buf = s; depth = depth_of(s); start = FNR
    if (depth <= 0) { if (buf ~ /children:/) print FILENAME ":" start "  " kind "(…, children:) is a SwiftUI hierarchical control" }
    else reading = 1
  }
  if (c ~ /(^|[^A-Za-z0-9_])(DisclosureTableRow|OutlineGroup)([^A-Za-z0-9_]|$)/ || c ~ /Section\(isExpanded:/)
    print FILENAME ":" FNR "  DisclosureTableRow, OutlineGroup and Section(isExpanded:) are SwiftUI hierarchical controls"
  if (c ~ /(^|[^A-Za-z0-9_])DisclosureGroup([^A-Za-z0-9_]|$)/ && !prevmarker)
    print FILENAME ":" FNR "  DisclosureGroup without the marker comment on the line above (" marker ")"
  prevmarker = (iscomment && index(raw, marker) > 0)
}'
exit 0
