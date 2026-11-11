#!/usr/bin/env bash
# receipt-identity-test.sh — the cleaners' [TRASHED] receipts end with the item's
# identity (`#id=<device>:<inode>`), taken with macOS's own /usr/bin/stat, so Undo
# can prove the Trash still holds THAT item.
#
# It really applies each cleaner, but only to stand-in files it makes itself, with
# HOME pointed at a temp folder (so the Trash and the logs are the temp folder's),
# `env -i`, and a fake GNU-style `stat` FIRST on the PATH: a script that called a
# bare `stat -f` (a flag only macOS's stat has) would write a junk identity, or
# fail its own safety check and move nothing.
#
# Usage: tests/receipt-identity-test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == "Darwin" ]] || { echo "skipped: needs macOS (stat -f)"; exit 0; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ma-receipt.XXXXXX")" || exit 2
FIXTURE="/private/tmp/ma-receipt-fixture-$$"
trap 'rm -rf "$TMP" "$FIXTURE"' EXIT
HOME_DIR="$TMP/home"; BIN="$TMP/bin"
mkdir -p "$HOME_DIR/Downloads" "$HOME_DIR/.Trash" "$BIN" "$FIXTURE"
# a stand-in for GNU coreutils' stat: -f means "file system status" there and prints a report
cat > "$BIN/stat" <<'STAT'
#!/bin/sh
printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: fake-gnu-stat\n' "$*"
STAT
chmod +x "$BIN/stat"

fail=0
check() { if [[ "$2" == ok ]]; then echo "PASS  $1"; else echo "FAIL  $1 — $2"; fail=1; fi; }
env_run() { env -i HOME="$HOME_DIR" PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP/tmp" "$@"; }
mkdir -p "$TMP/tmp"
real_id() { /usr/bin/stat -f '%d:%i' "$1"; }
find_log() { find "$HOME_DIR" -name "$1" -type f 2>/dev/null | head -1; }

# ---- the Downloads janitor
echo old > "$HOME_DIR/Downloads/old.zip"; touch -t 202001010000 "$HOME_DIR/Downloads/old.zip"
env_run /bin/bash "$ROOT/storage-analyzer/downloads-janitor.sh" --apply >"$TMP/janitor.out" 2>&1
log="$(find_log janitor.log)"
line="$(grep '\[TRASHED\]' "$log" 2>/dev/null | head -1)"
dest="$(printf '%s' "$line" | sed -E 's/.*->  (.*)  #id=.*/\1/')"
id="$(printf '%s' "$line" | sed -E 's/.*  #id=([0-9]+:[0-9]+)$/\1/')"
if [[ -n "$line" && -e "$dest" && "$id" == "$(real_id "$dest")" ]]; then check "janitor receipt carries the Trash item's identity" ok
else check "janitor receipt carries the Trash item's identity" "line: ${line:-none}"; fi
grep -q 'File:' "$log" 2>/dev/null && check "janitor receipt has no GNU stat output" "found 'File:'" || check "janitor receipt has no GNU stat output" ok

# ---- temp-clean. It scans the real /tmp and /var/tmp (about two minutes), so it runs only
# when asked: RUN_SLOW=1 tests/receipt-identity-test.sh. One 2 MB stand-in file, named in an
# --only-paths list so nothing else is touched; --min-age-hours 0 because the recency gate
# also looks at ctime, which no `touch` can backdate.
if [[ "${RUN_SLOW:-0}" == "1" ]]; then
  FILE="/private/tmp/ma-receipt-fixture-$$.bin"
  dd if=/dev/zero of="$FILE" bs=1048576 count=2 2>/dev/null; touch -t 202001010000 "$FILE"
  printf '%s\n' "$FILE" > "$TMP/only.txt"
  env_run /bin/bash "$ROOT/storage-analyzer/temp-clean.sh" --apply --min-age-hours 0 --only-paths "$TMP/only.txt" >"$TMP/temp.out" 2>&1
  rm -f "$FILE"
  log="$(find_log temp-clean.log)"
  line="$(grep "\[TRASHED\].*ma-receipt-fixture" "$log" 2>/dev/null | head -1)"
  dest="$(printf '%s' "$line" | sed -E 's/.*->  (.*)  #id=.*/\1/')"
  id="$(printf '%s' "$line" | sed -E 's/.*  #id=([0-9]+:[0-9]+)$/\1/')"
  if [[ -n "$line" && -e "$dest" && "$id" == "$(real_id "$dest")" ]]; then check "temp-clean moved the item and its receipt carries the identity" ok
  else check "temp-clean moved the item and its receipt carries the identity" "line: ${line:-none}; output: $(tail -n 3 "$TMP/temp.out" | tr '\n' ' ')"; fi
else
  echo "skip  temp-clean (set RUN_SLOW=1; it scans the real /tmp)"
fi

exit "$fail"
