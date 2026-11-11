#!/usr/bin/env bash
# login-items-audit-test.sh — regression test for vendor_has_app in
# storage-analyzer/login-items-audit.sh. Uses only stand-in folders under a
# temp directory: HOME is pointed there, mdfind is stubbed, and both the
# helper-tools folder and /Applications are swapped for temp ones, so the
# result never depends on what is installed on the machine running it.
#
# What it pins down:
#   * the function works when called on its own. It used to build `tail` from
#     `vendor` inside the same `local`, so `tail` was empty unless the caller
#     happened to have a `vendor` variable of its own — and an empty tail
#     matches every app, so no orphan would ever be flagged;
#   * an app whose name matches in a different case is found;
#   * names with spaces or odd characters neither break the match nor match
#     by accident;
#   * the helper-tools folder is matched by app name, not by the folder's path;
#   * `nocasematch` is left exactly as it was found, whichever way the
#     function returns.
#
# Usage: tests/login-items-audit-test.sh [path-to-login-items-audit.sh]
# (no `set -u`: the function under test must fail by its checks, not by aborting the run)
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-$HERE/../storage-analyzer/login-items-audit.sh}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { # name expected-rc actual-rc
  if [[ "$2" -eq "$3" ]]; then echo "PASS  $1"; else echo "FAIL  $1 (expected rc=$2, got rc=$3)"; fail=1; fi
}

mkdir -p "$TMP/home/Applications" "$TMP/PrivilegedHelperTools" "$TMP/Applications"
# an app that is a link to a drive that is not plugged in
ln -s "/Volumes/ZZNotMounted-$$/ZZExtDrive.app" "$TMP/Applications/ZZExtDrive.app"
export HOME="$TMP/home"
# stand-in apps (names are directories, like real bundles)
mkdir "$HOME/Applications/ZZStandIn Pro (beta) [x].app"
mkdir "$HOME/Applications/we'ird \"name\"*.app"
mkdir "$HOME/Applications/Other App.app"
mkdir "$TMP/PrivilegedHelperTools/unrelated.helper.app"

# the function under test, with the helper-tools folder redirected to the temp one
eval "$(sed -n '/^vendor_has_app() {/,/^}/p' "$SCRIPT" \
        | sed -e "s#/Library/PrivilegedHelperTools#$TMP/PrivilegedHelperTools#g" \
              -e "s#in /Applications #in $TMP/Applications #")"
mdfind() { return 0; }   # Spotlight is not part of what is being tested

# 1. called on its own (no `vendor` variable in the caller): app present
vendor_has_app "com.example.zzstandin"; check "found by name, called on its own" 0 $?
# 2. same call, app absent: must say no. Before the fix this said yes.
vendor_has_app "com.example.nosuchvendor"; check "absent app is not found when called on its own" 1 $?
# 3. the lowercase tail still matches the mixed-case, spaced, bracketed name (case 1 already proves it);
#    a different case of the tail matches too
vendor_has_app "com.example.ZZSTANDIN"; check "match is case-insensitive" 0 $?
vendor_has_app "com.example.zzextdrive"; check "an app linked from a drive that is not plugged in still counts as installed" 0 $?
# 4. odd names: one with quotes, an asterisk and spaces is found by a piece of its name,
#    and a tail made of glob characters is taken literally, not as a pattern
vendor_has_app "com.example.ird"; check "name with quotes and an asterisk is found" 0 $?
vendor_has_app "com.example.[a-z]"; check "glob characters in the vendor are not a pattern" 1 $?
# 5. helper tools: the folder's own name must not count as a match ("tools" is in the path)
vendor_has_app "com.example.tools"; check "helper-tools folder matched by app name, not by path" 1 $?
vendor_has_app "com.example.unrelated"; check "helper-tools app found by name" 0 $?
# 6. nocasematch restored: off stays off, on stays on, on both return paths
shopt -u nocasematch
vendor_has_app "com.example.zzstandin"; vendor_has_app "com.example.nosuchvendor"
shopt -q nocasematch; check "nocasematch still off after found + not found" 1 $?
shopt -s nocasematch
vendor_has_app "com.example.zzstandin"; vendor_has_app "com.example.nosuchvendor"
shopt -q nocasematch; check "nocasematch still on if it was on" 0 $?
shopt -u nocasematch
# 7. an empty folder (the unmatched glob stays literal) is not a match
rmdir "$TMP/PrivilegedHelperTools/unrelated.helper.app"
vendor_has_app "com.example.unrelated"; check "empty helper-tools folder is not a match" 1 $?
exit $fail
