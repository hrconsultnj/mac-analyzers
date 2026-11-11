#!/usr/bin/env bash
# tm-reclaim-test.sh — tm-reclaim.sh looks first and acts only with --apply. Every program that could change
# something (`tmutil`, `sudo`) is a stand-in found through PATH that only LOGS what it was asked; `df` is a
# stand-in too, so nothing real is read or changed. HOME is a throwaway folder. Runs under `bash` and
# /bin/bash (3.2), with no terminal on stdin (as the app runs it).
#
# Covers: no flag and --dry-run call only `tmutil listlocalsnapshots`; --apply --no-backup makes exactly one
# whitelisted thin call and no backup; --apply also starts one backup; without the sudoers rule (and no
# terminal) it says what is missing, exits 3 and does not start a backup; the log block has the standard
# banner, a SNAPSHOT line per snapshot and the free space before and after.
#
# Usage: tests/tm-reclaim-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../storage-analyzer/tm-reclaim.sh"
[[ -f "$SCRIPT" ]] || { echo "SKIP: script not found"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }

STUBS="$TMP/stubs"; mkdir -p "$STUBS"
cat > "$STUBS/tmutil" <<'STUB'
#!/bin/bash
echo "tmutil $*" >> "$STUB_LOG"
if [[ "$1" == listlocalsnapshots ]]; then
  echo "com.apple.TimeMachine.2026-11-10-100000.local"
  echo "com.apple.TimeMachine.2026-11-11-090000.local"
  echo "com.apple.os.update-ABCDEF"
fi
exit 0
STUB
cat > "$STUBS/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$STUB_LOG"
[[ -f "$STUB_DENY" ]] && exit 1
exit 0
STUB
cat > "$STUBS/df" <<'STUB'
#!/bin/bash
n=$(cat "$STUB_DF" 2>/dev/null || echo 0); echo $((n + 1)) > "$STUB_DF"
if [[ "$n" -eq 0 ]]; then a="51Gi"; else a="60Gi"; fi
printf 'Filesystem Size Used Avail Capacity Mounted on\n/dev/x 460Gi 400Gi %s 89%% /System/Volumes/Data\n' "$a"
STUB
chmod +x "$STUBS"/*

run() { # label shell args... -> output on stdout, status in $RC
  local label="$1" sh="$2"; shift 2
  export STUB_LOG="$TMP/$label.calls" STUB_DF="$TMP/$label.df" STUB_DENY="$TMP/deny"
  : > "$STUB_LOG"; rm -f "$STUB_DF"
  HOME="$TMP/home-$label" PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin" "$sh" "$SCRIPT" "$@" < /dev/null 2>&1
}
count() { grep -c "$2" "$TMP/$1.calls"; }

for sh in bash /bin/bash; do
  k="$(echo "$sh" | tr / _)"
  rm -f "$TMP/deny"

  out="$(run "nf-$k" "$sh")"
  log="$TMP/home-nf-$k/mac-analyzers/reports/storage/tm-reclaim.log"
  check "[$sh] no flag: only the snapshot list is read" "$([[ "$(count "nf-$k" .)" -eq 1 && "$(count "nf-$k" 'tmutil listlocalsnapshots')" -eq 1 ]] && echo ok || cat "$TMP/nf-$k.calls" | tr '\n' ';')"
  check "[$sh] no flag: nothing is thinned and no backup starts" "$([[ "$(count "nf-$k" sudo)" -eq 0 && "$(count "nf-$k" startbackup)" -eq 0 ]] && echo ok || echo changed)"
  check "[$sh] no flag: the log has the DRY RUN banner with the backup setting" "$(grep -q '^tm-reclaim | DRY RUN | backup=on | [0-9-]* [0-9:]*$' "$log" && echo ok || head -3 "$log")"
  check "[$sh] one SNAPSHOT line per local snapshot, the OS one kept apart" \
        "$([[ "$(grep -c '^SNAPSHOT ' "$log")" -eq 2 && "$(grep -c '^OSSNAPSHOT ' "$log")" -eq 1 && "$(grep -c '^SNAPSHOT 2026-11-10-100000$' "$log")" -eq 1 ]] && echo ok || grep SNAPSHOT "$log")"
  check "[$sh] FREE_BEFORE is in the log" "$(grep -q '^FREE_BEFORE 51Gi$' "$log" && echo ok || echo missing)"
  run "dr-$k" "$sh" --dry-run >/dev/null
  check "[$sh] --dry-run: no thin, no backup" "$([[ "$(count "dr-$k" sudo)" -eq 0 && "$(count "dr-$k" startbackup)" -eq 0 ]] && echo ok || echo changed)"

  out="$(run "nb-$k" "$sh" --apply --no-backup)"; rc=$?
  log="$TMP/home-nb-$k/mac-analyzers/reports/storage/tm-reclaim.log"
  check "[$sh] --apply --no-backup: exactly one thin call, the whitelisted one" \
        "$([[ "$(count "nb-$k" sudo)" -eq 1 && "$(count "nb-$k" 'sudo -n /usr/bin/tmutil thinlocalsnapshots / 999999999999 4$')" -eq 1 ]] && echo ok || grep sudo "$TMP/nb-$k.calls")"
  check "[$sh] --apply --no-backup: no backup, banner says APPLY and backup=off" "$([[ "$(count "nb-$k" startbackup)" -eq 0 ]] && grep -q '^tm-reclaim | APPLY | backup=off | ' "$log" && echo ok || echo wrong)"
  check "[$sh] the log ends with DONE and the free space before and after" "$(grep -q '^DONE — local snapshots thinned. Free space 51Gi -> 60Gi.$' "$log" && grep -q '^FREE_AFTER 60Gi$' "$log" && echo ok || tail -4 "$log")"
  check "[$sh] and the run succeeded" "$([[ $rc -eq 0 ]] && echo ok || echo "exit $rc")"

  run "ap-$k" "$sh" --apply >/dev/null
  check "[$sh] --apply: one thin call and one backup" "$([[ "$(count "ap-$k" sudo)" -eq 1 && "$(count "ap-$k" 'tmutil startbackup')" -eq 1 ]] && echo ok || cat "$TMP/ap-$k.calls" | tr '\n' ';')"

  : > "$TMP/deny"
  out="$(run "dn-$k" "$sh" --apply)"; rc=$?
  log="$TMP/home-dn-$k/mac-analyzers/reports/storage/tm-reclaim.log"
  check "[$sh] without the sudoers rule: exit 3 and it says what is missing" "$([[ $rc -eq 3 && "$out" == *"needs permission"* ]] && echo ok || echo "exit $rc")"
  check "[$sh] without it no backup is started and the log says it was not done" "$([[ "$(count "dn-$k" startbackup)" -eq 0 ]] && grep -q '^NOT DONE — thinning was not allowed' "$log" && echo ok || tail -3 "$log")"
  rm -f "$TMP/deny"
done
exit $fail
