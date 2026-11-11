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
  stub "$d" xcrun 'if [[ "$*" == "simctl list devices unavailable" ]]; then echo "    iPhone 14 (A) (Shutdown) (unavailable, runtime profile not found)"; elif [[ "$*" == "simctl delete unavailable" ]]; then echo "xcrun $*" >> "$STUB_LOG"; fi'
done
stub "$TMP/stubs" pnpm 'echo "pnpm $*" >> "$STUB_LOG"'

# run <label> <shell> <stubdir> <dry|apply> [listfile]  → calls the tools received, one per line, in $TMP/<label>.calls
run() {
  local label="$1" sh="$2" stubs="$3" mode="$4" list="${5:-}"
  local args=(--mode deep --roots "$TMP/root" --docker-running-only)
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
  run "nop-$k" "$sh" "$TMP/stubs-nopnpm" dry
  check "[$sh] a tool that is not installed has no row" "$([[ "$(grep -c 'prune:pnpm' "$TMP/nop-$k.out")" -eq 0 ]] && echo ok || echo "pnpm row shown")"
done
exit $fail
