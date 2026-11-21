#!/usr/bin/env bash
# changelog-check.sh — the release gate: is there a What's New entry for this
# version, and does it read like something written for the people who use
# the app?
#
#   scripts/changelog-check.sh            # checks the version in VERSION
#   scripts/changelog-check.sh 2.69.0     # checks a specific version
#   scripts/changelog-check.sh --print 2.69.0   # prints the entry's body
#   scripts/changelog-check.sh --title 2.69.0   # prints the entry's title
#   scripts/changelog-check.sh --tags 2.71.0    # prints open, icon and summary of each bullet's tag
#   scripts/changelog-check.sh --stamp 2.71.0 2026-11-14   # writes the release date under the heading
#   scripts/changelog-check.sh --on-mac 2.71.0  # checks every screen and icon a tag names exists (this Mac only)
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
# What's New tags. The app lists each bullet as a feature row, so from the
# first version that ships that (WN_FIRST) every bullet ends with ONE comment
# GitHub does not show:
#
#   - Old Recordings finds where your recording apps save. <!-- wn: open=recordings icon=film.stack title="Recording Sources" -->
#
# open  = the screen a deep link names ("monitor", "guard", "trends" …), or "-"
#         for a change across the app; one screen per bullet
# icon  = an SF Symbol name
# title = optional, in double quotes, title style, 60 characters or fewer
#
# and the line under the heading carries the date, written by cut-release.sh
# (--stamp), never by hand:  <!-- wn: released=2026-11-14 -->
# --print removes every such comment, so the GitHub release body is the same
# prose as ever. Whether a screen and a symbol really exist is known only to
# the app's code: --on-mac asks SnapshotRunner, on this Mac.
#
# Exit: 0 entry is fit to ship · 1 it is not (every problem is listed)
#       --on-mac: 2 when it could not run (no Mac or no Swift).
set -euo pipefail

# the first version whose entry must be fully tagged: older entries are never re-judged
WN_FIRST="2.71.0"

mode="check"
in_development=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --print) mode="print" ;;
    --title) mode="title" ;;
    --tags) mode="tags" ;;
    --stamp) mode="stamp" ;;
    --on-mac) mode="onmac" ;;
    --in-development) in_development=1 ;;
  esac
  shift
done
stamp_date="${2:-}"

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

# every What's New comment removed: a line that is only one, and one at the end of a bullet with the space before it
strip_tags() {
  sed -E '/^[[:space:]]*<!--[[:space:]]*wn:.*-->[[:space:]]*$/d; s/[[:space:]]*<!--[[:space:]]*wn:.*-->[[:space:]]*$//'
}
# the prose the checks below judge: no tag is ever "code in the prose"
raw_body="$body"
body="$(printf '%s\n' "$raw_body" | strip_tags)"

# is $1 at or after $2? (dotted numbers)
version_at_least() {
  awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 } exit 0 }'
}

