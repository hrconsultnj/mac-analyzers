#!/usr/bin/env bash
# layout-migrate-test.sh — the updater's folder move, on a fake home.
# Proves: a checkout at ~/mac-analyzers moves to ~/sparehold, the files exist
# once, and the old names are removed when the update finishes. A file that
# differs is kept. Nothing here touches the real home.
# Runs under bash and /bin/bash (3.2).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib/layout-migrate.sh"
[[ -f "$LIB" ]] || { echo "SKIP: layout-migrate.sh not found"; exit 0; }

if [[ "${LAYOUT_MIGRATE_INNER:-}" != 1 ]]; then
  status=0
  for sh in bash /bin/bash; do
    echo "== $($sh -c 'printf "%s" "$BASH_VERSION"') =="
    LAYOUT_MIGRATE_INNER=1 "$sh" "$0" || status=1
  done
  exit "$status"
fi

# shellcheck source=../lib/layout-migrate.sh
source "$LIB"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() {
  if [[ "$2" == ok ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 ($2)"
    fail=1
  fi
}
link_to() {
  local path="$1" want="$2" got
  if [[ ! -L "$path" ]]; then
    echo "not a link"
    return
  fi
  got="$(readlink "$path")"
  if [[ "$got" == "$want" ]]; then
    echo ok
  else
    echo "points at $got"
  fi
}

# $1 home under $TMP, $2 directory to migrate. The function can only move
# $HOME/mac-analyzers, and HOME is this fake home.
migrate() {
  local home="$1" dir="$2"
  case "$home" in
    "$TMP"/*) ;;
    *) echo "FAIL  refused a home outside the temp directory ($home)"; exit 1 ;;
  esac
  (
    set -euo pipefail
    export HOME="$home"
    cd "$dir"
    sparehold_migrate_layout
  )
}

# The finished update: the move, then the old names deleted.
finish() {
  local home="$1" dir="$2" where rc=0
  migrate "$home" "$dir" || rc=1
  if [[ -d "$home/sparehold/memory" || -d "$home/sparehold/storage" || -d "$home/sparehold/network" ]]; then
    where="$home/sparehold"
  else
    where="$dir"
  fi
  (
    set -euo pipefail
    export HOME="$home"
    cd "$where"
    sparehold_remove_old_names
  ) || rc=1
  return "$rc"
}

git_quiet() {
  git -c user.email=t@example.invalid -c user.name=test -c commit.gpgsign=false "$@"
}

# --- old names only: rename, link, and move the home folder ---
home="$TMP/old-only"
mkdir -p "$home/mac-analyzers/memory-analyzer" "$home/mac-analyzers/storage-analyzer" "$home/mac-analyzers/network-analyzer"
printf '%s\n' '#!/bin/bash' 'echo ran-guard' > "$home/mac-analyzers/memory-analyzer/memory-guard.sh"
chmod +x "$home/mac-analyzers/memory-analyzer/memory-guard.sh"
printf '%s\n' 'notes' > "$home/mac-analyzers/memory-analyzer/my notes.txt"
printf '%s\n' 'disk' > "$home/mac-analyzers/storage-analyzer/cleanup.sh"
printf '%s\n' 'net' > "$home/mac-analyzers/network-analyzer/network-snapshot.sh"
printf '%s\n' 'KEEP=1' > "$home/mac-analyzers/config.local.sh"
if finish "$home" "$home/mac-analyzers"; then
  check "old layout migrates" ok
else
  check "old layout migrates" "the move failed"
fi
check "home folder is now ~/sparehold" "$([[ -d "$home/sparehold" && ! -L "$home/sparehold" ]] && echo ok || echo "sparehold missing")"
check "the old home name is gone" "$([[ ! -e "$home/mac-analyzers" && ! -L "$home/mac-analyzers" ]] && echo ok || echo "old name remains")"
check "settings came along" "$([[ "$(cat "$home/sparehold/config.local.sh")" == "KEEP=1" ]] && echo ok || echo "settings changed")"
check "memory-analyzer is gone" "$([[ ! -e "$home/sparehold/memory-analyzer" && ! -L "$home/sparehold/memory-analyzer" ]] && echo ok || echo "old folder remains")"
check "storage-analyzer is gone" "$([[ ! -e "$home/sparehold/storage-analyzer" && ! -L "$home/sparehold/storage-analyzer" ]] && echo ok || echo "old folder remains")"
check "network-analyzer is gone" "$([[ ! -e "$home/sparehold/network-analyzer" && ! -L "$home/sparehold/network-analyzer" ]] && echo ok || echo "old folder remains")"
check "a name with a space came along" "$([[ "$(cat "$home/sparehold/memory/my notes.txt")" == "notes" ]] && echo ok || echo "missing")"
ran="$(/bin/bash "$home/sparehold/memory/memory-guard.sh" 2>/dev/null || true)"
check "the script is only in the new folder" "$([[ "$ran" == "ran-guard" ]] && echo ok || echo "got ${ran:-nothing}")"

# --- second run changes nothing ---
before="$(stat -f %i "$home/sparehold")"
if finish "$home" "$home/sparehold"; then
  check "second run is safe" ok
else
  check "second run is safe" "the move failed"
fi
check "second run does not bring the old name back" "$([[ ! -e "$home/mac-analyzers" && ! -L "$home/mac-analyzers" ]] && echo ok || echo "old name returned")"
after="$(stat -f %i "$home/sparehold")"
check "second run does not move the folder again" "$([[ "$before" == "$after" ]] && echo ok || echo "inode changed")"

# --- new layout already, and ~/sparehold is taken: do not move home ---
home="$TMP/taken"
mkdir -p "$home/sparehold" "$home/mac-analyzers/memory" "$home/mac-analyzers/extras/swiftbar-plugin"
printf '%s\n' 'marker' > "$home/sparehold/marker"
printf '%s\n' 'stay' > "$home/mac-analyzers/memory/memory-guard.sh"
printf '%s\n' 'plugin' > "$home/mac-analyzers/extras/swiftbar-plugin/sparehold.5m.sh"
if finish "$home" "$home/mac-analyzers"; then
  check "taken sparehold migrates inside the checkout" ok
else
  check "taken sparehold migrates inside the checkout" "the move failed"
fi
check "checkout stays put when ~/sparehold exists" "$([[ -d "$home/mac-analyzers" && ! -L "$home/mac-analyzers" ]] && echo ok || echo "home was moved")"
check "existing ~/sparehold is untouched" "$([[ "$(cat "$home/sparehold/marker")" == "marker" ]] && echo ok || echo "marker changed")"
check "the suite's old name is gone" "$([[ ! -e "$home/mac-analyzers/memory-analyzer" && ! -L "$home/mac-analyzers/memory-analyzer" ]] && echo ok || echo "old folder remains")"
check "swiftbar's old name is gone" "$([[ ! -e "$home/mac-analyzers/extras/swiftbar-plugin/mac-analyzers.5m.sh" && ! -L "$home/mac-analyzers/extras/swiftbar-plugin/mac-analyzers.5m.sh" ]] && echo ok || echo "old name remains")"

# --- both directories: a file only the old one has moves; a shared name stays ---
home="$TMP/both"
mkdir -p "$home/mac-analyzers/memory" "$home/mac-analyzers/memory-analyzer"
printf '%s\n' 'new' > "$home/mac-analyzers/memory/keep.sh"
printf '%s\n' 'old' > "$home/mac-analyzers/memory-analyzer/keep.sh"
printf '%s\n' 'extra' > "$home/mac-analyzers/memory-analyzer/extra.sh"
if finish "$home" "$home/mac-analyzers"; then
  check "overlap migrates" ok
else
  check "overlap migrates" "the move failed"
fi
root="$home/sparehold"
check "the new file wins" "$([[ "$(cat "$root/memory/keep.sh")" == "new" ]] && echo ok || echo "overwritten")"
check "a file only the old folder had is kept" "$([[ "$(cat "$root/memory/extra.sh")" == "extra" ]] && echo ok || echo "extra missing")"
check "a different file is not deleted" "$([[ -d "$root/memory-analyzer" && ! -L "$root/memory-analyzer" && "$(cat "$root/memory-analyzer/keep.sh")" == "old" ]] && echo ok || echo "old folder was removed")"
check "the moved file is not left behind" "$([[ ! -e "$root/memory-analyzer/extra.sh" ]] && echo ok || echo "extra still in the old folder")"

# --- the same file in both folders is one copy, and the old folder goes ---
home="$TMP/same"
mkdir -p "$home/mac-analyzers/memory" "$home/mac-analyzers/memory-analyzer"
printf '%s\n' 'same' > "$home/mac-analyzers/memory/keep.sh"
printf '%s\n' 'same' > "$home/mac-analyzers/memory-analyzer/keep.sh"
if finish "$home" "$home/mac-analyzers"; then
  check "identical folders migrate" ok
else
  check "identical folders migrate" "the move failed"
fi
check "an identical old folder is removed" "$([[ ! -e "$home/sparehold/memory-analyzer" && ! -L "$home/sparehold/memory-analyzer" ]] && echo ok || echo "old folder remains")"
check "the one copy is in the new folder" "$([[ "$(cat "$home/sparehold/memory/keep.sh")" == "same" ]] && echo ok || echo "missing")"

# --- a checkout that is not ~/mac-analyzers only gets the inner links ---
home="$TMP/elsewhere"
mkdir -p "$home/work/repo/storage"
printf '%s\n' 'disk' > "$home/work/repo/storage/cleanup.sh"
if finish "$home" "$home/work/repo"; then
  check "other location migrates" ok
else
  check "other location migrates" "the move failed"
fi
check "a checkout elsewhere is not moved" "$([[ ! -e "$home/sparehold" && ! -e "$home/mac-analyzers" && -d "$home/work/repo/storage" ]] && echo ok || echo "home changed")"
check "the old suite name is removed there too" "$([[ ! -e "$home/work/repo/storage-analyzer" && ! -L "$home/work/repo/storage-analyzer" && -f "$home/work/repo/storage/cleanup.sh" ]] && echo ok || echo "old name remains")"

# --- git: ignored links stay out of status; without the ignore, no link is made ---
home="$TMP/git-clean"
mkdir -p "$home/mac-analyzers/memory" "$home/mac-analyzers/extras/swiftbar-plugin"
printf '%s\n' 'x' > "$home/mac-analyzers/memory/memory-guard.sh"
printf '%s\n' 'plugin' > "$home/mac-analyzers/extras/swiftbar-plugin/sparehold.5m.sh"
printf '%s\n' '/memory-analyzer' '/storage-analyzer' '/network-analyzer' '/extras/swiftbar-plugin/mac-analyzers.5m.sh' > "$home/mac-analyzers/.gitignore"
(
  cd "$home/mac-analyzers"
  git_quiet init -q
  git_quiet add .gitignore memory/memory-guard.sh extras/swiftbar-plugin/sparehold.5m.sh
  git_quiet commit -q -m fixture
)
if finish "$home" "$home/mac-analyzers"; then
  check "ignored links migrate" ok
else
  check "ignored links migrate" "the move failed"
fi
porcelain="$(git -C "$home/sparehold" status --porcelain)"
check "removing the old names leaves the checkout clean" "$([[ -z "$porcelain" ]] && echo ok || echo "dirty: $porcelain")"
check "the old suite name is gone" "$([[ ! -e "$home/sparehold/memory-analyzer" && ! -L "$home/sparehold/memory-analyzer" ]] && echo ok || echo "old name remains")"

home="$TMP/git-open"
mkdir -p "$home/work/repo/memory"
printf '%s\n' 'x' > "$home/work/repo/memory/memory-guard.sh"
(
  cd "$home/work/repo"
  git_quiet init -q
  git_quiet add memory/memory-guard.sh
  git_quiet commit -q -m fixture
)
if migrate "$home" "$home/work/repo"; then
  check "unignored checkout migrates" ok
else
  check "unignored checkout migrates" "the move failed"
fi
check "a link that git would show is not created" "$([[ ! -e "$home/work/repo/memory-analyzer" && ! -L "$home/work/repo/memory-analyzer" ]] && echo ok || echo "link was created")"
porcelain="$(git -C "$home/work/repo" status --porcelain)"
check "skipping that link leaves the checkout clean" "$([[ -z "$porcelain" ]] && echo ok || echo "dirty: $porcelain")"

# The updater a person already has stays in this folder and, after the pull,
# runs the build, which moves the folder, then looks up memory-analyzer/.
home="$TMP/parent-cwd"
mkdir -p "$home/mac-analyzers/memory-analyzer"
printf '%s\n' '#!/bin/bash' 'echo from-old-path' > "$home/mac-analyzers/memory-analyzer/memory-guard.sh"
chmod +x "$home/mac-analyzers/memory-analyzer/memory-guard.sh"
parent_out="$(
  export HOME="$home"
  cd "$home/mac-analyzers"
  (
    set -euo pipefail
    sparehold_migrate_layout
  )
  ./memory-analyzer/memory-guard.sh
  sparehold_remove_old_names
  if [[ -e ./memory-analyzer || -L ./memory-analyzer || -e "$HOME/mac-analyzers" || -L "$HOME/mac-analyzers" ]]; then
    echo "old-name-remains"
  fi
  ./memory/memory-guard.sh
)"
check "the updater can use the old path until the update finishes" "$([[ "$parent_out" == *from-old-path* && "$parent_out" != *old-name-remains* ]] && echo ok || echo "got ${parent_out:-nothing}")"
check "that updater's folder is ~/sparehold" "$([[ -f "$home/sparehold/memory/memory-guard.sh" ]] && echo ok || echo "not moved")"

exit "$fail"
