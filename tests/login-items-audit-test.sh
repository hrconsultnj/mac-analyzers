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
# Second half: the whole script, run in a temp HOME, for --only-paths. The list
# can only NARROW what --apply removes: a listed path that is not a user-level
# leftover is ignored and said so, and a list that is empty or unreadable stops
# the run instead of meaning "everything". (osascript, mdfind and launchctl are
# stubbed; the /Library folders are only read, and only user-level results are
# asserted.)
#
# Usage: tests/login-items-audit-test.sh [path-to-login-items-audit.sh]
# (no `set -u`: the function under test must fail by its checks, not by aborting the run)
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-$HERE/../storage-analyzer/login-items-audit.sh}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { # name expected-rc actual-rc (an actual that is not a number is a failure, not a 0)
  if [[ "$3" =~ ^[0-9]+$ && "$2" -eq "$3" ]]; then echo "PASS  $1"; else echo "FAIL  $1 (expected rc=$2, got rc=$3)"; fail=1; fi
}

has() { [[ "$1" == *"$2"* ]] && echo 0 || echo 1; }   # 0 when $1 contains $2
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

# ---- a program that is not there is not always gone -----------------------------
eval "$(sed -n '/^unavailable_reason() {/,/^}/p' "$SCRIPT" | sed "s#/Volumes#$TMP/Volumes#g")"
mkdir -p "$TMP/Volumes/Disk/Tools"
ln -s "$TMP/Volumes/GoneDrive/tool" "$TMP/dangling"
ln -s "$TMP/dangling" "$TMP/dangling-two"
ln -s "$TMP/Volumes/Disk/Tools/tool" "$TMP/to-mounted"
check "an unmounted drive: not connected" 0 "$(has "$(unavailable_reason "$TMP/Volumes/GoneDrive/x/tool")" drive-not-connected)"
check "a different disk with the same name is mounted and the folder is not on it" 0 "$(has "$(unavailable_reason "$TMP/Volumes/Disk/NoSuchDir/tool")" other-disk)"
check "the folder is on the mounted disk and only the program is gone: really missing" 0 "$([[ -z "$(unavailable_reason "$TMP/Volumes/Disk/Tools/tool")" ]] && echo 0 || echo 1)"
check "a dangling symlink into an unmounted drive: not connected" 0 "$(has "$(unavailable_reason "$TMP/dangling")" drive-not-connected)"
check "a symlink to a symlink into an unmounted drive: not connected" 0 "$(has "$(unavailable_reason "$TMP/dangling-two")" drive-not-connected)"
check "a symlink into a mounted disk whose program is gone: really missing" 0 "$([[ -z "$(unavailable_reason "$TMP/to-mounted")" ]] && echo 0 || echo 1)"
check "an ordinary missing path is really missing" 0 "$([[ -z "$(unavailable_reason /nonexistent/zz/tool)" ]] && echo 0 || echo 1)"
check "/System/Volumes/Data is an ordinary path, not an external drive" 0 "$([[ -z "$(unavailable_reason /System/Volumes/Data/zz-missing/tool)" ]] && echo 0 || echo 1)"

