#!/usr/bin/env bash
# install-git-hooks.sh — wire scripts/release.sh as post-commit + post-merge.
# Hooks live in the COMMON git dir, so they fire in every worktree — including
# the main release worktree at .composure/workspaces/main, which is where
# development → main merges happen. Run once per clone.
set -euo pipefail
cd "$(dirname "$0")/.."

hooks_dir="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$hooks_dir"

for hook in post-commit post-merge; do
  cat > "$hooks_dir/$hook" <<'EOF'
#!/usr/bin/env bash
# mac-analyzers release-on-main hook — see scripts/release.sh (no-op off main)
exec "$(git rev-parse --show-toplevel)/scripts/release.sh"
EOF
  chmod +x "$hooks_dir/$hook"
  echo "installed: $hooks_dir/$hook"
done
