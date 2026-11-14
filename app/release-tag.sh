#!/usr/bin/env bash
# release-tag.sh <repo> <version> — which release tag a build counts its commits from, and how many.
# Prints "<tag> <commits since it>", or nothing when no usable tag is in reach.
#
# Counted from the tag of the version in VERSION (`v2.69.0..HEAD`), not from `git describe`: describe only
# finds a tag on this branch's own history, and a release is tagged on main's merge commit, which development
# does not contain — so right after a release it would name the release BEFORE and call an identical tree a
# development build. Counting from the version's own tag gives 0 for that tree whatever the branch layout.
# Only when that tag is not known here (not fetched yet, or VERSION bumped before the release is tagged) does
# it fall back to the nearest tag in history, and only a tag that is a version (vN.N.N) counts: a tag such
# as `v9-junk` or `v2.70.0-rc1` is not a release and is never used.
set -euo pipefail
repo="${1:?usage: release-tag.sh <repo> <version>}"
tag="v${2:?usage: release-tag.sh <repo> <version>}"

if git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
  echo "$tag $(git -C "$repo" rev-list --count "$tag..HEAD" 2>/dev/null || echo 0)"
  exit 0
fi
described="$(git -C "$repo" describe --tags --long --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-*' 2>/dev/null || true)"
if [[ "$described" =~ ^(v[0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-g[0-9a-f]+$ ]]; then
  echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
fi
