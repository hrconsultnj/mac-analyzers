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
#   approved_list_has_process <pid>
#                               exit 0 when the list approves THIS process: a line "<pid><TAB><start>"
#                               whose start (epoch seconds) is when the process running under that pid
#                               started, give or take two seconds, or (a list from an older app) a bare
#                               "<pid>" line. A pid the system has since given to another program is
#                               not approved, because that program started at another moment.
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

# When a process started, in epoch seconds, from the elapsed time ps reports ([[dd-]hh:]mm:ss), so
# there is no wall-clock text to misread when the clocks go back. Empty (and failing) when the process is gone.
approved_list_process_start() {
  local et d=0 h=0 m=0 s=0 a b c
  et="$(ps -o etime= -p "$1" 2>/dev/null)" || return 1
  et="${et//[[:space:]]/}"
  [[ -n "$et" ]] || return 1
  case "$et" in *-*) d="${et%%-*}"; et="${et#*-}" ;; esac
  IFS=: read -r a b c <<<"$et"
  if [[ -n "${c-}" ]]; then h="$a"; m="$b"; s="$c"; else m="$a"; s="$b"; fi
  printf '%s' "$(( $(date +%s) - (((10#$d * 24 + 10#$h) * 60 + 10#$m) * 60 + 10#$s) ))"
}

approved_list_has_process() {
  local pid="$1"
  approved_list_has "$pid" && return 0            # a list from an older app names the pid alone
  local prefix="$pid"$'\t' lo=0 hi=$APPROVED_LIST_N mid line recorded started LC_COLLATE=C
  while (( lo < hi )); do                           # the first line that is not before "<pid><TAB>"
    mid=$(( (lo + hi) / 2 ))
    if [[ "${APPROVED_LIST[mid]}" < "$prefix" ]]; then lo=$((mid + 1)); else hi=$mid; fi
  done
  (( lo < APPROVED_LIST_N )) || return 1
  [[ "${APPROVED_LIST[lo]}" == "$prefix"* ]] || return 1
  started="$(approved_list_process_start "$pid")" || return 1
  [[ -n "$started" ]] || return 1
  while (( lo < APPROVED_LIST_N )); do
    line="${APPROVED_LIST[lo]}"
    [[ "$line" == "$prefix"* ]] || break
    recorded="${line#"$prefix"}"
    if [[ "$recorded" =~ ^[0-9]+$ ]] && (( started - recorded <= 2 && recorded - started <= 2 )); then return 0; fi
    lo=$((lo + 1))
  done
  return 1
}

