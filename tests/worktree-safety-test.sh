#!/usr/bin/env bash
# worktree-safety-test.sh — storage-auto-clean.sh never harms a checkout:
#   1. every .composure/workspaces/ folder, in every repo, is skipped whole —
#      its worktrees, node_modules and build folders are never cleaned;
#   2. a worktree with uncommitted or untracked changes is never parked or
#      removed (no refs/parked/*, no reset, the folder stays exactly as it is);
#   3. only gitignored build output goes: a committed `build/` or `dist/`, a
#      build folder outside any checkout, and an ignored .env all stay; the
#      checkout itself is never removed.
# Everything happens in a temp folder with HOME pointed at it and a copy of the
# script (notifications a no-op). Runs the deep clean in dry run and apply,
# under `bash` and /bin/bash (3.2).
#
# Usage: tests/worktree-safety-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../storage/storage-auto-clean.sh"
[[ -f "$SCRIPT" ]] || { echo "SKIP: script not found"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not installed"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }
present() { [[ -e "$1" ]] && echo ok || echo "missing: ${1#"$TMP"/}"; }
absent()  { [[ -e "$1" ]] && echo "still there: ${1#"$TMP"/}" || echo ok; }

mkdir -p "$TMP/tree/storage" "$TMP/tree/lib" "$TMP/home" "$TMP/bin"
# git and nothing else from outside the system folders: no package manager or Docker runs
ln -s "$(command -v git)" "$TMP/bin/git"
cp "$SCRIPT" "$TMP/tree/storage/storage-auto-clean.sh"
cp "$HERE"/../lib/*.sh "$TMP/tree/lib/"
printf 'notify() { :; }\n' > "$TMP/tree/lib/notify.sh"

g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=development "$@" >/dev/null 2>&1; }
old() { touch -h -t 202601010000 "$1"; find "$1" -exec touch -h -t 202601010000 {} + 2>/dev/null; }

# build <root>: one repo with five worktrees and the folders around them
build() {
  local R="$1/repo"
  mkdir -p "$R"
  g -C "$R" init
  printf 'node_modules/\n.next/\n.env\n' > "$R/.gitignore"
  mkdir -p "$R/build" "$R/src"; echo 'echo hi' > "$R/build/run.sh"; echo 'x' > "$R/src/a.ts"   # a committed build/ folder
  g -C "$R" add -A; g -C "$R" commit -m init
  for b in clean dirty untracked ws other; do g -C "$R" branch "$b"; done
  g -C "$R" worktree add "$R/../wt-clean" clean
  g -C "$R" worktree add "$R/../wt-dirty" dirty
  g -C "$R" worktree add "$R/../wt-untracked" untracked
  mkdir -p "$R/.composure/workspaces"
  g -C "$R" worktree add "$R/.composure/workspaces/agent" ws
  local w
  for w in "$R/../wt-clean" "$R/../wt-dirty" "$R/../wt-untracked" "$R/.composure/workspaces/agent"; do
    mkdir -p "$w/node_modules/pkg" "$w/.next/cache"; echo m > "$w/node_modules/pkg/i.js"; echo n > "$w/.next/cache/c"
    echo 'SECRET=1' > "$w/.env"
  done
  echo 'edit' >> "$R/../wt-dirty/src/a.ts"
  echo 'new' > "$R/../wt-untracked/notes.md"
  # an agent workspace's own node_modules and build cache under the primary checkout too
  mkdir -p "$R/.composure/workspaces/loose/node_modules/x" "$R/.composure/workspaces/loose/.next"
  # a build folder outside any git checkout
  mkdir -p "$1/plain/dist"; echo d > "$1/plain/dist/out.js"
  old "$1"
}

# run <label> <shell> <dry|apply>
run() {
  local args=(--mode deep --roots "$TMP/$1" --worktree-idle-days 1 --cache-age-days 1 --nm-age-days 1)
  [[ "$3" == apply ]] && args+=(--apply)
  HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$2" "$TMP/tree/storage/storage-auto-clean.sh" "${args[@]}" > "$TMP/$1.out" 2>&1
}

for sh in bash /bin/bash; do
  [[ "$sh" == /bin/bash && ! -x /bin/bash ]] && continue
  tag="$(basename "$sh")-$([[ "$sh" == /* ]] && echo sys || echo path)"
  for mode in dry apply; do
    label="$tag-$mode"; mkdir -p "$TMP/$label"; build "$TMP/$label"
    R="$TMP/$label/repo"
    run "$label" "$sh" "$mode"
    log="$TMP/$label.out"
    # 1. the agent workspace is never touched, nor named for removal
    check "[$label] workspace worktree kept whole" "$(present "$R/.composure/workspaces/agent/node_modules/pkg/i.js")"
    check "[$label] workspace build cache kept" "$(present "$R/.composure/workspaces/agent/.next/cache/c")"
    check "[$label] loose workspace node_modules kept" "$(present "$R/.composure/workspaces/loose/node_modules/x")"
    if grep -E '\[(DRY|DELETED)\]' "$log" | grep -q '\.composure/workspaces'; then
      check "[$label] no workspace path listed for removal" "listed"
    else
      check "[$label] no workspace path listed for removal" ok
    fi
    # 2. uncommitted and untracked changes: nothing parked, nothing removed
    check "[$label] dirty worktree kept with its edit" "$(grep -q edit "$R/../wt-dirty/src/a.ts" && echo ok || echo 'edit gone')"
    check "[$label] dirty worktree node_modules kept (any section)" "$(present "$R/../wt-dirty/node_modules/pkg/i.js")"
    check "[$label] untracked file kept" "$(present "$R/../wt-untracked/notes.md")"
    check "[$label] untracked worktree node_modules kept" "$(present "$R/../wt-untracked/node_modules/pkg/i.js")"
    check "[$label] nothing parked" "$([[ -z "$(git -C "$R" for-each-ref refs/parked)" ]] && echo ok || echo 'refs/parked written')"
    check "[$label] every worktree still registered" "$([[ "$(git -C "$R" worktree list | grep -c .)" -eq 5 ]] && echo ok || echo "$(git -C "$R" worktree list | grep -c .) left")"
    # 3. only gitignored build output
    check "[$label] committed build/ kept" "$(present "$R/build/run.sh")"
    check "[$label] build folder outside git kept" "$(present "$TMP/$label/plain/dist/out.js")"
    check "[$label] clean worktree checkout kept" "$(present "$R/../wt-clean/src/a.ts")"
    check "[$label] clean worktree .env kept" "$(present "$R/../wt-clean/.env")"
    if [[ "$mode" == apply ]]; then
      check "[$label] clean worktree node_modules cleared" "$(absent "$R/../wt-clean/node_modules")"
      check "[$label] clean worktree .next cleared" "$(absent "$R/../wt-clean/.next")"
    else
      check "[$label] dry run lists the clean worktree's node_modules" \
        "$(grep -E '\[DRY\]' "$log" | grep -q 'wt-clean/node_modules' && echo ok || echo 'not listed')"
      check "[$label] dry run changes nothing" "$(present "$R/../wt-clean/node_modules/pkg/i.js")"
    fi
    [[ $fail -eq 0 ]] || { echo "--- log ($label) ---"; cat "$log"; }
  done
done

exit $fail
