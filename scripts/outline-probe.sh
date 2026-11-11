#!/usr/bin/env bash
# outline-probe.sh — runs the headless probes of the shared OutlineTable
# (SnapshotRunner --outline-probe …, app/Sources/SnapshotRunner/OutlineProbe*.swift)
# and counts what AppKit logs: "reentrant operation in its NSTableView delegate".
#
#   scripts/outline-probe.sh a1      the actions of the measurement, each in a fresh process,
#                                    3 runs, with text cells and with hosted cells: warnings=0
#   scripts/outline-probe.sh a2      the wrapper's own cases (closed group, 3 levels, 6,000 children,
#                                    section headers, an update from inside AppKit's call, the
#                                    environment in hosted cells, the context menu)
#   scripts/outline-probe.sh a3      the 120 s soak (SOAK_SECONDS shortens it)
#   scripts/outline-probe.sh a4      what survives an update: selection, expansion, scroll, focus
#   scripts/outline-probe.sh a5      timings at 6,000 rows, median of 3, against the budgets
#   scripts/outline-probe.sh a6      the pure diff
#   scripts/outline-probe.sh a7      ticks (review semantics on a fixture)
#   scripts/outline-probe.sh a8      autosave, and RememberedExpansion
#   scripts/outline-probe.sh a11     flat SwiftUI Table re-sorts and List appends, counted
#   scripts/outline-probe.sh render <dir>   one image per fixture, size and appearance (screencapture of a window outside every display)
#   scripts/outline-probe.sh check   the subset scripts/check.sh runs: open all and re-sort, text and hosted
#   scripts/outline-probe.sh all     a1 … a11
#
# Each probe prints `@@MARK begin <name>` / `@@MARK end <name>` on stderr around the
# action and this script counts the warning lines between them (setup before the
# marks is counted separately as "outside"). `OS_ACTIVITY_DT_MODE=YES` is set HERE,
# for the probe process only, so os_log reaches its stderr; nothing in the
# component reads an environment variable.
#
# The probe runs headless: its window is never on a display and never takes focus.
# macOS only. Build products go to OUTLINE_BUILD_PATH (default app/.build); a5 and a6 build
# release (timings), the others debug.
# Exit 1 when any probe failed or counted a warning.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT/app" || exit 2

if [ "$(uname -s)" != "Darwin" ]; then
  echo "outline-probe: macOS only" >&2
  exit 2
fi

BUILD_ARGS=(--disable-keychain)
[ -n "${OUTLINE_BUILD_PATH:-}" ] && BUILD_ARGS+=(--build-path "$OUTLINE_BUILD_PATH")
CONFIG_ARGS=()

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ma-outline.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

# build quietly; a build failure is a failure of the probe
build() {
  if ! env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
       swift build "${BUILD_ARGS[@]}" "${CONFIG_ARGS[@]}" --product SnapshotRunner >"$TMP/build.log" 2>&1; then
    grep -a -E ': error: ' "$TMP/build.log" | cut -c1-300 | awk '!seen[$0]++' | head -10
    echo "outline-probe: could not build SnapshotRunner" >&2
    exit 1
  fi
  BIN="$(env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
         swift build "${BUILD_ARGS[@]}" "${CONFIG_ARGS[@]}" --show-bin-path 2>/dev/null)/SnapshotRunner"
  [ -x "$BIN" ] || { echo "outline-probe: no SnapshotRunner at $BIN" >&2; exit 1; }
}

FAILED=0
WARN=0; OUTSIDE=0; QUEUED=0; RC=0

# run_probe <probe args…>: sets WARN (inside the marks), OUTSIDE, QUEUED, RC; output in $TMP/out
run_probe() {
  OS_ACTIVITY_DT_MODE=YES "$BIN" --outline-probe "$@" >"$TMP/out" 2>"$TMP/err"
  RC=$?
  WARN="$(awk '/^@@MARK begin/{on=1;next} /^@@MARK end/{on=0;next} on && /reentrant operation/{c++} END{print c+0}' "$TMP/err")"
  local total
  total="$(grep -a -c 'reentrant operation' "$TMP/err")"
  OUTSIDE=$((total - WARN))
  QUEUED="$(awk '/^@@MARK begin/{on=1;next} /^@@MARK end/{on=0;next} on && /update queued to the next main turn/{c++} END{print c+0}' "$TMP/err")"
}

fail() { FAILED=1; }

say_out() { sed 's/^/    /' "$TMP/out"; }

# ── A1 ──────────────────────────────────────────────────────────────────────
A1_ACTIONS="appear expand1 collapse1 expandAll expandAllOption values addChild removeChild addParent removeParent resort filter10 filterBack select"

