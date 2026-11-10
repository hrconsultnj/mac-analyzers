#!/usr/bin/env bash
# changelog-check.sh — the release gate: is there a What's New entry for this
# version, and does it read like something written for the people who use
# the app?
#
#   scripts/changelog-check.sh            # checks the version in VERSION
#   scripts/changelog-check.sh 2.69.0     # checks a specific version
#   scripts/changelog-check.sh --print 2.69.0   # prints the entry's body
#   scripts/changelog-check.sh --title 2.69.0   # prints the entry's title
#
# CHANGELOG.md is the single source for release notes — the app's Update
# screen shows it and each GitHub release publishes its entry — so an entry
# that is missing, empty, or written in commit shorthand must stop a release
# rather than ship to users. Called by scripts/cut-release.sh (before
# anything changes), by the pre-merge-commit hook on main (before a release
# merge is created), and by scripts/release.sh (before anything is pushed).
#
# A check can only catch shorthand, not judge writing: it blocks what is
# never right in release notes. Whether the entry is CLEAR is still read by
# a person — cut-release.sh shows it and asks.
#
# Exit: 0 entry is fit to ship · 1 it is not (every problem is listed).
set -euo pipefail

mode="check"
case "${1:-}" in
  --print) mode="print"; shift ;;
  --title) mode="title"; shift ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
changelog="${MA_CHANGELOG:-$root/CHANGELOG.md}"
version="${1:-$(tr -d ' \n' < "$root/VERSION")}"
version="${version#v}"

if [[ ! -f "$changelog" ]]; then
  echo "changelog: $changelog does not exist." >&2
  exit 1
fi

# ── the entry: from "## v<version> — Title" to the next "## v" heading ─────
heading="$(grep -m1 -E "^## v${version//./\\.}( |$)" "$changelog" || true)"
title="$(sed -E 's/^## v[0-9.]+[[:space:]]*(—|-|:)?[[:space:]]*//' <<<"$heading")"
body="$(awk -v want="## v$version" '
  index($0, want " ") == 1 || $0 == want { inside = 1; next }
  inside && /^## v[0-9]/ { exit }
  inside { print }
' "$changelog")"

if [[ "$mode" == "title" ]]; then printf '%s\n' "$title"; exit 0; fi
if [[ "$mode" == "print" ]]; then
  # trim leading/trailing blank lines so the release body starts with text
  printf '%s\n' "$body" | awk 'NF { seen = 1 } seen { lines[++n] = $0 } END {
    while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
    for (i = 1; i <= n; i++) print lines[i] }'
  exit 0
fi

problems=()
fail() { problems+=("$1"); }

if [[ -z "$heading" ]]; then
  cat >&2 <<EOF
changelog: no entry for v$version in CHANGELOG.md.

Add one at the top of the list, written for someone who uses the app and has
never seen the code:

  ## v$version — One sentence saying what is better now

  A short paragraph on what changed and why they would care.

  - Smaller things worth knowing, one per line.

  Fixed: anything that used to go wrong and no longer does.
EOF
  exit 1
fi

# ── the title ──────────────────────────────────────────────────────────────
[[ "$heading" == *" — "* ]] || fail "the heading needs a title: \"## v$version — What is better now\""
if [[ -n "$title" ]]; then
  [[ "$title" =~ ^[A-Z0-9\"\'“‘] ]] || fail "the title starts lowercase: \"$title\""
  (( $(wc -w <<<"$title") >= 3 )) || fail "the title is too short to say anything: \"$title\""
fi

# ── the body ───────────────────────────────────────────────────────────────
words="$(wc -w <<<"$body" | tr -d ' ')"
(( words >= 20 )) || fail "the entry is $words words — say what changed and why a user would care (20 or more)"

line_no=0
previous_blank=1
while IFS= read -r line; do
  line_no=$((line_no + 1))
  trimmed="${line#"${line%%[![:space:]]*}"}"
  if [[ -z "$trimmed" ]]; then previous_blank=1; continue; fi

  # commit shorthand: "feat(memory): …", "fix: …"
  if [[ "$trimmed" =~ ^(-[[:space:]]+)?(feat|fix|chore|docs|refactor|test|perf|build|ci|style|revert)(\([^\)]*\))?!?:[[:space:]] ]]; then
    fail "line $line_no is a commit subject, not a sentence: \"$trimmed\""
  fi

  # a paragraph or bullet that starts lowercase is a fragment
  starts_block=0
  text="$trimmed"
  if [[ "$trimmed" =~ ^[-*][[:space:]]+(.*)$ ]]; then starts_block=1; text="${BASH_REMATCH[1]}"
  elif (( previous_blank )); then starts_block=1; fi
  if (( starts_block )) && [[ "$text" =~ ^[a-z] ]]; then
    fail "line $line_no starts lowercase — write a full sentence: \"$trimmed\""
  fi

  # anything outside `backticks` is prose; code names do not belong in prose
  prose="$(sed -E 's/`[^`]*`//g' <<<"$trimmed")"
  if [[ "$prose" =~ (^|[^A-Za-z0-9_])([a-z][a-z0-9]*_[a-z0-9_]+)([^A-Za-z0-9_]|$) ]]; then
    fail "line $line_no names code (\"${BASH_REMATCH[2]}\") — describe what the user sees instead"
  fi
  if [[ "$prose" =~ (^|[^A-Za-z0-9])([a-z]+[A-Z][a-z]+[A-Za-z]*)\(?\)?([^A-Za-z0-9]|$) ]]; then
    case "${BASH_REMATCH[2]}" in
      macOS|iOS|iPhone|iPad|iCloud|iMessage|iTerm|eBay|npm|watchOS|tvOS|visionOS) ;;
      *) fail "line $line_no names code (\"${BASH_REMATCH[2]}\") — describe what the user sees instead" ;;
    esac
  fi
  if [[ "$prose" =~ [A-Za-z0-9_]+\.(swift|sh|plist|json|ts|py)([^A-Za-z]|$) ]]; then
    fail "line $line_no names a source file — describe what the user sees instead: \"$trimmed\""
  fi
  previous_blank=0
done <<<"$body"

# ── words that belong to how the work was done, not to what changed ────────
while IFS= read -r phrase; do
  [[ -n "$phrase" ]] || continue
  if grep -qiE -- "$phrase" <<<"$body"$'\n'"$title"; then
    fail "contains \"$(grep -oiE -m1 -- "$phrase" <<<"$body"$'\n'"$title" | head -1)\" — that is about how the work was done, not what changed for the user"
  fi
done <<'PHRASES'
Co-Authored-By:
Claude-Session:
Decision-Owner:
# critiqued
/Users/
\bTODO\b
\bWIP\b
\bblueprint
\bsub-?agents?\b
\brefactor
\bunder the hood\b
\bcode ?base\b
\bpull request\b|\bPRs?\b #?[0-9]
\bcommit(s|ted)? [0-9a-f]{7}\b
\btech(nical)? debt\b
\bboilerplate\b
\bregression test
\bedge case
PHRASES

if (( ${#problems[@]} > 0 )); then
  echo "changelog: the entry for v$version is not ready to ship:" >&2
  for problem in "${problems[@]}"; do echo "  • $problem" >&2; done
  echo "Fix CHANGELOG.md and run this again." >&2
  exit 1
fi

echo "changelog: v$version — $title ($words words) ✓"
