#!/usr/bin/env bash
# outline-refuse-test.sh — scripts/outline-refuse.sh refuses every SwiftUI hierarchical control and passes the allowed
# forms. Each case plants one Swift file in a scratch folder and asks the real script. Runs under bash and /bin/bash.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/../scripts/outline-refuse.sh"
[[ -x "$SCAN" ]] || { echo "SKIP: no scripts/outline-refuse.sh"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }
plant() { # name, body -> prints the scan's output for a tree holding only that file (one tree per case name)
  local d="$TMP/$1/Sources"; mkdir -p "$d/Screens"; printf '%s\n' "$2" > "$d/Screens/$1.swift"
  "$SCAN" "$d" 2>&1
}
refused() { [[ -n "$(plant "$2" "$3")" ]] && check "$1" ok || check "$1" "was NOT refused"; }
passes()  { [[ -z "$(plant "$2" "$3")" ]] && check "$1" ok || check "$1" "was refused: $(plant "$2" "$3" | head -1)"; }

refused "an unmarked DisclosureGroup is refused" A 'DisclosureGroup("Raw") { Text("x") }'
passes  "a DisclosureGroup with the marker on its own line above passes" B '    // one disclosed block, not rows
    DisclosureGroup("Raw") { Text("x") }'
refused "a marker two lines above is refused" C '// one disclosed block, not rows

DisclosureGroup("Raw") { Text("x") }'
refused "a marker as a trailing comment after code on the line above is refused" D 'let a = 1 // one disclosed block, not rows
DisclosureGroup("Raw") { Text("x") }'
refused "a marker on the same line is refused" E 'DisclosureGroup("Raw") { Text("x") } // one disclosed block, not rows'
passes  "a DisclosureGroup named only in a comment passes" F '// a DisclosureGroup is not used here
let x = 1'
refused "OutlineGroup is refused" G 'OutlineGroup(items, children: \.kids) { Text("x") }'
refused "Section(isExpanded:) is refused" H 'Section("A", isExpanded: $open) { Text("x") }
Section(isExpanded: $open) { Text("x") } header: { Text("A") }'
refused "DisclosureTableRow is refused" I 'DisclosureTableRow(item) { TableColumn("a") { _ in Text("x") } }'
refused "a Table with children: on one line is refused" J 'Table(items, children: \.kids) { TableColumn("a") { Text($0.a) } }'
refused "a Table whose children: is on the next line is refused" K 'Table(items,
      children: \.kids) {
  TableColumn("a") { Text($0.a) }
}'
refused "a List with children: is refused" L 'List(items, children: \.kids) { Text($0.a) }'
refused "a List whose children: is several lines down is refused" M 'List(
    items,
    id: \.id,
    children: \.kids
) { item in Text(item.a) }'
passes  "a flat List passes" N 'List(items) { Text($0.a) }'
passes  "a flat Table passes" O 'Table(items) { TableColumn("a") { Text($0.a) } }'
passes  "OutlineTable( is not Table(" P 'OutlineTable(tree, children: \.children, selection: $s) { OutlineColumn("a", "A") { Text("x") } }'
passes  "a List(…) whose later code mentions children: outside the call passes" Q 'List(items) { Text($0.a) }
let kids = node(children: [])'
passes  "children: inside a comment of a List passes" R 'List(items) { // children: not here
  Text($0.a)
}'
# the component itself is where they live
d="$TMP/component/Sources"; mkdir -p "$d/UIComponents/OutlineTable"; printf 'OutlineGroup(a, children: \\.k) { Text("x") }\n' > "$d/UIComponents/OutlineTable/X.swift"
[[ -z "$("$SCAN" "$d" 2>&1)" ]] && check "the OutlineTable component's own folder is not scanned" ok || check "the OutlineTable component's own folder is not scanned" "was scanned"
# the tree as it is
[[ -z "$("$SCAN" "$HERE/../app/Sources" 2>&1)" ]] && check "app/Sources as it is passes" ok || check "app/Sources as it is passes" "$("$SCAN" "$HERE/../app/Sources" | head -2)"
exit $fail