a1() {
  local total=0 runs=0 action run variant flag
  echo "A1 — ${A1_RUNS:-3} runs of each action, 200 x 5, text and hosted cells"
  for variant in text hosted; do
    flag=""; [ "$variant" = "hosted" ] && flag="--hosted"
    for action in $A1_ACTIONS; do
      for run in $(seq 1 "${A1_RUNS:-3}"); do
        # shellcheck disable=SC2086
        run_probe "$action" --rows 200,5 $flag
        echo "action=$action variant=$variant run=$run warnings=$WARN outside=$OUTSIDE"
        total=$((total + WARN)); runs=$((runs + 1))
        [ "$WARN" -eq 0 ] && [ "$RC" -eq 0 ] || fail
      done
    done
  done
  echo "A1 total warnings=$total over $runs runs"
}

# ── A2 ──────────────────────────────────────────────────────────────────────
a2() {
  local name flag variant
  echo "A2 — the wrapper's own cases"
  for variant in text hosted; do
    flag=""; [ "$variant" = "hosted" ] && flag="--hosted"
    for name in valuesAndAdd closedGroupAdd threeLevel bigLevel; do
      # shellcheck disable=SC2086
      run_probe "a2:$name" $flag
      echo "case=$name variant=$variant warnings=$WARN outside=$OUTSIDE exit=$RC"
      say_out
      [ "$WARN" -eq 0 ] && [ "$RC" -eq 0 ] || fail
    done
  done
  local run
  for variant in text hosted; do
    flag=""; [ "$variant" = "hosted" ] && flag="--hosted"
    for run in 1 2 3; do
      # shellcheck disable=SC2086
      run_probe "a2:openWithInsert" $flag
      echo "case=openWithInsert variant=$variant run=$run warnings=$WARN outside=$OUTSIDE exit=$RC"
      say_out
      [ "$WARN" -eq 0 ] && [ "$RC" -eq 0 ] || fail
    done
  done
  # the independent review's cases, and the closed-group cases below the first level
  for name in rv-order rv-reparent rv-closedAfterOpen rv-grand rv-bulkRemove rv-bulkChild rv-bulkSelectMoved rv-nilEmpty rv-dup rv-linesOffscreen rv-closedDeep rv-closedUnderHeader rv-closedExpandAllSameUpdate; do
    run_probe "a2:$name"
    echo "case=$name warnings=$WARN outside=$OUTSIDE exit=$RC"
    say_out
    [ "$WARN" -eq 0 ] && [ "$RC" -eq 0 ] || fail
  done
  for name in sectionHeaders callback env menu lines; do
    run_probe "a2:$name"
    echo "case=$name warnings=$WARN outside=$OUTSIDE exit=$RC queuedFromCallback=$QUEUED"
    say_out
    [ "$WARN" -eq 0 ] && [ "$RC" -eq 0 ] || fail
  done
}

# ── A3 ──────────────────────────────────────────────────────────────────────
a3() {
  local variant flag
  for variant in text hosted; do
    flag=""; [ "$variant" = "hosted" ] && flag="--hosted"
    # shellcheck disable=SC2086
    run_probe soak --seconds "${SOAK_SECONDS:-120}" $flag
    echo "soak variant=$variant seconds=${SOAK_SECONDS:-120} warnings=$WARN outside=$OUTSIDE exit=$RC"
    [ "$WARN" -eq 0 ] && [ "$RC" -eq 0 ] || fail
  done
}

# ── plain probes: print their output, exit status decides ───────────────────
plain() { # plain <label> <probe args…>
  local label="$1"; shift
  run_probe "$@"
  echo "$label warnings=$WARN outside=$OUTSIDE exit=$RC"
  say_out
  [ "$WARN" -eq 0 ] && [ "$RC" -eq 0 ] || fail
}

a4() {
  plain "A4 preserve (200 x 5: the rows move one by one)" preserve --rows 200,5
  plain "A4 preserve (3000 x 2: a re-sort moves so many rows that the level is replaced and reloaded)" preserve --rows 3000,2
}
a6() { plain "A6 diff" diff; }
a7() { plain "A7 ticks" ticks; }
a8() { plain "A8 autosave" autosave; plain "A8 remembered" remembered; }

