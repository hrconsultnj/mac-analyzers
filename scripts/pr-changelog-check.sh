#!/usr/bin/env bash
# pr-changelog-check.sh — the pull-request half of the What's New rules.
#
#   scripts/pr-changelog-check.sh <base-ref> <head-ref> [--no-changelog]
#
# A change a user would notice needs a bullet under "## Next" in CHANGELOG.md.
# This script says whether a pull request has one, and whether the bullets it
# adds are written the way scripts/changelog-check.sh requires (the tag, the
# sentence rules). It does not judge the rules itself: it lends the added
# bullets to changelog-check.sh, so the two can never disagree.
#
#   <base-ref>       where the pull request will land (e.g. a commit sha)
#   <head-ref>       the pull request's last commit
#   --no-changelog   the maintainer's "no-changelog" label is set: the missing
#                    bullet is allowed (a bullet that IS there is still checked)
#
# Used by .github/workflows/pr-hygiene.yml. Runs under bash 3.2 (macOS).
# Exit: 0 fine · 1 the pull request needs a change (the reason is printed).
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: pr-changelog-check.sh <base-ref> <head-ref> [--no-changelog]" >&2
  exit 2
fi
base="$1"
head="$2"
allow_missing=0
[[ "${3:-}" == "--no-changelog" ]] && allow_missing=1

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── does this pull request change something a user would notice? ───────────
# The app's code and the engines (the analyzer scripts and what they share).
# Not: build and release scripts, tests, docs, workflows, the sample config.
git -C "$root" diff --name-only "$base...$head" > "$tmp/files"
visible="$(grep -E '^app/Sources/|\.(sh|command)$' "$tmp/files" \
  | grep -vE '^(scripts|tests)/|^app/[^/]*\.sh$|/tests/|^config\.example\.sh$' || true)"

# ── the bullets under "## Next", one line each (a wrapped bullet is joined) ─
next_bullets() {
  awk '
    /^## / { inside = ($0 == "## Next"); flush(); next }
    !inside { next }
    /^[ \t]*[-*][ \t]+/ { flush(); text = $0; have = 1; next }
    NF == 0 { flush(); next }
    have { sub(/^[ \t]+/, ""); text = text " " $0; next }
    function flush() { if (have) print text; have = 0; text = "" }
    END { flush() }'
}
git -C "$root" show "$base:CHANGELOG.md" 2>/dev/null | next_bullets > "$tmp/before" || true
git -C "$root" show "$head:CHANGELOG.md" 2>/dev/null | next_bullets > "$tmp/after" || true
# the bullets this pull request adds or rewrites
grep -vxFf "$tmp/before" "$tmp/after" > "$tmp/added" || true

if [[ ! -s "$tmp/added" ]]; then
  if [[ -n "$visible" && "$allow_missing" -eq 0 ]]; then
    {
      echo "This change touches what people see or what the scripts do, but adds nothing under \"## Next\" in CHANGELOG.md:"
      printf '%s\n' "$visible" | head -n 8 | sed 's/^/  - /'
      echo
      echo "Add one bullet, in plain words for someone who has never seen the code,"
      echo "ending with its tag, for example:"
      echo "  - Old Recordings finds where your recording apps save. <!-- wn: open=recordings icon=film.stack title=\"Recording Sources\" -->"
      echo "If nobody using the app would notice this change, ask a maintainer to add the"
      echo "\"no-changelog\" label."
    } >&2
    exit 1
  fi
  if [[ -n "$visible" ]]; then
    echo "pr-changelog: no \"## Next\" bullet, allowed by the no-changelog label."
  else
    echo "pr-changelog: nothing a user would notice changed, so no \"## Next\" bullet is needed."
  fi
  exit 0
fi

# ── hand the added bullets to the real gate, dressed as a release entry ────
# (the intro is only there to give the entry enough words to be judged; a
# blank line before each bullet makes it a paragraph the same way a release has)
{
  echo "# What's New"
  echo
  echo "## v99.0.0 — Changes proposed for the next release"
  echo
  echo "These are the changes this contribution adds to the next release, collected here so that their wording and tags can be checked before they are merged."
  echo
  cat "$tmp/added"
} > "$tmp/changelog.md"
# one bullet per line, blank-line separated, exactly as in a real entry
awk 'NR > 6 && /^[ \t]*[-*][ \t]/ { print ""; } { print }' "$tmp/changelog.md" > "$tmp/entry.md"

if out="$(MA_CHANGELOG="$tmp/entry.md" "$root/scripts/changelog-check.sh" 99.0.0 2>&1)"; then
  echo "pr-changelog: $(wc -l < "$tmp/added" | tr -d ' ') new \"## Next\" bullet(s), format fine."
  exit 0
fi
printf '%s\n' "$out" | sed -e 's/the entry for v99\.0\.0 is not ready to ship/the new "## Next" bullets are not ready to merge/' \
  -e 's/line \([0-9]*\) of the entry/the bullet at line \1 of the new bullets/' >&2
exit 1