# ---- the commands printed for removing an item by hand ------------------------
eval "$(sed -n '/^remove_command() {/,/^}/p' "$SCRIPT")"
export UID_NUM=501   # read by remove_command, which was eval'd above
check "a daemon is unloaded from system, then removed with sudo" 0 "$(has "$(remove_command /Library/LaunchDaemons/x.plist com.a.b)" 'sudo launchctl bootout system/com.a.b; sudo rm /Library/LaunchDaemons/x.plist')"
check "an all-users agent is unloaded from the user's own session without sudo" 0 "$(has "$(remove_command /Library/LaunchAgents/x.plist com.a.b)" 'launchctl bootout gui/501/com.a.b; sudo rm /Library/LaunchAgents/x.plist')"
export HOME_DIR=/Users/zz
check "a possible leftover in your own folder: no sudo, and only the plist" 0 "$(has "$(remove_command /Users/zz/Library/LaunchAgents/x.plist com.a.b /Applications/Old.app/Contents/MacOS/x)" 'launchctl bootout gui/501/com.a.b; rm /Users/zz/Library/LaunchAgents/x.plist')"
[[ "$(remove_command /Users/zz/Library/LaunchAgents/x.plist com.a.b /Applications/Old.app)" == *sudo* ]] && r=1 || r=0
check "that command contains no sudo and does not name the program" 0 $r
cmd="$(remove_command "/Library/LaunchAgents/it's mine; rm -rf x.plist" "a b" "/Library/odd 'dir")"
check "a space, quote or semicolon in a path is escaped, not left to change the command" 0 "$(has "$cmd" "it\\'s\\ mine\\;\\ rm\\ -rf\\ x.plist")"
check "a label with a space is escaped" 0 "$(has "$cmd" 'gui/501/a\ b;')"
check "the second path is escaped too" 0 "$(has "$cmd" "/Library/odd\\ \\'dir")"

# ---- --only-paths, the whole script --------------------------------------
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
for tool in mdfind launchctl; do printf '#!/bin/sh\nexit 0\n' > "$STUBS/$tool"; chmod +x "$STUBS/$tool"; done
# System Events stand-in: lists three login items (one healthy, one whose app is
# gone, one whose NAME is an AppleScript injection attempt) and logs every delete
cat > "$STUBS/osascript" <<'STUB'
#!/bin/bash
echo "osascript $*" >> "$STUB_LOG"
case "$*" in
  *"login item whose path"*) echo "${STUB_DELETE_COUNT:-1}"; exit 0 ;;
  *repeat*) printf 'GoodApp\t/System/Applications/Calculator.app\nDeadApp\t/Applications/ZZNoSuchApp-fixture.app\nEv"il\t/Applications/ZZNoSuchEvil-fixture.app\n' ;;
esac
exit 0
STUB
chmod +x "$STUBS/osascript"
export STUB_LOG="$TMP/stub.log"
plist() { # path label program
  printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array><string>%s</string></array></dict></plist>\n' "$2" "$3" > "$1"
}
fresh() { # a new HOME with two leftovers (a, b) and one healthy agent
  rm -rf "$TMP/h2"; mkdir -p "$TMP/h2/Library/LaunchAgents"
  plist "$TMP/h2/Library/LaunchAgents/com.zz.a.plist" com.zz.a /Applications/ZZGoneA.app/Contents/MacOS/x
  plist "$TMP/h2/Library/LaunchAgents/com.zz.b.plist" com.zz.b /Applications/ZZGoneB.app/Contents/MacOS/x
  plist "$TMP/h2/Library/LaunchAgents/com.zz.fine.plist" com.zz.fine /bin/echo
}
# the interpreter running this test also runs the script, so a run under
# /bin/bash (3.2) tests the script under 3.2 too
run() { HOME="$TMP/h2" PATH="$STUBS:$PATH" "$BASH" "$SCRIPT" "$@" 2>&1; }
A="$TMP/h2/Library/LaunchAgents/com.zz.a.plist"; B="$TMP/h2/Library/LaunchAgents/com.zz.b.plist"; F="$TMP/h2/Library/LaunchAgents/com.zz.fine.plist"
exists() { [[ -e "$1" ]]; }

fresh; printf '%s\n' "$A" > "$TMP/list-a"
out="$(run --dry-run --only-paths "$TMP/list-a")"
grep -A2 'com.zz.b$' <<<"$out" | grep -q 'not in the approved list'; check "dry run: the leftover that is not listed is marked as left alone" 0 $?
grep -A2 'com.zz.a$' <<<"$out" | grep -q 'not in the approved list'; check "dry run: the listed leftover is not marked left alone" 1 $?

fresh; printf '%s\n' "$A" > "$TMP/list-a"
run --apply --only-paths "$TMP/list-a" >/dev/null
exists "$A"; ra=$?; exists "$B"; rb=$?
check "apply with one of two leftovers listed removes only that one (listed gone)" 1 $ra
check "apply with one of two leftovers listed removes only that one (other kept)" 0 $rb

