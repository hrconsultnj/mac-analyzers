#!/usr/bin/env bash
# downloads-janitor-test.sh — the janitor must never put an item on top of one
# already in the Trash. Runs the REAL `--apply` of downloads-janitor.sh, but only
# inside a throwaway HOME with fixture files (the script sweeps $HOME/Downloads
# and $HOME/Desktop/Screenshots, and nothing else), with notifications replaced
# by a no-op in a copy of the script. Runs the janitor under `bash` and under
# /bin/bash (3.2) and prints PASS/FAIL lines.
#
# Covers: three same-named files from two folders in one run (same second), a
# name that is already in the Trash from before, a folder, a name with spaces,
# a name with a line break (left alone with a logged reason), and receipts that each
# name where the item really is.
#
# Usage: tests/downloads-janitor-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../storage-analyzer/downloads-janitor.sh"
[[ -f "$SCRIPT" ]] || { echo "SKIP: janitor not found"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }

# a copy of the script that cannot notify anyone
mkdir -p "$TMP/tree/storage-analyzer" "$TMP/tree/lib"
cp "$SCRIPT" "$TMP/tree/storage-analyzer/downloads-janitor.sh"
cp "$HERE"/../lib/*.sh "$TMP/tree/lib/"                       # the reviewed-list reader is part of the script
printf 'notify() { :; }\n' > "$TMP/tree/lib/notify.sh"

run_case() { # label shell
  local label="$1" sh="$2" home="$TMP/home-$1" f
  mkdir -p "$home/Downloads/Old Folder" "$home/Desktop/Screenshots/2026" "$home/.Trash"
  printf 'A' > "$home/Downloads/same.png"
  printf 'B' > "$home/Desktop/Screenshots/same.png"
  printf 'C' > "$home/Desktop/Screenshots/2026/same.png"
  printf 'D' > "$home/Downloads/my file (1).pdf"
  printf 'E' > "$home/Downloads/old1.pdf"
  printf 'F' > "$home/Downloads/Old Folder/inside.txt"
  printf 'G' > "$home/Downloads/bad"$'\n'"name.png"          # a name with a line break
  printf 'pre-same' > "$home/.Trash/same.png"          # already in the Trash from before
  printf 'pre-old1' > "$home/.Trash/old1.pdf"
  find "$home/Downloads" "$home/Desktop" -exec touch -h -t 202001010000 {} +

  HOME="$home" "$sh" "$TMP/tree/storage-analyzer/downloads-janitor.sh" --apply > "$TMP/$label.out" 2>&1
  local rc=$?
  check "[$label] janitor finished" "$([[ $rc -eq 0 ]] && echo ok || echo "exit $rc")"

  # every source is gone
  local left=0
  for f in "$home/Downloads/same.png" "$home/Desktop/Screenshots/same.png" "$home/Desktop/Screenshots/2026/same.png" \
           "$home/Downloads/my file (1).pdf" "$home/Downloads/old1.pdf" "$home/Downloads/Old Folder"; do
    [[ -e "$f" ]] && left=$((left + 1))
  done
  check "[$label] every old item left its folder" "$([[ $left -eq 0 ]] && echo ok || echo "$left still there")"

  # the three same-named files and the one already there: four different items, none replaced
  local contents
  contents="$(find "$home/.Trash" -type f \( -name '*same.png' \) -exec cat {} \; | sed 's/pre-same/P/' | fold -w1 | sort | tr -d '\n')"
  check "[$label] three same-named files and the old one are all in the Trash" "$([[ "$contents" == "ABCP" ]] && echo ok || echo "found '$contents'")"
  check "[$label] the item already in the Trash was not touched" \
        "$([[ "$(cat "$home/.Trash/same.png")" == "pre-same" && "$(cat "$home/.Trash/old1.pdf")" == "pre-old1" ]] && echo ok || echo changed)"

  # each receipt names where the item really is, and what is there is that item
  local receipts=0 wrong=0 src dest want
  while IFS= read -r line; do
    receipts=$((receipts + 1))
    src="${line#*  }"; dest="${src##*  ->  }"; src="${src%%  ->  *}"
    case "$src" in
      */Downloads/same.png) want=A ;; */Screenshots/same.png) want=B ;; */2026/same.png) want=C ;;
      *"my file (1).pdf") want=D ;; */old1.pdf) want=E ;; *"Old Folder") want=F ;; *) want="?" ;;
    esac
    if [[ -d "$dest" ]]; then got="$(cat "$dest/inside.txt" 2>/dev/null)"; else got="$(cat "$dest" 2>/dev/null)"; fi
    [[ "$got" == "$want" ]] || wrong=$((wrong + 1))
  done < <(grep '^\[TRASHED\]' "$TMP/$label.out")
  check "[$label] six receipts, each naming where its item really is" "$([[ $receipts -eq 6 && $wrong -eq 0 ]] && echo ok || echo "$receipts receipts, $wrong wrong")"
  check "[$label] a name with a line break is left alone, said so, and does not stop the run" \
        "$([[ -e "$home/Downloads/bad"$'\n'"name.png" && "$(grep -c '^\[SKIP\] name contains a line break' "$TMP/$label.out")" -eq 1 && $rc -eq 0 ]] && echo ok || echo "not handled")"
  check "[$label] nothing reported as failed" "$([[ "$(grep -c '^\[FAILED\]' "$TMP/$label.out")" -eq 0 ]] && echo ok || echo failures)"
}

run_case bash bash
run_case old /bin/bash
exit $fail
