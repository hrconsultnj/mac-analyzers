#!/usr/bin/env bash
# monitor-probe.sh — Monitor's real table on the real process table, driven headless, counting what AppKit
# logs ("reentrant operation in its NSTableView delegate") between the probe's marks.
#
#   scripts/monitor-probe.sh            every action, 3 runs each
#   scripts/monitor-probe.sh soak       the soak, SOAK_SECONDS long (default 600)
#
# It uses SnapshotRunner's outline probe (`--outline-probe monitor:<case>`): the window is never on a
# display and never takes focus. Build path: MONITOR_BUILD_PATH (default app/.build).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT/app" || exit 2
ARGS=(--disable-keychain)
[ -n "${MONITOR_BUILD_PATH:-}" ] && ARGS+=(--build-path "$MONITOR_BUILD_PATH")
env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= swift build "${ARGS[@]}" --product SnapshotRunner >/dev/null 2>&1 \
  || { echo "monitor-probe: could not build SnapshotRunner" >&2; exit 1; }
BIN="$(env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= swift build "${ARGS[@]}" --show-bin-path 2>/dev/null)/SnapshotRunner"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ma-monitor.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
FAILED=0
count() { # <case> [extra args]: warnings between the marks, and outside
  local name="$1"; shift
  OS_ACTIVITY_DT_MODE=YES "$BIN" --outline-probe "monitor:$name" "$@" >"$TMP/out" 2>"$TMP/err"; local rc=$?
  local inside outside
  inside="$(awk '/^@@MARK begin/{on=1;next} /^@@MARK end/{on=0;next} on && /reentrant operation/{c++} END{print c+0}' "$TMP/err")"
  outside=$(( $(grep -a -c 'reentrant operation' "$TMP/err") - inside ))
  echo "case=$name warnings=$inside outside=$outside exit=$rc  $(tail -1 "$TMP/out")"
  [ "$inside" -eq 0 ] && [ "$outside" -eq 0 ] && [ "$rc" -eq 0 ] || FAILED=1
}
if [ "${1:-}" = "soak" ]; then
  count soak --seconds "${SOAK_SECONDS:-600}"
else
  for name in first ticks resort search tabs open1 openAll churn; do
    for run in 1 2 3; do count "$name"; done
  done
fi
[ "$FAILED" -eq 0 ] && echo "monitor-probe: zero warnings" || echo "monitor-probe: FAILED"
exit "$FAILED"
