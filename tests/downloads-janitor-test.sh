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

# a copy of the script whose lib/approved-list.sh is missing must say so and stop (exit 78), not exit 1 silently
missing_case() { # label shell
  local label="$1" sh="$2" home="$TMP/home-$1" tree="$TMP/tree-nolib-$1"
  mkdir -p "$home/Downloads" "$tree/storage-analyzer" "$tree/lib"
  cp "$SCRIPT" "$tree/storage-analyzer/downloads-janitor.sh"
  printf 'notify() { :; }\n' > "$tree/lib/notify.sh"
  printf 'x' > "$home/Downloads/one.pdf"; touch -t 202001010000 "$home/Downloads/one.pdf"
  printf '%s\n' "$home/Downloads/one.pdf" > "$TMP/list-$1"
  HOME="$home" "$sh" "$tree/storage-analyzer/downloads-janitor.sh" --apply --only-paths "$TMP/list-$1" > "$TMP/$label.out" 2>&1
  local rc=$?
  check "[$label] list reader missing: exit 78 with the reason, nothing moved" \
        "$([[ $rc -eq 78 && -e "$home/Downloads/one.pdf" ]] && grep -q 'FATAL: lib/approved-list.sh is missing' "$TMP/$label.out" && echo ok || echo "exit $rc")"
}

# a file kept only in iCloud: du says 0, so a preview lists it on its own [CLOUD] line with its real size,
# and a normal file is still [DRY]. A stand-in `stat` plays the iCloud flags for a file named like
# cloud-only-*; every other call goes to the real stat. A preview moves nothing.
cloud_case() { # label shell
  local label="$1" sh="$2" home="$TMP/home-$1" stubs="$TMP/stubs-$1"
  mkdir -p "$home/Downloads" "$stubs"
  printf 'x' > "$home/Downloads/cloud-only-1.png"
  printf 'y' > "$home/Downloads/normal.pdf"
  touch -t 202001010000 "$home/Downloads/cloud-only-1.png" "$home/Downloads/normal.pdf"
  printf '#!/bin/bash\nfor a in "$@"; do [[ "$a" == *cloud-only-* ]] && { echo "compressed,dataless 26818"; exit 0; }; done\nexec /usr/bin/stat "$@"\n' > "$stubs/stat"
  # du reports no blocks for such a file, as it does for a real one
  printf '#!/bin/bash\nfor a in "$@"; do [[ "$a" == *cloud-only-* ]] && { printf "0\\t%%s\\n" "$a"; exit 0; }; done\nexec /usr/bin/du "$@"\n' > "$stubs/du"
  chmod +x "$stubs/stat" "$stubs/du"
  PATH="$stubs:$PATH" HOME="$home" "$sh" "$TMP/tree/storage-analyzer/downloads-janitor.sh" > "$TMP/$label.out" 2>&1
  check "[$label] an iCloud-only file is listed as [CLOUD] with its real size" \
        "$(grep -q '^\[CLOUD\] 27 KB  .*cloud-only-1.png' "$TMP/$label.out" && echo ok || grep 'cloud-only' "$TMP/$label.out")"
  check "[$label] a normal file is still [DRY]" "$(grep -q '^\[DRY\] .*normal.pdf' "$TMP/$label.out" && echo ok || echo "no [DRY] row")"
  check "[$label] a preview moves nothing" "$([[ -e "$home/Downloads/cloud-only-1.png" && -e "$home/Downloads/normal.pdf" ]] && echo ok || echo moved)"
}

