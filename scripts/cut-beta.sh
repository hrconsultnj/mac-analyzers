#!/usr/bin/env bash
# cut-beta.sh — publish a beta: a GitHub PRE-release anyone can follow from the Beta channel.
#
#   scripts/cut-beta.sh                  # the next beta of the next version (2.72.0 released → 2.72.1 Beta, then Beta 2 …)
#   scripts/cut-beta.sh 2.73.0           # a beta of a specific upcoming version
#   scripts/cut-beta.sh --dry-run        # show every step, change nothing
#   scripts/cut-beta.sh --yes            # skip the "does this read well?" question
#
# A beta is the current commit of `development`, tagged v<version>-beta.<n> and published as a GitHub
# pre-release whose notes are the "## Next" section of CHANGELOG.md. It never touches main, VERSION or the
# stable release flow (scripts/cut-release.sh), and GitHub never offers a pre-release as the latest release, so
# the Releases channel and the update notification never see it. Beta follows the newest pre-release; when the
# release of that version ships, Beta offers the release.
#
# It stops at the first thing that is not right, before anything has been changed:
#   1. you are on `development` with nothing uncommitted, and every repository check passes (scripts/check.sh)
#   2. the version is newer than the latest release, and this commit is not already a beta
#   3. "## Next" has notes fit to show people: the same release-notes rules cut-release applies
#      (scripts/changelog-check.sh), and at least one note
#   4. then: push development and create the pre-release, which makes the tag on GitHub in the same step, so a tag
#      never exists without its pre-release; the tag is then fetched here. If creating it fails, nothing was tagged
#      anywhere and running this again finishes the job.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

target=""
dry_run=0
assume_yes=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    --yes|-y) assume_yes=1 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "usage: scripts/cut-beta.sh [version] [--dry-run] [--yes]" >&2; exit 2 ;;
    *) target="$arg" ;;
  esac
done

say() { echo "→ $*"; }
run() {
  if (( dry_run )); then echo "  [dry-run] $*"; else "$@"; fi
}

# ── 1. where we are ────────────────────────────────────────────────────────
branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != "development" ]]; then
  echo "cut-beta: betas are cut from development — this checkout is on '$branch'." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "cut-beta: there are uncommitted changes — commit them first, so the beta is exactly what is in git:" >&2
  git status --short >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "cut-beta: gh is not authenticated — run 'gh auth login', then run this again. Nothing was changed." >&2
  exit 1
fi

say "running every check (scripts/check.sh)"
if ! scripts/check.sh; then
  echo "cut-beta: a check failed — fix it first. Nothing was changed." >&2
  exit 1
fi

# ── 2. which beta ──────────────────────────────────────────────────────────
current="$(tr -d ' \n' < VERSION)"
if [[ -n "$target" ]]; then
  version="${target#v}"
elif git rev-parse -q --verify "refs/tags/v$current" >/dev/null; then
  # the version in VERSION is released: the beta leads to the next patch
  IFS=. read -r major minor patch <<<"$current"
  version="$major.$minor.$((patch + 1))"
else
  # VERSION was bumped ahead of its release: the beta leads to that release
  version="$current"
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "cut-beta: '$version' is not a version (expected 2.73.0)." >&2
  exit 1
