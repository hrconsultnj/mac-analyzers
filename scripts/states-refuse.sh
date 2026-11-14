#!/usr/bin/env bash
# states-refuse.sh <sources folder> — prints "file:line  what" for every screen state drawn without the shared piece, and
# nothing when there is none. `scripts/check.sh states` runs it on app/Sources/SettingsFeature.
#
# A screen's empty, failed or loading state is `EmptyState` / `LoadingState` (Shared/ScreenState.swift), which fill the
# space the screen has and centre themselves. A bare one takes only its own size and lands at the top left under
# whatever else is in a stack.
#
# Refused (outside Shared/ScreenState.swift, comment lines ignored):
#   ContentUnavailableView           — use EmptyState (same arguments)
#   ProgressView( … ) as a state     — use LoadingState. Allowed: a gauge (`value:`) and an inline spinner
#                                      (`.controlSize(` on the same line)
set -u
root="${1:-app/Sources/SettingsFeature}"
[ -d "$root" ] || { echo "states-refuse: no folder $root" >&2; exit 2; }
find "$root" -name '*.swift' -not -path "$root/Shared/ScreenState.swift" -print0 | xargs -0 grep -HnE 'ContentUnavailableView|ProgressView\(' 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
  | awk '
      /ContentUnavailableView/ { print $0 "  — use EmptyState"; next }
      /ProgressView\(/ { if ($0 ~ /value:/ || $0 ~ /\.controlSize\(/) next; print $0 "  — use LoadingState" }'
exit 0