# ── A5 ──────────────────────────────────────────────────────────────────────
# budgets: the measurement's `f` (text) and `g` (hosted) numbers, 1.2x; under 20 ms is noise
a5() {
  local variant flag run
  echo "A5 — 6,000 rows (1,000 x 5, all open), median of 3, ms; budget = 1.2 x the measurement or under 20 ms (wall time includes SwiftUI, the probe's own model and whatever else the Mac is doing: load average $(uptime | sed 's/.*load averages*: //'); cpu is this thread's CPU time for the step)"
  for variant in text hosted; do
    flag=""; [ "$variant" = "hosted" ] && flag="--hosted"
    : >"$TMP/perf.$variant"
    for run in 1 2 3; do
      # shellcheck disable=SC2086
      run_probe perf --rows 1000,5 $flag
      grep -a '^perf ' "$TMP/out" >>"$TMP/perf.$variant"
      [ "$WARN" -eq 0 ] && [ "$RC" -eq 0 ] || { echo "run $run: warnings=$WARN exit=$RC"; fail; }
    done
    awk -v variant="$variant" '
      function med(a, b, c) { return a + b + c - (a > b ? (a > c ? a : c) : (b > c ? b : c)) - (a < b ? (a < c ? a : c) : (b < c ? b : c)) }
      BEGIN {
        if (variant == "text") { split("appear 45 expandAll 18 scrollMean 10.3 values 6 resort 17 addChild 6 removeChild 5 filter10 13 filterBack 5", t, " ") }
        else { split("appear 32 expandAll 19 scrollMean 12.9 values 1 resort 28 addChild 6 removeChild 6 filter10 13 filterBack 5", t, " ") }
        for (i = 1; i <= 17; i += 2) budget[t[i]] = t[i + 1] * 1.2
        order = "appear expandAll scrollMean scrollP95 values resort addChild removeChild filter10 filterBack valuesModelCpu resortModelCpu"
      }
      { for (i = 1; i <= NF; i++) { split($i, kv, "="); if (kv[1] != "perf" && kv[1] != "rows" && kv[1] != "hosted") { n[kv[1]]++; v[kv[1], n[kv[1]]] = kv[2] } } }
      END {
        split(order, keys, " ")
        for (k = 1; k <= 12; k++) {
          key = keys[k]
          m = med(v[key, 1], v[key, 2], v[key, 3])
          c = (key "Cpu") in n ? med(v[key "Cpu", 1], v[key "Cpu", 2], v[key "Cpu", 3]) : -1
          cpu = c >= 0 ? sprintf("cpu %6.1f ms", c) : ""
          if (key ~ /ModelCpu$/) { printf "  %-7s %-11s the probe model alone, same edit: %5.1f ms cpu\n", variant, key, m; continue }
          if (key in budget) { verdict = (m <= budget[key] || m < 20) ? "within" : "OVER"; printf "  %-7s %-11s %7.1f ms wall  %s  budget %6.1f  %s\n", variant, key, m, cpu, budget[key], verdict }
          else { printf "  %-7s %-11s %7.1f ms wall  %s\n", variant, key, m, cpu }
        }
      }' "$TMP/perf.$variant"
  done
}

# ── A11 ─────────────────────────────────────────────────────────────────────
a11() {
  local spec run
  echo "A11 — flat SwiftUI Table re-sorted in place, and a List growing by 200 rows (3 runs each)"
  for spec in tableSort:200 tableSort:1000 listAppend:200 listAppend:400 listAppend:800; do
    local counts=""
    for run in 1 2 3; do
      run_probe "a11:$spec"
      counts="$counts $WARN"
    done
    echo "  $spec warnings per run:$counts"
  done
}

# ── render ──────────────────────────────────────────────────────────────────
render() {
  local dir="$1" fixture size appearance flag
  [ -n "$dir" ] || { echo "usage: scripts/outline-probe.sh render <dir>" >&2; exit 2; }
  mkdir -p "$dir"
  for fixture in plain hosted ticks headers; do
    for size in 900x600 1100x720; do
      for appearance in light dark; do
        flag=""; [ "$appearance" = "dark" ] && flag="--dark"
        # shellcheck disable=SC2086
        run_probe render "$fixture" "$dir/$fixture-$size-$appearance.png" --size "$size" $flag
        cat "$TMP/out"
        [ "$RC" -eq 0 ] || fail
      done
    done
  done
}

# ── check: the subset scripts/check.sh runs ─────────────────────────────────
check() {
  local variant flag action total=0
  for variant in text hosted; do
    flag=""; [ "$variant" = "hosted" ] && flag="--hosted"
    for action in expandAll resort; do
      # shellcheck disable=SC2086
      run_probe "$action" --rows 200,5 $flag
      echo "$action/$variant warnings=$WARN"
      total=$((total + WARN))
      [ "$WARN" -eq 0 ] && [ "$RC" -eq 0 ] || fail
    done
  done
  echo "open all and re-sort, text and hosted: warnings=$total"
}

# timings in a debug build say nothing about the product: a5 and a6 build and run release
case "${1:-all}" in a5|a6) CONFIG_ARGS=(-c release) ;; esac
build
case "${1:-all}" in
  a1) a1 ;;
  a2) a2 ;;
  a3) a3 ;;
  a4) a4 ;;
  a5) a5 ;;
  a6) a6 ;;
  a7) a7 ;;
  a8) a8 ;;
  a11) a11 ;;
  check) check ;;
  render) render "${2:-}" ;;
  all) a1; a2; a3; a4; a5; a6; a7; a8; a11 ;;
  *) echo "usage: scripts/outline-probe.sh a1|a2|a3|a4|a5|a6|a7|a8|a11|check|all" >&2; exit 2 ;;
esac
exit "$FAILED"