fresh; printf '%s\n%s\n%s\n' "$F" "/Library/LaunchAgents/com.zz.system.plist" "/nonexistent/x.plist" > "$TMP/list-bad"
out="$(run --apply --only-paths "$TMP/list-bad")"
exists "$A"; ra=$?; exists "$B"; rb=$?; exists "$F"; rf=$?
check "a list of non-leftovers and system paths removes nothing (a kept)" 0 $ra
check "a list of non-leftovers and system paths removes nothing (b kept)" 0 $rb
check "a list of non-leftovers and system paths removes nothing (healthy agent kept)" 0 $rf
grep -c '\[SKIP\].*not a user-level leftover' <<<"$out" | grep -q '^3$'; check "each ignored entry is logged as skipped" 0 $?

fresh; : > "$TMP/list-empty"
run --apply --only-paths "$TMP/list-empty" >/dev/null; rc=$?
check "an empty list stops the run (exit 2)" 2 $rc
exists "$A"; ra=$?; exists "$B"; rb=$?
check "an empty list does not mean everything (a kept)" 0 $ra
check "an empty list does not mean everything (b kept)" 0 $rb
run --apply --only-paths "$TMP/no-such-list" >/dev/null; rc=$?
check "an unreadable list stops the run (exit 2)" 2 $rc
exists "$A"; ra=$?; check "an unreadable list removes nothing" 0 $ra

fresh
run --apply >/dev/null
exists "$A"; ra=$?; exists "$B"; rb=$?
check "no list: apply still removes every user-level leftover (a)" 1 $ra
check "no list: apply still removes every user-level leftover (b)" 1 $rb
exists "$F"; rf=$?; check "no list: the healthy agent stays" 0 $rf

# ---- login items: removed by PATH, passed as an argument -----------------------
fresh; : > "$STUB_LOG"; printf '%s\n' "/Applications/ZZNoSuchApp-fixture.app" > "$TMP/list-li"
run --apply --only-paths "$TMP/list-li" >/dev/null
deletes="$(grep -c 'login item whose path' "$STUB_LOG")"
check "a listed leftover login item is deleted once" 1 "$deletes"
grep -q 'whose path is (item 1 of argv)' "$STUB_LOG"; check "the delete asks System Events for the item whose path is argv 1" 0 $?
grep -q 'ZZNoSuchApp-fixture.app$' "$STUB_LOG"; check "the path is the last argument, not part of the script text" 0 $?
grep -q 'do shell script' "$STUB_LOG"; check "no script text is built from an item's name" 1 $?
: > "$STUB_LOG"; fresh; printf '%s\n' "$A" > "$TMP/list-a"
run --apply --only-paths "$TMP/list-a" >/dev/null
check "a list that names no login item deletes none" 0 "$(grep -c 'login item whose path' "$STUB_LOG")"

# System Events removed nothing (an empty selection is not an error): not "removed"
fresh; : > "$STUB_LOG"; printf '%s\n' "/Applications/ZZNoSuchApp-fixture.app" > "$TMP/list-li"
out="$(STUB_DELETE_COUNT=0 run --apply --only-paths "$TMP/list-li")"
grep -q '\[NOT REMOVED\] login item' <<<"$out"; check "a login item System Events did not remove is reported as not removed" 0 $?
grep -q '\[REMOVED\] login item' <<<"$out"; check "and is not reported as removed" 1 $?
fresh; : > "$STUB_LOG"
out="$(STUB_DELETE_COUNT=1 run --apply --only-paths "$TMP/list-li")"
grep -q '\[REMOVED\] login item' <<<"$out"; check "a login item System Events removed is reported as removed" 0 $?

# ---- an unplugged drive is not a leftover ----------------------------------------
fresh
plist "$TMP/h2/Library/LaunchAgents/com.zz.drive.plist" com.zz.drive /Volumes/ZZNoSuchDrive-$$/Tool.app/Contents/MacOS/x
out="$(run --apply)"
exists "$TMP/h2/Library/LaunchAgents/com.zz.drive.plist"; check "an agent whose program is on an unplugged drive is kept" 0 $?
grep -q 'its drive is not connected' <<<"$out"; check "and says why" 0 $?

