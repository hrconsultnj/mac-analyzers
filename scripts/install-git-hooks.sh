#!/usr/bin/env bash
# install-git-hooks.sh — wire scripts/release.sh as post-commit + post-merge,
# and the What's New gate as pre-merge-commit.
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

for hook in post-commit post-merge; do
  cat > "$hooks_dir/$hook" <<'EOF'
#!/usr/bin/env bash
# mac-analyzers release-on-main hook — see scripts/release.sh (no-op off main)
exec "$(git rev-parse --show-toplevel)/scripts/release.sh"
EOF
  chmod +x "$hooks_dir/$hook"
  echo "installed: $hooks_dir/$hook"
done
