#!/usr/bin/env bash
# install-git-hooks.sh — wire scripts/release.sh as post-commit + post-merge,
# the What's New gate as pre-merge-commit, and the checks as pre-push.
# Hooks live in the COMMON git dir, so they fire in every worktree — including
# the main release worktree at .composure/workspaces/main, which is where
# development → main merges happen. Run once per clone.
set -euo pipefail
cd "$(dirname "$0")/.."

hooks_dir="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$hooks_dir"

# The release gate, one step earlier: a merge INTO main is refused outright
# when the version it would ship has no fit What's New entry — so a release
# merge made by hand never even lands. (Fast-forward merges skip this hook;
# scripts/release.sh runs the same check before it pushes anything.)
cat > "$hooks_dir/pre-merge-commit" <<'HOOK'
#!/usr/bin/env bash
# mac-analyzers release gate — see scripts/changelog-check.sh (no-op off main)
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || exit 0
top="$(git rev-parse --show-toplevel)"
[[ -x "$top/scripts/changelog-check.sh" ]] || exit 0
version="$(tr -d ' \n' < "$top/VERSION")"
git rev-parse -q --verify "refs/tags/v$version" >/dev/null && exit 0   # not a release merge
exec "$top/scripts/changelog-check.sh" "$version"
HOOK
chmod +x "$hooks_dir/pre-merge-commit"
echo "installed: $hooks_dir/pre-merge-commit"

# The push gate: scripts/check.sh runs the checks whose inputs changed in
# what is being pushed, and a failure stops the push before anything leaves
# this machine. One call per pushed ref; a brand-new branch is measured
# against its merge-base with origin/development (or, with no such base,
# against the empty tree, so every check runs). Docs-only pushes cost
# seconds: only the secrets sweep and the stray-file check always run.
# The checks run on the working tree, which is the pushed commit unless you
# push another commit while holding uncommitted edits — the hook says so.
# It also guards the release push that scripts/release.sh makes from the
# main worktree. (git's own `git push --no-verify` is the only way around it.)
cat > "$hooks_dir/pre-push" <<'HOOK'
#!/usr/bin/env bash
# mac-analyzers push gate — see scripts/check.sh
top="$(git rev-parse --show-toplevel)" || exit 0
[[ -x "$top/scripts/check.sh" ]] || exit 0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX
cd "$top" || exit 0
zero="0000000000000000000000000000000000000000"
status=0
while read -r lref lsha rref rsha; do
  [[ "$lsha" == "$zero" ]] && continue          # deleting a remote ref: nothing to check
  case "$lref" in refs/tags/*) continue ;; esac  # tags carry no new files of their own
  base=""
  if [[ "$rsha" != "$zero" ]] && git cat-file -e "$rsha^{commit}" 2>/dev/null; then
    base="$rsha"
  else
    # new branch (or a remote commit we do not have): measure from where it
    # left origin/development; with no such base, from the empty tree
    base="$(git merge-base "$lsha" origin/development 2>/dev/null)" \
      || base="$(git hash-object -t tree /dev/null)"
  fi
  echo "pre-push: checking ${lref#refs/heads/} -> ${rref#refs/heads/} ($(git rev-parse --short "$base")..$(git rev-parse --short "$lsha"))"
  if [[ "$lsha" != "$(git rev-parse HEAD)" ]]; then
    echo "pre-push: note — $lref is not the checked-out commit; checks run on the working tree"
  fi
  if ! "$top/scripts/check.sh" --changed "$base..$lsha"; then
    echo "pre-push: push refused — fix the failures above, commit, and push again."
    status=1
  fi
done
exit "$status"
HOOK
chmod +x "$hooks_dir/pre-push"
echo "installed: $hooks_dir/pre-push"

for hook in post-commit post-merge; do
  cat > "$hooks_dir/$hook" <<'EOF'
#!/usr/bin/env bash
# mac-analyzers release-on-main hook — see scripts/release.sh (no-op off main)
exec "$(git rev-parse --show-toplevel)/scripts/release.sh"
EOF
  chmod +x "$hooks_dir/$hook"
  echo "installed: $hooks_dir/$hook"
done
