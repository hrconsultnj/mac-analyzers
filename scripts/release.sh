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
#   3. tag v<V> on main here and push the tag, then `gh release create v<V>`
#      on that tag with the tarball, and the What's New entry for this
#      version from CHANGELOG.md as the release notes
#
# Guards: MA_RELEASE_RUNNING recursion guard · existing tag/release → skip ·
# gh auth is verified BEFORE any mutation, so a failed auth ships nothing ·
# NO CHANGELOG ENTRY, NO RELEASE: scripts/changelog-check.sh must pass for
# this version before anything is pushed. Notes are never auto-generated
# from commit subjects — those are written for whoever reads the code.
#
# The normal way in is scripts/cut-release.sh, which runs the same check
# before it changes anything; this is the backstop for a merge done by hand.
# Dry run: MA_RELEASE_DRYRUN=1 prints planned actions only.
set -euo pipefail

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "main" ]] || exit 0
[[ "${MA_RELEASE_RUNNING:-0}" == "1" ]] && exit 0
export MA_RELEASE_RUNNING=1

root="$(git rev-parse --show-toplevel)"
version="$(tr -d ' \n' < "$root/VERSION")"
tag="v${version}"

main_commit="$(git rev-parse main)"

# A later commit on main with the SAME version needs no release: that
# version's tag already sits on an earlier commit of main. Decided from local
# refs alone, before any network call, so it holds offline and when GitHub is
# slow or erroring — and nothing is pushed for it.
if tagged="$(git rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null)" \
   && [[ "$tagged" != "$main_commit" ]] \
   && git merge-base --is-ancestor "$tagged" "$main_commit"; then
  echo "release: $tag is already released (tagged on ${tagged:0:7}) — this commit needs no release. Bump VERSION on development to cut a new one."
  exit 0
fi

# Otherwise "already released" means the RELEASE exists on GitHub and is
# published. A tag on main's own commit does not: this script creates the tag
# itself (below), so a run that stopped between tagging and publishing must be
# able to finish when it is run again. A draft left behind by a failed upload
# is not a release either — say so instead of calling it done.
release_state="$(gh release view "$tag" --json isDraft -q .isDraft 2>/dev/null || true)"
if [[ "$release_state" == "false" ]]; then
  echo "release: $tag already exists — bump VERSION on development to cut a new release."
  exit 0
elif [[ "$release_state" == "true" ]]; then
  echo "release: $tag exists on GitHub only as a DRAFT — an earlier run did not finish publishing it." >&2
  echo "Publish it:  gh release edit $tag --draft=false     or delete it (gh release delete $tag) and run scripts/release.sh again." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "release: gh is not authenticated — run 'gh auth login', then re-run scripts/release.sh from the main worktree." >&2
  exit 1
fi

if ! "$root/scripts/changelog-check.sh" "$version"; then
  echo "release: NOT shipping $tag — nothing was pushed." >&2
  echo "Add or fix the v$version entry in CHANGELOG.md on development, then run" >&2
  echo "scripts/cut-release.sh $version again (it merges the fix and retries)." >&2
  exit 1
fi
title="$("$root/scripts/changelog-check.sh" --title "$version")"

if [[ "${MA_RELEASE_DRYRUN:-0}" == "1" ]]; then
  echo "release [dry-run]: would push main, tag $tag, attach mac-analyzers-$tag.tar.gz"
  exit 0
fi

echo "release: shipping $tag"
git push origin main

artifact="$(mktemp -d)/mac-analyzers-$tag.tar.gz"
git archive --format=tar.gz --prefix="mac-analyzers/" -o "$artifact" main

notes="$(mktemp)"
"$root/scripts/changelog-check.sh" --print "$version" > "$notes"

# Create the tag HERE and push it, instead of letting GitHub create it with
# the release. A tag GitHub makes exists only there until someone fetches;
# until then every build on this Mac counts from the previous release and
# calls itself a Dev Build, although it is exactly this release. With the tag
# made locally first, a build is right the moment the release ships.
if existing="$(git rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null)"; then
  if [[ "$existing" != "$main_commit" ]]; then
    # Not an earlier commit of main (that case stopped above): a tag of this
    # name on some other line of history.
    echo "release: a local tag $tag points at ${existing:0:7}, which is not main (${main_commit:0:7}) or an earlier commit of it." >&2
    echo "If $tag is already a published release, this commit needs no release. Otherwise remove the stray tag (git tag -d $tag) and run scripts/release.sh again." >&2
    exit 1
  fi
else
  git tag "$tag" "$main_commit"
fi
git push origin "refs/tags/$tag"

gh release create "$tag" "$artifact" \
  --verify-tag \
  --title "Mac Analyzers $tag — $title" \
  --notes-file "$notes"

rm -f "$artifact" "$notes"
echo "release: $tag published — https://github.com/hrconsultnj/mac-analyzers/releases/tag/$tag"
