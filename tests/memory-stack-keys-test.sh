#!/usr/bin/env bash
# memory-stack-keys-test.sh — an orphaned Docker/Supabase stack is a reviewed row
# in memory-auto-clean.sh, keyed `stack=<key>` in its output and `stack:<key>` in
# the reviewed list (never a pid). With a list the stack is stopped only when its
# key is in it; with no list (the guard, a Terminal run) it is as it always was.
#
# DRY RUNS ONLY: the gate is the same test an apply makes (it comes before the
# dry-run branch), so a preview with a list shows what an apply would do without
# touching a process. HOME is a temp folder, `docker` is a stand-in that only
# logs, the supabase project is a fixture folder, and notifications are a no-op
# in a copy of the script. The stack pass needs bash 4+, so `/bin/bash` (3.2)
# re-execs into a newer bash when there is one, as in production.
#
# Usage: tests/memory-stack-keys-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../memory-analyzer/memory-auto-clean.sh"
[[ -f "$SCRIPT" ]] || { echo "SKIP: script not found"; exit 0; }
NEWER=""
for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x "$b" ]] && NEWER="$b" && break; done
[[ -n "$NEWER" ]] || { echo "SKIP: no bash 4+ on this Mac, so the stack pass is not part of the script"; exit 0; }
command -v python3 >/dev/null || { echo "SKIP: python3 is needed to make the stand-in Docker socket"; exit 0; }

TMP="$(mktemp -d /tmp/mst.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }

mkdir -p "$TMP/tree/memory-analyzer" "$TMP/tree/lib" "$TMP/stubs" "$TMP/home/.orbstack/run" \
         "$TMP/repos/site/.git" "$TMP/repos/site/supabase"
cp "$SCRIPT" "$TMP/tree/memory-analyzer/memory-auto-clean.sh"
cp "$HERE"/../lib/*.sh "$TMP/tree/lib/"                       # the live-session exemption is part of the script
printf 'notify() { :; }\n' > "$TMP/tree/lib/notify.sh"       # ...but nobody is notified
printf 'project_id = "demo"\n' > "$TMP/repos/site/supabase/config.toml"
python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$TMP/home/.orbstack/run/docker.sock"
cat > "$TMP/stubs/docker" <<'STUB'
#!/bin/bash
if [[ "$1" == "ps" ]]; then
  echo "c1|supabase_db_demo|demo|||"
  echo "c2|supabase_auth_demo|demo|||"
  exit 0
fi
echo "docker $*" >> "$STUB_LOG"
STUB
chmod +x "$TMP/stubs/docker"

printf 'stack:supabase:demo\n' > "$TMP/list-key"
printf 'stack:supabase:other\n99999\n' > "$TMP/list-other"
printf '99999\n' > "$TMP/list-pid"

run() { # label shell [listfile]
  local label="$1" sh="$2" list="${3:-}" args=(--dev --dry-run)
  [[ -n "$list" ]] && args+=(--only-pids "$list")
  : > "$TMP/docker.calls"
  STUB_LOG="$TMP/docker.calls" HOME="$TMP/home" PATH="$TMP/stubs:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    ANALYZERS_DEV_STOP_IDLE_STACKS=1 ANALYZERS_STACK_IDLE_MIN=0 ANALYZERS_STACK_REPO_ROOTS="$TMP/repos" \
    ANALYZERS_STACK_STATE_FILE="$TMP/state" "$sh" "$TMP/tree/memory-analyzer/memory-auto-clean.sh" "${args[@]}" \
    > "$TMP/$label.out" 2>&1
}
dry_rows() { grep -c '^ *\[DRY\] *stack=supabase:demo ' "$TMP/$1.out"; }
skip_rows() { grep -c '^ *\[SKIP\] .*stack=supabase:demo ' "$TMP/$1.out"; }

for sh in "$NEWER" /bin/bash; do
  k="$(echo "$sh" | tr / _)"
  run "nolist$k" "$sh"
  check "[$sh] no list: the stack is a row, as always" "$([[ "$(dry_rows "nolist$k")" -eq 1 ]] && echo ok || echo "$(dry_rows "nolist$k") rows")"
  run "key$k" "$sh" "$TMP/list-key"
  check "[$sh] its key in the list: the stack would be stopped" "$([[ "$(dry_rows "key$k")" -eq 1 && "$(skip_rows "key$k")" -eq 0 ]] && echo ok || echo "dry $(dry_rows "key$k"), skip $(skip_rows "key$k")")"
  run "other$k" "$sh" "$TMP/list-other"
  check "[$sh] another stack's key and a pid in the list: this stack is skipped" "$([[ "$(skip_rows "other$k")" -eq 1 && "$(dry_rows "other$k")" -eq 0 ]] && echo ok || echo "dry $(dry_rows "other$k"), skip $(skip_rows "other$k")")"
  run "pid$k" "$sh" "$TMP/list-pid"
  check "[$sh] a list of pids only: this stack is skipped" "$([[ "$(skip_rows "pid$k")" -eq 1 ]] && echo ok || echo "skip $(skip_rows "pid$k")")"
  check "[$sh] nothing was stopped by any of these previews" "$([[ ! -s "$TMP/docker.calls" ]] && echo ok || cat "$TMP/docker.calls")"
done
exit $fail
