#!/usr/bin/env bash
# cut-release.sh — the one way to ship a release.
#
#   scripts/cut-release.sh 2.69.0        # or: patch | minor | major
#   scripts/cut-release.sh minor --dry-run   # show every step, change nothing
#   scripts/cut-release.sh 2.69.0 --yes      # skip the "does this read well?" question
#
# What it does, in order — and it stops at the first thing that is not right,
# before anything has been changed:
#   1. checks you are on `development` with nothing uncommitted, and that
#      every repository check passes on this Mac (scripts/check.sh) — no
#      machine on GitHub re-checks a release
#   2. checks CHANGELOG.md has a What's New entry for the new version that is
#      fit to show users (scripts/changelog-check.sh), shows it, and asks
#   3. writes VERSION and commits it as "v<version> — <title>"
#   4. pushes development
#   5. merges development into main in the release worktree
#      (.composure/workspaces/main) — which is what ships: the hook there
#      runs scripts/release.sh to push main and publish the GitHub release
#      with the changelog entry as its notes
#   6. confirms the release is live
#   7. fast-forwards development to the release, so the next build from it
#      is that release and not a development build
#
# Releases are never cut by merging by hand: that is how three versions were
# bumped on development and never reached anyone.
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
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) target="$arg" ;;
  esac
done
if [[ -z "$target" ]]; then
  echo "usage: scripts/cut-release.sh <version|patch|minor|major> [--dry-run] [--yes]" >&2
  exit 2
fi

say() { echo "→ $*"; }
run() {
  if (( dry_run )); then echo "  [dry-run] $*"; else "$@"; fi
}

# ── 1. where we are ────────────────────────────────────────────────────────
branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != "development" ]]; then
  echo "cut-release: releases are cut from development — this checkout is on '$branch'." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "cut-release: there are uncommitted changes — commit them first, so the release is exactly what is in git:" >&2
  git status --short >&2
  exit 1
fi
main_worktree="$(git worktree list --porcelain | awk '
  /^worktree / { path = substr($0, 10) }
  $0 == "branch refs/heads/main" { print path; exit }')"
if [[ -z "$main_worktree" ]]; then
  echo "cut-release: no worktree has main checked out. Create the release worktree once:" >&2
  echo "  git worktree add .composure/workspaces/main main" >&2
  exit 1
fi

# Every check, on this Mac, before anything changes. This is the release's
# only automated gate besides the push hook: nothing on GitHub re-checks it.
say "running every check (scripts/check.sh)"
if ! scripts/check.sh; then
  echo "cut-release: a check failed — fix it first. Nothing was changed." >&2
  exit 1
fi

# ── the new version ────────────────────────────────────────────────────────
current="$(tr -d ' \n' < VERSION)"
IFS=. read -r major minor patch <<<"$current"
case "$target" in
  major) version="$((major + 1)).0.0" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  patch) version="$major.$minor.$((patch + 1))" ;;
  *) version="${target#v}" ;;
esac
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "cut-release: '$version' is not a version (expected 2.69.0, or patch/minor/major)." >&2
  exit 1
fi
tag="v$version"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  if [[ "$(gh release view "$tag" --json isDraft -q .isDraft 2>/dev/null || true)" == "false" ]]; then
    echo "cut-release: $tag has already been released." >&2
  else
    echo "cut-release: $tag is tagged but its release is not published (or GitHub could not be reached)." >&2
    echo "If an earlier run stopped partway, finish it: run scripts/release.sh from the main worktree." >&2
  fi
  exit 1
fi
say "releasing $tag (currently $current)"

# ── 2. the What's New entry — before anything changes ──────────────────────
scripts/changelog-check.sh "$version"
title="$(scripts/changelog-check.sh --title "$version")"
echo
echo "──────── What users will read ────────"
echo "v$version — $title"
echo
scripts/changelog-check.sh --print "$version"
echo "───────────────────────────────────────"
echo
if (( ! assume_yes )) && (( ! dry_run )); then
  if [[ ! -t 0 ]]; then
    echo "cut-release: not a terminal — re-run with --yes once someone has read the entry above." >&2
    exit 1
  fi
  read -r -p "Would someone who has never seen the code understand this? [y/N] " answer
  if [[ ! "$answer" =~ ^[Yy] ]]; then
    echo "cut-release: stopped — nothing was changed. Edit CHANGELOG.md and run this again."
    exit 1
  fi
fi

# ── 3. version commit ──────────────────────────────────────────────────────
subject="v$version — $title"
if [[ "$current" != "$version" ]]; then
  say "writing VERSION"
  if (( ! dry_run )); then
    echo "$version" > VERSION
    git add VERSION
    git commit -q -m "$subject"
  else
    echo "  [dry-run] echo $version > VERSION && git commit -m \"$subject\""
  fi
else
  say "VERSION already says $version"
fi

# ── 4. push development ────────────────────────────────────────────────────
say "pushing development"
run git push origin development

# ── 5. merge into main — this is what ships ────────────────────────────────
say "merging into main in $main_worktree"
if (( dry_run )); then
  echo "  [dry-run] git -C $main_worktree merge --no-ff development -m \"$subject\""
  echo "  [dry-run] the hook on main then runs scripts/release.sh: push main, publish $tag"
  echo "  [dry-run] then: fetch tags, fast-forward development to main, push development"
  echo "cut-release [dry-run]: every check passed; nothing was changed."
  exit 0
fi
(
  cd "$main_worktree" || exit 1
  [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || { echo "cut-release: $main_worktree is not on main." >&2; exit 1; }
  git merge --no-ff development -m "$subject"
)

# ── 6. is it actually out? ─────────────────────────────────────────────────
if [[ "$(gh release view "$tag" --json isDraft -q .isDraft 2>/dev/null || true)" == "false" ]]; then
  say "published: $(gh release view "$tag" --json url -q .url)"
else
  echo "cut-release: main was merged but $tag is not on GitHub yet." >&2
  echo "Run scripts/release.sh from $main_worktree to finish — it is safe to re-run." >&2
  exit 1
fi

# ── 7. development continues from the release ──────────────────────────────
# The release on main is a merge commit that development does not have yet,
# and the tag was created on GitHub. Fetch the tag and fast-forward
# development to it (main is development plus that one merge). A build made
# from development right after a release is then the release itself — its
# version line reads v<version>, not "Dev Build".
git fetch --quiet --tags origin || true
if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
  echo "cut-release: note — the tag $tag is not known on this Mac yet, so builds made here will say \"Dev Build\". Run: git fetch --tags" >&2
fi
if git merge --ff-only main >/dev/null 2>&1; then
  if git push --quiet origin development; then
    say "development now continues from $tag"
  else
    echo "cut-release: note — development was fast-forwarded here but not pushed. Run: git push origin development" >&2
  fi
else
  echo "cut-release: note — development could not be fast-forwarded to main. Merge main into development by hand." >&2
fi
