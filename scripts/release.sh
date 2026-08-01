#!/usr/bin/env bash
# release.sh — release-on-main: installed as a post-commit AND post-merge git
# hook (scripts/install-git-hooks.sh). Fires on every commit/merge that lands
# on the MAIN branch — i.e. in the main worktree — and aborts anywhere else,
# so commits on development never release.
#
# THEREFORE: any commit or merge on main SHIPS. Cut a release by bumping
# VERSION on development, then merging development → main (in the main
# worktree). Same-version merges are safe: if the tag already exists the hook
# no-ops, so docs-only follow-ups on main don't re-release.
#
# What it does, in order (main only):
#   1. push origin main (no-op if synced)
#   2. build the artifact: `git archive` of main → mac-analyzers-v<V>.tar.gz
#      (tracked files only — reports/, config.local.sh, app builds never ship)
#   3. `gh release create v<V>` with the tarball + auto-generated notes
#
# Guards: MA_RELEASE_RUNNING recursion guard · existing tag/release → skip ·
# gh auth is verified BEFORE any mutation, so a failed auth ships nothing.
# Dry run: MA_RELEASE_DRYRUN=1 prints planned actions only.
set -euo pipefail

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "main" ]] || exit 0
[[ "${MA_RELEASE_RUNNING:-0}" == "1" ]] && exit 0
export MA_RELEASE_RUNNING=1

root="$(git rev-parse --show-toplevel)"
version="$(tr -d ' \n' < "$root/VERSION")"
tag="v${version}"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null || gh release view "$tag" >/dev/null 2>&1; then
  echo "release: $tag already exists — bump VERSION on development to cut a new release."
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "release: gh is not authenticated — run 'gh auth login', then re-run scripts/release.sh from the main worktree." >&2
  exit 1
fi

if [[ "${MA_RELEASE_DRYRUN:-0}" == "1" ]]; then
  echo "release [dry-run]: would push main, tag $tag, attach mac-analyzers-$tag.tar.gz"
  exit 0
fi

echo "release: shipping $tag"
git push origin main

artifact="$(mktemp -d)/mac-analyzers-$tag.tar.gz"
git archive --format=tar.gz --prefix="mac-analyzers/" -o "$artifact" main

gh release create "$tag" "$artifact" \
  --title "mac-analyzers $tag" \
  --generate-notes \
  --notes-start-tag "$(git describe --tags --abbrev=0 2>/dev/null || echo v1.0.0)"

rm -f "$artifact"
echo "release: $tag published — https://github.com/hrconsultnj/mac-analyzers/releases/tag/$tag"