fresh; ln -s "/Volumes/ZZNoSuchDrive-$$/tool" "$TMP/h2/sym-target"
plist "$TMP/h2/Library/LaunchAgents/com.zz.sym.plist" com.zz.sym "$TMP/h2/sym-target"
run --apply >/dev/null
exists "$TMP/h2/Library/LaunchAgents/com.zz.sym.plist"; check "an agent whose program is a symlink into an unplugged drive is kept" 0 $?
for vol in "/Volumes/Macintosh HD" /Volumes/*; do
  [[ -d "$vol" && -n "$vol" ]] || continue
  fresh; plist "$TMP/h2/Library/LaunchAgents/com.zz.same.plist" com.zz.same "$vol/ZZNoSuchDir-$$/tool"
  out="$(run --apply)"
  exists "$TMP/h2/Library/LaunchAgents/com.zz.same.plist"; check "an agent whose program is on a mounted disk's missing folder is kept ($vol)" 0 $?
  grep -q 'another disk with the same name' <<<"$out"; check "and says so ($vol)" 0 $?
  break
done

# ---- the command printed for a possible leftover is right for where the item loads
fresh
mkdir -p "$TMP/zzvendor"; printf '#!/bin/sh\n' > "$TMP/zzvendor/tool"; chmod +x "$TMP/zzvendor/tool"
plist "$TMP/h2/Library/LaunchAgents/com.zzvendor.x.plist" com.zzvendor.x "$TMP/zzvendor/tool"
out="$(run --dry-run)"
uid="$(id -u)"
line="$(grep -F "launchctl bootout" <<<"$out" | grep -F "com.zzvendor.x" | head -1)"
[[ "$line" == *"launchctl bootout gui/$uid/com.zzvendor.x; rm "* && "$line" != *sudo* ]] && r=0 || r=1
check "a possible leftover in your own folder: the user's own domain, plain rm, no sudo" 0 $r
grep -q 'no administrator needed' <<<"$out"; check "and the line says no administrator is needed" 0 $?
grep -F "com.zzvendor.x" "$TMP/h2/mac-analyzers/reports/storage/login-items.tsv" | awk -F'\t' '{print $9}' | grep -q '^launchctl bootout gui/'; check "the inventory carries the same command" 0 $?

# ---- a tab in a name cannot be stored, so the item is never acted on ----------------
fresh
plist "$TMP/h2/Library/LaunchAgents/com.zz.tab.plist" "$(printf 'com.zz.tab\tx')" /nonexistent/zz-tab
out="$(run --apply)"
exists "$TMP/h2/Library/LaunchAgents/com.zz.tab.plist"; check "an item with a tab in its label is kept" 0 $?
grep -q 'a tab or line break' <<<"$out"; check "and is listed as skipped with the reason" 0 $?

# ---- the launch inventory library is missing: the audit stops, it does not guess (exit 78, before anything is read or changed) ----
fresh
NOLIB="$TMP/nolib"; mkdir -p "$NOLIB/storage-analyzer" "$NOLIB/lib"
cp "$SCRIPT" "$NOLIB/storage-analyzer/login-items-audit.sh"
for f in "$HERE"/../lib/*.sh; do [[ "${f##*/}" == launch-items.sh ]] || cp "$f" "$NOLIB/lib/"; done
out="$(HOME="$TMP/h2" PATH="$STUBS:$PATH" "$BASH" "$NOLIB/storage-analyzer/login-items-audit.sh" --apply 2>&1)"; rc=$?
check "a missing lib/launch-items.sh stops the audit (exit 78)" 78 "$rc"
grep -q 'FATAL: lib/launch-items.sh is missing' <<<"$out"; check "and says which file is missing" 0 $?
exists "$A"; ra=$?; exists "$B"; rb=$?
check "and removes nothing (a kept)" 0 $ra
check "and removes nothing (b kept)" 0 $rb
exit $fail
