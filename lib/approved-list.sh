#!/usr/bin/env bash
# approved-list.sh — the reviewed list (`--only-paths` / `--only-pids`), read ONCE.
#
# A cleaner given a list acts only on the keys in it, one per line. Every item it
# finds asks "is this one in the list?", and a `grep` over the file per item cost
# 90 ms of each item's time on a 6,000-line list (164 s for a 6,154-file Downloads
# apply, measured). The list is sorted once and each question is a binary search in
# memory: no process per item, and no associative arrays, so it runs under the
# bash macOS ships (3.2).
#
#   approved_list_load <file>   sort the file's lines into memory
#   approved_list_has  <key>    exit 0 when the key is a whole line of the file
#
# The comparison is bytewise (LC_COLLATE=C), the same order `sort` was given, so
# the search is exact whatever the Mac's language. A key is matched as a whole
# line, with nothing in it taken as a pattern.

APPROVED_LIST=()
APPROVED_LIST_N=0

approved_list_load() {
  local line
  APPROVED_LIST=()
  APPROVED_LIST_N=0
  while IFS= read -r line; do
    APPROVED_LIST[APPROVED_LIST_N]="$line"
    APPROVED_LIST_N=$((APPROVED_LIST_N + 1))
  done < <(LC_ALL=C sort -u "$1" 2>/dev/null)
}

approved_list_has() {
  local lo=0 hi=$((APPROVED_LIST_N - 1)) mid LC_COLLATE=C
  while (( lo <= hi )); do
    mid=$(( (lo + hi) / 2 ))
    if [[ "$1" == "${APPROVED_LIST[mid]}" ]]; then
      return 0
    elif [[ "$1" < "${APPROVED_LIST[mid]}" ]]; then
      hi=$((mid - 1))
    else
      lo=$((mid + 1))
    fi
  done
  return 1
}