# one record per bullet of the raw entry, separated by the unit separator (a tab would swallow empty fields):
#   line  tags-in-bullet  tag-ends-bullet  open  icon  title  summary
bullet_records() {
  printf '%s\n' "$raw_body" | awk '
    function field(tag, key,    m, rest) {
      if (key == "title") { if (match(tag, /title="[^"]*"/)) return substr(tag, RSTART + 7, RLENGTH - 8); return "" }
      if (match(tag, "(^|[ \t])" key "=[^ \t]+")) { rest = substr(tag, RSTART, RLENGTH); sub(/^[ \t]*[a-z]+=/, "", rest); return rest }
      return ""
    }
    function summary(text,    t, k) {
      t = text; gsub(/\*\*/, "", t); gsub(/`/, "", t)
      k = index(t, ". "); if (k > 0) t = substr(t, 1, k - 1)
      sub(/\.$/, "", t); return t
    }
    function flush(    tags, n, rest, tag, ends, body) {
      if (!inb) return
      n = 0; rest = text
      while ((k = index(rest, "<!-- wn:")) > 0) { n++; rest = substr(rest, k + 8) }
      ends = (n == 1 && text ~ /<!-- wn:([^-]|-[^-]|--[^>])*-->[ \t]*$/ && lastline ~ /<!-- wn:/) ? 1 : 0
      tag = ""; body = text
      if (n >= 1) { k = index(text, "<!-- wn:"); tag = substr(text, k + 8); sub(/-->.*$/, "", tag); body = substr(text, 1, k - 1); sub(/[ \t]+$/, "", body) }
      t = field(tag, "title"); if (t == "") t = summary(body)
      # anything in the tag that is not open=, icon=, title= or image= makes it unreadable
      left = tag; gsub(/title="[^"]*"/, "", left); gsub(/(open|icon|image)=[^ \t]+/, "", left); gsub(/[ \t]/, "", left)
      if (n >= 1 && left != "") { badtag = 1 } else { badtag = 0 }
      # a ">" inside the comment (a title with one) ends it early for every reader that is not this one
      angle = (n >= 1 && index(tag, ">") > 0)
      printf "%d\037%d\037%d\037%s\037%s\037%s\037%s\n", startline, n, ends, (angle ? "!>" : (badtag ? "!" : field(tag, "open"))), field(tag, "icon"), field(tag, "title"), t
      inb = 0
    }
    /^[ \t]*[-*][ \t]+/ { flush(); inb = 1; startline = NR; text = $0; sub(/^[ \t]*[-*][ \t]+/, "", text); lastline = $0; next }
    NF == 0 { flush(); next }
    inb { text = text " " $0; lastline = $0; next }
    END { flush() }'
}

if [[ "$mode" == "title" ]]; then printf '%s\n' "$title"; exit 0; fi
if [[ "$mode" == "print" ]]; then
  # trim leading/trailing blank lines so the release body starts with text
  printf '%s\n' "$body" | awk 'NF { seen = 1 } seen { lines[++n] = $0 } END {
    while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
    for (i = 1; i <= n; i++) print lines[i] }'
  exit 0
fi
if [[ "$mode" == "tags" ]]; then
  bullet_records | awk -F'\037' '{ printf "%s\t%s\t%s\n", $4, $5, $7 }'
  exit 0
fi
if [[ "$mode" == "stamp" ]]; then
  [[ "$stamp_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "changelog: --stamp needs a date like 2026-11-14." >&2; exit 2; }
  [[ -n "$heading" ]] || { echo "changelog: no entry for v$version to stamp." >&2; exit 1; }
  stamped="$(mktemp)"
  # the new date goes directly under the heading; an old one anywhere before the entry's first bullet is replaced
  awk -v want="## v$version" -v day="$stamp_date" '
    index($0, want " ") == 1 || $0 == want { print; print "<!-- wn: released=" day " -->"; inside = 1; next }
    inside && /^## / { inside = 0 }
    inside && /^[ \t]*[-*][ \t]+/ { inside = 0 }
    inside && /^[ \t]*<!--[ \t]*wn:[ \t]*released=[^>]*-->[ \t]*$/ { next }
    { print }' "$changelog" > "$stamped"
  if cmp -s "$stamped" "$changelog"; then rm -f "$stamped"; else cat "$stamped" > "$changelog"; rm -f "$stamped"; fi
  echo "changelog: v$version released $stamp_date"
  exit 0
fi
if [[ "$mode" == "onmac" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]] || ! command -v swift >/dev/null 2>&1; then
    echo "changelog: not run — the screens and icons a tag names can only be checked on a Mac with Swift." >&2
    exit 2
  fi
  build_path="${MA_BUILD_PATH:-$root/app/.build}"
  build_log="$(mktemp)"
  if ! ( cd "$root/app" && env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
      swift build --disable-keychain --build-path "$build_path" --product SnapshotRunner ) >"$build_log" 2>&1; then
    echo "changelog: could not build the tool that checks the tags. The build said:" >&2
    grep -a -E ': error: ' "$build_log" | cut -c1-300 | awk '!seen[$0]++' | head -8 >&2 || true
    tail -n 5 "$build_log" | cut -c1-300 >&2
    rm -f "$build_log"
    exit 1
  fi
  rm -f "$build_log"
  "$build_path/debug/SnapshotRunner" --check-whats-new "$changelog" "$version" "$WN_FIRST"
  exit $?
fi

problems=()
fail() { problems+=("$1"); }

# Development between releases: the entry for the RUNNING version does not
# exist yet — its What's New accumulates under "## Next" until the release
# renames it. check.sh passes --in-development; the release gate does not, so
# a release still cannot ship without its own entry.
if [[ -z "$heading" ]] && (( in_development )); then
  if grep -q '^## Next' "$changelog"; then
    echo "changelog: in development — What's New accumulates under ## Next."
    exit 0
  fi
fi
if [[ -z "$heading" ]]; then
  cat >&2 <<EOF
changelog: no entry for v$version in CHANGELOG.md.

Rename the "## Next" heading at the top to this version and give it a title
(or add the entry there), written for someone who uses the app and has never
seen the code:

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
  # (the pattern lives in a variable: quotes inside a [[ =~ ]] expression are
  #  legal bash but unparseable for shellcheck, which CI gates on)
  # shellcheck disable=SC1112  # the curly quotes are deliberate: a title may open with them
  title_start='^[A-Z0-9"“‘'"'"']'
  [[ "$title" =~ $title_start ]] || fail "the title starts lowercase: \"$title\""
  (( $(wc -w <<<"$title") >= 3 )) || fail "the title is too short to say anything: \"$title\""
fi

# ── the tags ───────────────────────────────────────────────────────────────
if version_at_least "$version" "$WN_FIRST"; then
  if [[ -z "$(bullet_records)" ]]; then
    fail "the entry has no bullets — from $WN_FIRST on, What's New lists each change as a row, so write each change as a bullet that ends with its tag (<!-- wn: open=… icon=… -->); a fix is a bullet too"
  fi
  while IFS=$'\037' read -r at tag_count at_end open icon tag_title _; do
    [[ -n "$at" ]] || continue
    if (( tag_count == 0 )); then fail "the bullet at line $at of the entry has no What's New tag (<!-- wn: open=… icon=… -->)"; continue; fi
    (( tag_count == 1 )) || { fail "the bullet at line $at of the entry has $tag_count What's New tags; it takes one"; continue; }
    (( at_end == 1 )) || { fail "the What's New tag of the bullet at line $at is not at the end of the bullet's last line"; continue; }
    [[ "$open" != "!>" ]] || { fail "the tag of the bullet at line $at contains a \">\" (a title cannot hold one: it would end the comment early)"; continue; }
    [[ "$open" == "-" || "$open" =~ ^[a-zA-Z][a-zA-Z0-9:._-]*$ ]] || fail "the tag of the bullet at line $at has no usable open= (a screen name, or - for the whole app)"
    [[ "$icon" =~ ^[a-z0-9.]+$ ]] || fail "the tag of the bullet at line $at has no usable icon= (an SF Symbol name)"
    if [[ -n "$tag_title" ]]; then
      [[ "$tag_title" =~ ^[A-Z0-9] ]] || fail "the tag title \"$tag_title\" starts lowercase"
      (( ${#tag_title} <= 60 )) || fail "the tag title \"$tag_title\" is over 60 characters"
    fi
  done < <(bullet_records)
fi
# the release date line belongs above the first bullet: the app reads it only from there
late_date="$(printf '%s\n' "$raw_body" | awk '
  /^[ \t]*[-*][ \t]+/ { seen_bullet = 1 }
  seen_bullet && /^[ \t]*<!--[ \t]*wn:[ \t]*released=[0-9]{4}-[0-9]{2}-[0-9]{2}[ \t]*-->[ \t]*$/ { print NR; exit }')"
if [[ -n "$late_date" ]]; then
  fail "the release date line (<!-- wn: released=… -->) at line $late_date of the entry comes after the first bullet — move it up under the heading or below the intro paragraph, before the first bullet, or the app shows no date"
fi
# a tag anywhere but the end of a bullet (the date line apart) is a mistake in any entry
stray="$(printf '%s\n' "$raw_body" | awk '
  /^[ \t]*[-*][ \t]+/ { inb = 1 }
  NF == 0 { inb = 0 }
  /<!--[ \t]*wn:/ {
    if ($0 ~ /^[ \t]*<!--[ \t]*wn:[ \t]*released=[0-9]{4}-[0-9]{2}-[0-9]{2}[ \t]*-->[ \t]*$/) { if (++dates > 1) print "date " NR; next }
    if (!inb) print "line " NR
  }')"
if [[ -n "$stray" ]]; then
  fail "the entry has a What's New comment that is not at the end of a bullet, or a second release date line ($(tr '\n' ' ' <<<"$stray" | sed 's/ $//'))"
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
