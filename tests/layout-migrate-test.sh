#!/usr/bin/env bash
# layout-migrate-test.sh — the updater's folder move, on a fake home.
# Proves: old suite folders are renamed and the old names keep working, a
# checkout at ~/mac-analyzers moves to ~/sparehold with the old name left as
# a link, a second run changes nothing, an existing ~/sparehold is left
# alone, a checkout anywhere else is not moved, and the compatibility links
# do not show up as uncommitted changes. Nothing here touches the real home.
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
if migrate "$home" "$home/mac-analyzers"; then
  check "old layout migrates" ok
else
  check "old layout migrates" "the move failed"
fi
check "home folder is now ~/sparehold" "$([[ -d "$home/sparehold" && ! -L "$home/sparehold" ]] && echo ok || echo "sparehold missing")"
check "old home name is a link" "$(link_to "$home/mac-analyzers" sparehold)"
check "settings came along" "$([[ "$(cat "$home/sparehold/config.local.sh")" == "KEEP=1" ]] && echo ok || echo "settings changed")"
check "settings still open under the old name" "$([[ "$(cat "$home/mac-analyzers/config.local.sh")" == "KEEP=1" ]] && echo ok || echo "old path lost them")"
check "memory-analyzer points at memory" "$(link_to "$home/sparehold/memory-analyzer" memory)"
check "storage-analyzer points at storage" "$(link_to "$home/sparehold/storage-analyzer" storage)"
check "network-analyzer points at network" "$(link_to "$home/sparehold/network-analyzer" network)"
check "a name with a space came along" "$([[ "$(cat "$home/sparehold/memory/my notes.txt")" == "notes" ]] && echo ok || echo "missing")"
ran="$(/bin/bash "$home/mac-analyzers/memory-analyzer/memory-guard.sh" 2>/dev/null || true)"
check "the old script path still runs" "$([[ "$ran" == "ran-guard" ]] && echo ok || echo "got ${ran:-nothing}")"
ran="$(/bin/bash "$home/sparehold/memory/memory-guard.sh" 2>/dev/null || true)"
check "the new script path runs" "$([[ "$ran" == "ran-guard" ]] && echo ok || echo "got ${ran:-nothing}")"

# --- second run, from the old name and from the new one, changes nothing ---
before="$(stat -f %i "$home/sparehold")"
if migrate "$home" "$home/mac-analyzers" && migrate "$home" "$home/sparehold"; then
  check "second run is safe" ok
else
  check "second run is safe" "the move failed"
fi
check "second run keeps the home link" "$(link_to "$home/mac-analyzers" sparehold)"
check "second run does not nest the suite link" "$(link_to "$home/sparehold/memory-analyzer" memory)"
after="$(stat -f %i "$home/sparehold")"
check "second run does not move the folder again" "$([[ "$before" == "$after" ]] && echo ok || echo "inode changed")"

# --- new layout already, and ~/sparehold is taken: do not move home ---
home="$TMP/taken"
mkdir -p "$home/sparehold" "$home/mac-analyzers/memory" "$home/mac-analyzers/extras/swiftbar-plugin"
printf '%s\n' 'marker' > "$home/sparehold/marker"
printf '%s\n' 'stay' > "$home/mac-analyzers/memory/memory-guard.sh"
printf '%s\n' 'plugin' > "$home/mac-analyzers/extras/swiftbar-plugin/sparehold.5m.sh"
if migrate "$home" "$home/mac-analyzers"; then
  check "taken sparehold migrates inside the checkout" ok
else
  check "taken sparehold migrates inside the checkout" "the move failed"
fi
check "checkout stays put when ~/sparehold exists" "$([[ -d "$home/mac-analyzers" && ! -L "$home/mac-analyzers" ]] && echo ok || echo "home was moved")"
check "existing ~/sparehold is untouched" "$([[ "$(cat "$home/sparehold/marker")" == "marker" ]] && echo ok || echo "marker changed")"
check "suite link is still made" "$(link_to "$home/mac-analyzers/memory-analyzer" memory)"
check "swiftbar's old name points at the new file" "$(link_to "$home/mac-analyzers/extras/swiftbar-plugin/mac-analyzers.5m.sh" sparehold.5m.sh)"

# --- both directories: a file only the old one has moves; a shared name stays ---
home="$TMP/both"
mkdir -p "$home/mac-analyzers/memory" "$home/mac-analyzers/memory-analyzer"
printf '%s\n' 'new' > "$home/mac-analyzers/memory/keep.sh"
printf '%s\n' 'old' > "$home/mac-analyzers/memory-analyzer/keep.sh"
printf '%s\n' 'extra' > "$home/mac-analyzers/memory-analyzer/extra.sh"
if migrate "$home" "$home/mac-analyzers"; then
  check "overlap migrates" ok
else
  check "overlap migrates" "the move failed"
fi
root="$home/sparehold"
check "the new file wins" "$([[ "$(cat "$root/memory/keep.sh")" == "new" ]] && echo ok || echo "overwritten")"
check "a file only the old folder had is kept" "$([[ "$(cat "$root/memory/extra.sh")" == "extra" ]] && echo ok || echo "extra missing")"
check "the shared file is left in the old folder" "$([[ -d "$root/memory-analyzer" && ! -L "$root/memory-analyzer" && "$(cat "$root/memory-analyzer/keep.sh")" == "old" ]] && echo ok || echo "old folder was removed")"
check "the moved file is not left behind" "$([[ ! -e "$root/memory-analyzer/extra.sh" ]] && echo ok || echo "extra still in the old folder")"

# --- a checkout that is not ~/mac-analyzers only gets the inner links ---
home="$TMP/elsewhere"
mkdir -p "$home/work/repo/storage"
printf '%s\n' 'disk' > "$home/work/repo/storage/cleanup.sh"
if migrate "$home" "$home/work/repo"; then
  check "other location migrates" ok
else
  check "other location migrates" "the move failed"
fi
check "a checkout elsewhere is not moved" "$([[ ! -e "$home/sparehold" && ! -e "$home/mac-analyzers" && -d "$home/work/repo/storage" ]] && echo ok || echo "home changed")"
check "the suite link is made wherever the checkout is" "$(link_to "$home/work/repo/storage-analyzer" storage)"

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
if migrate "$home" "$home/mac-analyzers"; then
  check "ignored links migrate" ok
else
  check "ignored links migrate" "the move failed"
fi
porcelain="$(git -C "$home/sparehold" status --porcelain)"
check "compatibility links are not uncommitted changes" "$([[ -z "$porcelain" ]] && echo ok || echo "dirty: $porcelain")"
check "the ignored suite link exists" "$(link_to "$home/sparehold/memory-analyzer" memory)"

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

exit "$fail"
