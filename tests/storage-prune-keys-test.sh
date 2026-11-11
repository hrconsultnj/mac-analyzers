#!/usr/bin/env bash
# storage-prune-keys-test.sh — the prunes in storage-auto-clean.sh that are not
# paths (pnpm, npm, Homebrew, unavailable simulators, Docker) are reviewed rows
# keyed `prune:<id>`. With a reviewed list each runs only when its key is in the
# list; with no list (the schedule, a Terminal run) each runs as it always has;
# a tool that is not installed has no row. Stand-in tools in a temp folder only
# log what they were asked; HOME is a temp folder and notifications are a no-op
# in a copy of the script. Runs the script under `bash` and /bin/bash (3.2).
#
# Usage: tests/storage-prune-keys-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../storage-analyzer/storage-auto-clean.sh"
[[ -f "$SCRIPT" ]] || { echo "SKIP: script not found"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }

mkdir -p "$TMP/tree/storage-analyzer" "$TMP/tree/lib" "$TMP/stubs" "$TMP/stubs-nopnpm" "$TMP/home" "$TMP/root"
cp "$SCRIPT" "$TMP/tree/storage-analyzer/storage-auto-clean.sh"
cp "$HERE"/../lib/*.sh "$TMP/tree/lib/"                       # the reviewed-list reader is part of the script
printf 'notify() { :; }\n' > "$TMP/tree/lib/notify.sh"
stub() { printf '#!/bin/bash\n%s\n' "$3" > "$1/$2"; chmod +x "$1/$2"; }
for d in "$TMP/stubs" "$TMP/stubs-nopnpm"; do
  stub "$d" npm 'echo "npm $*" >> "$STUB_LOG"'
  stub "$d" brew 'if [[ "$1" == cleanup && "$2" == -n ]]; then echo "This operation would free approximately 1GB of disk space."; else echo "brew $*" >> "$STUB_LOG"; fi'
  stub "$d" docker '[[ "$1" == info ]] && exit 0; [[ "$1" == context ]] && exit 0; echo "docker $*" >> "$STUB_LOG"'
  stub "$d" tmutil 'if [[ "$1" == listlocalsnapshots ]]; then echo "com.apple.TimeMachine.2026-11-11-010101.local"; echo "com.apple.TimeMachine.2026-11-11-020202.local"; fi'
  stub "$d" sudo 'echo "sudo $*" >> "$STUB_LOG"'
  stub "$d" xcrun 'if [[ "$*" == "simctl list devices unavailable" ]]; then echo "    iPhone 14 (A) (Shutdown) (unavailable, runtime profile not found)"; elif [[ "$*" == "simctl delete unavailable" ]]; then echo "xcrun $*" >> "$STUB_LOG"; fi'
done
stub "$TMP/stubs" pnpm 'echo "pnpm $*" >> "$STUB_LOG"'
# a toolbox where npm fails and sudo refuses (no sudoers rule): the run must say what happened
mkdir -p "$TMP/stubs-fail"
cp "$TMP/stubs"/* "$TMP/stubs-fail/"
stub "$TMP/stubs-fail" npm 'echo "npm $*" >> "$STUB_LOG"; exit 1'
stub "$TMP/stubs-fail" sudo 'echo "sudo $*" >> "$STUB_LOG"; exit 1'

# run <label> <shell> <stubdir> <dry|apply> [listfile]  → calls the tools received, one per line, in $TMP/<label>.calls
run() {
  local label="$1" sh="$2" stubs="$3" mode="$4" list="${5:-}"
  local args=(--mode deep --roots "$TMP/root" --docker-running-only)
  [[ -n "${EXTRA:-}" ]] && args+=("$EXTRA")
  [[ "$mode" == apply ]] && args+=(--apply)
  [[ -n "$list" ]] && args+=(--only-paths "$list")
  : > "$TMP/$label.calls"
  STUB_LOG="$TMP/$label.calls" HOME="$TMP/home" ANALYZERS_TOOL_CACHES=brew,simulators \
    PATH="$stubs:/usr/bin:/bin:/usr/sbin:/sbin" "$sh" "$TMP/tree/storage-analyzer/storage-auto-clean.sh" "${args[@]}" \
    > "$TMP/$label.out" 2>&1
}
calls() { grep -v '^docker context' "$TMP/$1.calls" | tr '\n' ';'; }

printf 'prune:pnpm\n' > "$TMP/list-pnpm"
printf '/some/path\n' > "$TMP/list-none"
printf 'prune:pnpm\nprune:npm\nprune:brew\nprune:simulators\nprune:docker\n' > "$TMP/list-all"
printf 'prune:snapshots\n' > "$TMP/list-snap"
ALL='pnpm store prune;npm cache clean --force;brew cleanup --prune=all -s;xcrun simctl delete unavailable;docker system prune -f;'

for sh in bash /bin/bash; do
  k="$(echo "$sh" | tr / _)"
  run "prev-$k" "$sh" "$TMP/stubs" dry
  check "[$sh] a preview calls no prune" "$([[ -z "$(calls "prev-$k")" ]] && echo ok || calls "prev-$k")"
  rows="$(grep -c '^ *\[DRY\] *prune:' "$TMP/prev-$k.out")"
  check "[$sh] the preview lists the five prunes as rows with a key" "$([[ "$rows" -eq 5 ]] && echo ok || echo "$rows rows")"
  run "nolist-$k" "$sh" "$TMP/stubs" apply
  check "[$sh] no list at all: every prune runs, as before" "$([[ "$(calls "nolist-$k")" == "$ALL" ]] && echo ok || calls "nolist-$k")"
  run "one-$k" "$sh" "$TMP/stubs" apply "$TMP/list-pnpm"
  check "[$sh] only the pnpm key listed: only pnpm runs" "$([[ "$(calls "one-$k")" == 'pnpm store prune;' ]] && echo ok || calls "one-$k")"
  run "none-$k" "$sh" "$TMP/stubs" apply "$TMP/list-none"
  check "[$sh] a list with no prune key: no prune runs" "$([[ -z "$(calls "none-$k")" ]] && echo ok || calls "none-$k")"
  run "all-$k" "$sh" "$TMP/stubs" apply "$TMP/list-all"
  check "[$sh] every key listed: each prune runs once" "$([[ "$(calls "all-$k")" == "$ALL" ]] && echo ok || calls "all-$k")"
  # Time Machine thinning is a reviewed row too (Deep only, with --prune-snapshots)
  EXTRA=--prune-snapshots run "snapdry-$k" "$sh" "$TMP/stubs" dry
  check "[$sh] a deep preview lists the snapshot thinning as a keyed row" "$([[ "$(grep -c '^ *\[DRY\] *prune:snapshots' "$TMP/snapdry-$k.out")" -eq 1 ]] && echo ok || echo "no row")"
  check "[$sh] a preview thins nothing" "$([[ "$(grep -c '^sudo' "$TMP/snapdry-$k.calls")" -eq 0 ]] && echo ok || echo thinned)"
  EXTRA=--prune-snapshots run "snapno-$k" "$sh" "$TMP/stubs" apply
  check "[$sh] no list: snapshots are thinned, as before" "$([[ "$(grep -c 'sudo -n /usr/bin/tmutil thinlocalsnapshots' "$TMP/snapno-$k.calls")" -eq 1 ]] && echo ok || echo "not thinned")"
  EXTRA=--prune-snapshots run "snapother-$k" "$sh" "$TMP/stubs" apply "$TMP/list-pnpm"
  check "[$sh] a list without the snapshots key: nothing is thinned, and the run says so" "$([[ "$(grep -c '^sudo' "$TMP/snapother-$k.calls")" -eq 0 && "$(grep -c 'SKIP.*prune:snapshots' "$TMP/snapother-$k.out")" -eq 1 ]] && echo ok || echo "thinned or silent")"
  EXTRA=--prune-snapshots run "snapyes-$k" "$sh" "$TMP/stubs" apply "$TMP/list-snap"
  check "[$sh] the snapshots key listed: they are thinned" "$([[ "$(grep -c 'sudo -n /usr/bin/tmutil thinlocalsnapshots' "$TMP/snapyes-$k.calls")" -eq 1 ]] && echo ok || echo "not thinned")"
  # what a prune did is said, not assumed: done / failed lines, and a thinning that sudo refused is not "thinned"
  check "[$sh] a prune that worked says done" "$([[ "$(grep -c '^ *done: pnpm store prune' "$TMP/all-$k.out")" -eq 1 ]] && echo ok || echo "no done line")"
  EXTRA=--prune-snapshots run "failing-$k" "$sh" "$TMP/stubs-fail" apply "$TMP/list-all"
  check "[$sh] a prune that failed says failed, with its exit status" "$([[ "$(grep -c '^ *failed: npm cache clean --force (exit 1)' "$TMP/failing-$k.out")" -eq 1 ]] && echo ok || echo "no failed line")"
  EXTRA=--prune-snapshots run "refuse-$k" "$sh" "$TMP/stubs-fail" apply "$TMP/list-snap"
  check "[$sh] snapshots the sudoers rule refuses are not reported as thinned" "$([[ "$(grep -c 'thinned' "$TMP/refuse-$k.out")" -eq 0 && "$(grep -c 'snapshot thin needs the tmutil-thin sudoers rule' "$TMP/refuse-$k.out")" -ge 1 ]] && echo ok || echo "wrong report")"
  check "[$sh] snapshots thinned for real are reported as thinned" "$([[ "$(grep -c 'thinned 2 local snapshot' "$TMP/snapyes-$k.out")" -eq 1 ]] && echo ok || echo "no thinned line")"
  run "nop-$k" "$sh" "$TMP/stubs-nopnpm" dry
  check "[$sh] a tool that is not installed has no row" "$([[ "$(grep -c 'prune:pnpm' "$TMP/nop-$k.out")" -eq 0 ]] && echo ok || echo "pnpm row shown")"
done
exit $fail
