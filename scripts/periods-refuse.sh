#!/usr/bin/env bash
# periods-refuse.sh <sources folder> — prints "file:line  what" for every period type or period menu that is not the
# shared one, and nothing when there is none. `scripts/check.sh periods` runs it on app/Sources.
#
# Every screen with a period offers every period of `ReportPeriod` (AnalyzersKit/History/ReportPeriod.swift) through
# the one menu `PeriodToolbar` (SettingsFeature/Shared/PeriodMenu.swift); a screen says only its default and the key it
# saves under. Refused (comment lines ignored):
#   a type whose name ends in Period (enum, struct, class), outside ReportPeriod.swift and the name table (Naming/Names.swift)
#   an enum, struct or class named Window, TimeRange or ReportRange in History, Memory or Overview code
#   a Picker or ForEach over ReportPeriod, or ReportPeriod.allCases, outside Shared/PeriodMenu.swift
#   a list of periods written out ([.week, .month, …] naming .threeDays, .fortnight or .quarter) outside the shared files
set -u
root="${1:-app/Sources}"
[ -d "$root" ] || { echo "periods-refuse: no folder $root" >&2; exit 2; }
find "$root" -name '*.swift' -print0 | xargs -0 grep -HnE \
  '(enum|struct|class|actor)[[:space:]]+[A-Za-z]*Period([^A-Za-z]|$)|(enum|struct|class)[[:space:]]+(Window|TimeRange|ReportRange)([^A-Za-z]|$)|(ForEach|Picker)\(.*ReportPeriod|ReportPeriod\.allCases|\[[^]]*\.(threeDays|fortnight|quarter)\b[^]]*\]' 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
  | awk -F: '
      {
        file = $1; line = $0
        shared = (file ~ /\/Shared\/PeriodMenu\.swift$/)
        defines = (file ~ /\/History\/ReportPeriod\.swift$/ || file ~ /\/Naming\/Names\.swift$/)
        probes = (file ~ /\/AgentRunner\//)
        scoped = (file ~ /\/(Screens\/(History|Memory|Overview)|AnalyzersKit\/(History|Memory|Overview))\//)
        body = line; sub(/^[^:]+:[0-9]+:/, "", body)
        if (body ~ /(enum|struct|class|actor)[ \t]+[A-Za-z]*Period([^A-Za-z]|$)/) { if (!defines) print line "  — a second period type: use ReportPeriod"; next }
        if (body ~ /(enum|struct|class)[ \t]+(Window|TimeRange|ReportRange)([^A-Za-z]|$)/) { if (scoped) print line "  — a second period type: use ReportPeriod"; next }
        if (body ~ /(ForEach|Picker)\(.*ReportPeriod|ReportPeriod\.allCases/) { if (!shared && !defines && !probes) print line "  — a period menu outside PeriodToolbar"; next }
        if (!shared && !defines && !probes) print line "  — a list of periods written out: use PeriodToolbar"
      }'
exit 0