fi
# newer than the latest release, by number: a beta leads to a release that is not out yet
newest_release="$(git tag --list 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)"
if [[ -n "$newest_release" ]]; then
  higher="$(printf '%s\n%s\n' "${newest_release#v}" "$version" | sort -V | tail -n 1)"
  if [[ "$higher" != "$version" || "${newest_release#v}" == "$version" ]]; then
    echo "cut-beta: $version is not newer than the latest release (${newest_release#v}) — a beta leads to a release that is not out yet." >&2
    exit 1
  fi
fi

# the next beta number: one past the highest this Mac and GitHub know of
pattern="^v${version//./\\.}-beta\\.[0-9]+\$"
known="$({ git tag --list "v$version-beta.*"; git ls-remote --tags origin "refs/tags/v$version-beta.*" 2>/dev/null | sed 's|.*refs/tags/||; s|\^{}$||'; } || true)"
last="$(grep -E "$pattern" <<<"$known" | sed 's/.*-beta\.//' | sort -n | tail -n 1 || true)"
number=$(( ${last:-0} + 1 ))
tag="v$version-beta.$number"
if (( number > 1 )); then name="$version Beta $number"; else name="$version Beta"; fi

# this commit must be new: a beta tag already on it (here, or on GitHub) means there is nothing to publish
head_commit="$(git rev-parse HEAD)"
existing="$({ git tag --points-at HEAD --list 'v*-beta.*'; git ls-remote --tags origin 'refs/tags/v*-beta.*' 2>/dev/null | awk -v head="$head_commit" '$1 == head { sub(".*refs/tags/", "", $2); print $2 }'; } | head -n 1 || true)"
if [[ -n "$existing" ]]; then
  echo "cut-beta: this commit is already published as $existing — commit something new first." >&2
  exit 1
fi
say "publishing $tag ($name), from development at $(git rev-parse --short HEAD)"

# ── 3. the notes: "## Next", from its first bullet, without the What's New tags ──
notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
{
  echo "This is a beta of Mac Analyzers $version, published ahead of the release for people who follow the Beta channel. It is what is already in the next release:"
  echo
  awk '
    /^## Next/ { inside = 1; next }
    inside && /^## v[0-9]/ { exit }
    inside && /^[[:space:]]*[-*][[:space:]]/ { started = 1 }
    inside && started { print }
  ' CHANGELOG.md | sed -E '/^[[:space:]]*<!--[[:space:]]*wn:.*-->[[:space:]]*$/d; s/[[:space:]]*<!--[[:space:]]*wn:.*-->[[:space:]]*$//'
} > "$notes"
if ! grep -qE '^[[:space:]]*[-*][[:space:]]' "$notes"; then
  echo "cut-beta: '## Next' in CHANGELOG.md has no notes yet — a beta needs something to say. Nothing was changed." >&2
  exit 1
fi
# the same prose rules a release's notes pass (no code names, no source files, full sentences, tags present):
# the notes are judged as a release entry of this version, on a copy, before anything is changed
gate="$(mktemp)"
{
  printf '# What'"'"'s New\n\n## v%s — Beta of the next release\n\n' "$version"
  awk '
    /^## Next/ { inside = 1; next }
    inside && /^## v[0-9]/ { exit }
    inside && /^[[:space:]]*[-*][[:space:]]/ { started = 1 }
    inside && started { print }
  ' CHANGELOG.md
} > "$gate"
gate_out="$(MA_CHANGELOG="$gate" scripts/changelog-check.sh "$version" 2>&1)" || {
  rm -f "$gate"
  echo "$gate_out" >&2
  echo "cut-beta: stopped — the '## Next' notes do not pass the release-notes rules a release must pass. Fix CHANGELOG.md and run this again. Nothing was changed." >&2
  exit 1
}
rm -f "$gate"

echo
echo "──────── What the pre-release will say ────────"
echo "Mac Analyzers $name"
echo
cat "$notes"
echo "───────────────────────────────────────────────"
echo
if (( ! assume_yes )) && (( ! dry_run )); then
  if [[ ! -t 0 ]]; then
    echo "cut-beta: not a terminal — re-run with --yes once someone has read the notes above." >&2
    exit 1
  fi
  read -r -p "Would someone who has never seen the code understand this? [y/N] " answer
  if [[ ! "$answer" =~ ^[Yy] ]]; then
    echo "cut-beta: stopped — nothing was changed. Edit CHANGELOG.md and run this again."
    exit 1
  fi
fi

# ── 4. publish ─────────────────────────────────────────────────────────────
say "pushing development"
run git push origin development
# Creating the release with --target makes the tag on GitHub at this commit in the same step, so there is never a tag
# without its pre-release. If it fails nothing was tagged and a rerun starts clean.
say "creating the GitHub pre-release (and its tag $tag)"
if (( dry_run )); then
  echo "  [dry-run] gh release create $tag --prerelease --latest=false --target $head_commit --title Mac Analyzers $name --notes-file <notes>"
  echo "  [dry-run] git fetch --tags origin"
  echo "cut-beta [dry-run]: every check passed; nothing was changed. main and VERSION are never touched."
  exit 0
fi
if ! gh release create "$tag" --prerelease --latest=false --target "$head_commit" \
     --title "Mac Analyzers $name" --notes-file "$notes"; then
  echo "cut-beta: GitHub did not create the pre-release, so nothing was tagged. Development is already pushed; fix the cause (network, 'gh auth status') and run scripts/cut-beta.sh again." >&2
  exit 1
fi
git fetch --quiet --tags origin || echo "cut-beta: note — the tag $tag is not on this Mac yet. Run: git fetch --tags" >&2
if [[ "$(gh release view "$tag" --json isPrerelease -q .isPrerelease 2>/dev/null || true)" == "true" ]]; then
  say "published: $(gh release view "$tag" --json url -q .url)"
else
  echo "cut-beta: $tag was created but GitHub does not report it as a pre-release. Check: gh release view $tag" >&2
  exit 1
fi