# no run moves an iCloud-only file: not the scheduled one (no list), not a reviewed list that names it, and a
# file that has become local since the preview is an ordinary file again (moved only when listed or scheduled)
cloud_apply_cases() { # label shell
  local label="$1" sh="$2" home stubs="$TMP/stubs-apply-$1"
  mkdir -p "$stubs"
  printf '#!/bin/bash\nfor a in "$@"; do [[ "$a" == *cloud-only-* ]] && { echo "compressed,dataless 26818"; exit 0; }; done\nexec /usr/bin/stat "$@"\n' > "$stubs/stat"
  printf '#!/bin/bash\nfor a in "$@"; do [[ "$a" == *cloud-only-* ]] && { printf "0\\t%%s\\n" "$a"; exit 0; }; done\nexec /usr/bin/du "$@"\n' > "$stubs/du"
  chmod +x "$stubs/stat" "$stubs/du"
  fresh() { # name
    home="$TMP/home-$label-$1"; mkdir -p "$home/Downloads" "$home/.Trash"
    printf 'x' > "$home/Downloads/cloud-only-1.png"; printf 'y' > "$home/Downloads/normal.pdf"
    touch -t 202001010000 "$home/Downloads/cloud-only-1.png" "$home/Downloads/normal.pdf"
  }
  # 1. the scheduled run: no list
  fresh sched
  PATH="$stubs:$PATH" HOME="$home" "$sh" "$TMP/tree/storage-analyzer/downloads-janitor.sh" --apply > "$TMP/$label-sched.out" 2>&1
  check "[$label] a scheduled run (no list) leaves the iCloud-only file and moves the normal one" \
        "$([[ -e "$home/Downloads/cloud-only-1.png" && ! -e "$home/Downloads/normal.pdf" && -e "$home/.Trash/normal.pdf" ]] && echo ok || echo "cloud kept: $([[ -e "$home/Downloads/cloud-only-1.png" ]] && echo y || echo n)")"
  check "[$label] the run's summary says how many were left and why" \
        "$(grep -q '^LEFT — 1 file(s) that exist only in iCloud were left' "$TMP/$label-sched.out" && echo ok || echo "no LEFT line")"
  check "[$label] a scheduled run lists it as [CLOUD], never as trashed" \
        "$(grep -q '^\[CLOUD\] .*cloud-only-1.png' "$TMP/$label-sched.out" && ! grep -q 'TRASHED.*cloud-only' "$TMP/$label-sched.out" && echo ok || echo "wrong lines")"
  # 2. a reviewed list that names it anyway
  fresh listed
  printf '%s\n%s\n' "$home/Downloads/cloud-only-1.png" "$home/Downloads/normal.pdf" > "$TMP/list-$label-listed"
  PATH="$stubs:$PATH" HOME="$home" "$sh" "$TMP/tree/storage-analyzer/downloads-janitor.sh" --apply --only-paths "$TMP/list-$label-listed" > "$TMP/$label-listed.out" 2>&1
  check "[$label] a reviewed list that names the iCloud-only file still does not move it" \
        "$([[ -e "$home/Downloads/cloud-only-1.png" && -e "$home/.Trash/normal.pdf" ]] && echo ok || echo moved)"
  # 3. it became a local file between the preview and the apply: no longer cloud-only (no stand-in), so it is an
  #    ordinary file; not on the reviewed list it stays, on a scheduled run it is moved
  fresh local
  printf '%s\n' "$home/Downloads/normal.pdf" > "$TMP/list-$label-local"
  HOME="$home" "$sh" "$TMP/tree/storage-analyzer/downloads-janitor.sh" --apply --only-paths "$TMP/list-$label-local" > "$TMP/$label-local.out" 2>&1
  check "[$label] a file that became local is not moved by a list that never named it" \
        "$([[ -e "$home/Downloads/cloud-only-1.png" && -e "$home/.Trash/normal.pdf" ]] && echo ok || echo moved)"
  fresh local2
  HOME="$home" "$sh" "$TMP/tree/storage-analyzer/downloads-janitor.sh" --apply > "$TMP/$label-local2.out" 2>&1
  check "[$label] a file that became local is an ordinary file again for the scheduled run" \
        "$([[ ! -e "$home/Downloads/cloud-only-1.png" ]] && echo ok || echo "still there")"
}

run_case bash bash
run_case old /bin/bash
cloud_case cloud-bash bash
cloud_apply_cases capply-bash bash
cloud_case cloud-old /bin/bash
cloud_apply_cases capply-old /bin/bash
missing_case nolib-bash bash
missing_case nolib-old /bin/bash
exit $fail
