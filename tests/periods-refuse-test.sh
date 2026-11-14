#!/usr/bin/env bash
# periods-refuse-test.sh — scripts/periods-refuse.sh refuses a period type or menu that is not the shared one and passes the
# allowed forms. Each case plants one Swift file in a scratch tree and asks the real script. Runs under bash and /bin/bash.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/../scripts/periods-refuse.sh"
[[ -x "$SCAN" ]] || { echo "SKIP: no scripts/periods-refuse.sh"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }
# plant <case> <relative path under Sources> <line>
plant() { local d="$TMP/$1/Sources"; mkdir -p "$d/$(dirname "$2")"; printf '%s\n' "$3" > "$d/$2"; "$SCAN" "$d" 2>&1; }
refused() { [[ -n "$(plant "$2" "$3" "$4")" ]] && check "$1" ok || check "$1" "was NOT refused"; }
passes()  { [[ -z "$(plant "$2" "$3" "$4")" ]] && check "$1" ok || check "$1" "was refused: $(plant "$2" "$3" "$4" | head -1)"; }

refused "enum Period is refused" A SettingsFeature/Screens/X.swift 'enum Period { case a }'
refused "enum TrendsPeriod is refused" B SettingsFeature/Screens/X.swift 'enum TrendsPeriod: Int { case day7 }'
refused "struct ReportingPeriod is refused" C AnalyzersKit/X.swift 'public struct ReportingPeriod { }'
refused "enum Window in History code is refused" D SettingsFeature/Screens/History/X.swift 'enum Window: Int { case day = 24 }'
refused "enum Window in Memory code is refused" E AnalyzersKit/Memory/X.swift 'public enum Window { case a }'
refused "a Picker over ReportPeriod in a screen is refused" F SettingsFeature/Screens/History/X.swift 'Picker("Period", selection: $p) { ForEach(ReportPeriod.allCases) { Text($0.title) } }'
refused "ReportPeriod.allCases in a screen is refused" G SettingsFeature/Screens/Memory/X.swift 'let all = ReportPeriod.allCases'
refused "a ForEach over a literal list of periods is refused" H SettingsFeature/Screens/History/X.swift 'ForEach([ReportPeriod.day, .threeDays, .week]) { Text($0.title) }'
refused "a list naming .fortnight is refused" I SettingsFeature/Screens/Overview/X.swift 'let choices: [ReportPeriod] = [.week, .fortnight]'
passes  "enum Window outside History, Memory and Overview passes" J SettingsFeature/Screens/Activity/X.swift 'enum Window { case a }'
passes  "a list of calendar components passes" K SettingsFeature/Screens/History/X.swift 'let parts: [Calendar.Component] = [.year, .month, .day, .week]'
passes  "using one period passes" L SettingsFeature/Screens/History/X.swift 'let p = ReportPeriod.week; Text(p.title)'
passes  "a mention in a comment passes" M SettingsFeature/Screens/History/X.swift '// an enum Period or ReportPeriod.allCases here would be a second menu'
passes  "the shared menu may list them" N SettingsFeature/Shared/PeriodMenu.swift 'ForEach(ReportPeriod.allCases) { Text($0.title) }'
passes  "the type itself may be declared" O AnalyzersKit/History/ReportPeriod.swift 'public enum ReportPeriod: Int { case day = 24 }'
passes  "the name table may hold an enum Period" P AnalyzersKit/Naming/Names.swift 'public enum Period { }'
passes  "a probe may loop over the periods" Q AgentRunner/X.swift 'for p in ReportPeriod.allCases { }'
exit "$fail"
