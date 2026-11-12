#!/usr/bin/env bash
# sudoers-install-test.sh — storage-manage-agents.sh `sudoers-install` and `sudoers-status`.
# `sudoers-install` is for a person at a terminal, run as themselves. The app does NOT run it (nor as root): its
# "Allow..." button runs a fixed command built into the app, so nothing a user account can write is run as root.
# One file per account (`tmutil-thin-<uid>`), the old shared `tmutil-thin` is replaced only when its rule is for the
# same account. This proves: as root it refuses (exit 2) and installs nothing; as yourself it asks sudo for the password itself,
# the rule is written for you and nobody else, `visudo -cf` validates BEFORE install and a failing check stops
# everything, the rule is verified by LISTING the command (nothing is thinned), `--for-user` is gone, the template
# holds exactly one rule with no wildcard, and `sudoers-status` says whether the file is there. `id`, `visudo`,
# `install`, `sudo` and `tmutil` are stand-ins on PATH that only log; the rule's destination is a temp file in a
# copy of the script. Nothing is ever installed under /etc. Runs under `bash` and /bin/bash (3.2).
#
# Usage: tests/sudoers-install-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../storage-analyzer/storage-manage-agents.sh"
[[ -f "$SCRIPT" ]] || { echo "SKIP: script not found"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }

# a copy of the script (and the rule it installs) whose /etc/sudoers.d is a folder in the temp folder
TREE="$TMP/tree"; mkdir -p "$TREE/storage-analyzer/sudoers.d" "$TREE/lib"
cp "$HERE"/../storage-analyzer/sudoers.d/tmutil-thin "$TREE/storage-analyzer/sudoers.d/"
cp "$HERE"/../lib/*.sh "$TREE/lib/" 2>/dev/null
ETC="$TMP/etc-sudoers.d"; mkdir -p "$ETC"
OLD="$ETC/tmutil-thin"
sed "s#^SUDOERS_DIR=.*#SUDOERS_DIR=\"$ETC\"#" "$SCRIPT" > "$TREE/storage-analyzer/storage-manage-agents.sh"
grep -q "^SUDOERS_DIR=\"$ETC\"" "$TREE/storage-analyzer/storage-manage-agents.sh" || { echo "FAIL  the copy did not take the temp folder"; exit 1; }

S="$TMP/stubs"; mkdir -p "$S"
cat > "$S/id" <<'STUB'
#!/bin/bash
case "$1" in -u) echo "$STUB_UID";; -un) echo "$STUB_USER";; *) echo "uid=$STUB_UID($STUB_USER)";; esac
STUB
cat > "$S/visudo" <<'STUB'
#!/bin/bash
echo "visudo $*" >> "$STUB_LOG"
[[ "$1" == -cf && -f "$STUB_VISUDO_FAIL" ]] && exit 1
[[ "$1" == -c && -f "$STUB_VISUDO_LIVE_FAIL" ]] && exit 1
exit 0
STUB
cat > "$S/install" <<'STUB'
#!/bin/bash
echo "install $*" >> "$STUB_LOG"
last="${@: -1}"; prev="${@: -2:1}"; cp "$prev" "$last"
STUB
cat > "$S/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$STUB_LOG"
case "$1" in
  -v) exit 0 ;;
  -n|-l) [[ "$*" == *" -l"* || "$1" == -l ]] && exit "${STUB_LIST_RC:-0}"; shift; exec "$@" ;;
esac
exec "$@"
STUB
cat > "$S/tmutil" <<'STUB'
#!/bin/bash
echo "tmutil $*" >> "$STUB_LOG"
STUB
chmod +x "$S"/*

run() { # shell uid user args... -> output
  local sh="$1" uid="$2" user="$3"; shift 3
  export STUB_UID="$uid" STUB_USER="$user" STUB_LOG="$TMP/calls" STUB_VISUDO_FAIL="$TMP/visudo-fail" STUB_VISUDO_LIVE_FAIL="$TMP/visudo-live-fail"
  : > "$STUB_LOG"
  PATH="$S:$PATH" "$sh" "$TREE/storage-analyzer/storage-manage-agents.sh" "$@" 2>&1 < /dev/null
}
file_for() { echo "$ETC/tmutil-thin-$1"; }
# the one rule the script wrote into a file: a line that starts with "#" and a user ID (the template's comments start "# ")
active_rule() { grep -E '^#[0-9]+ ' "$1"; }
line_no() { grep -n "$1" "$TMP/calls" | head -1 | cut -d: -f1; }
clean() { rm -f "$ETC"/* "$TMP/visudo-fail" "$TMP/visudo-live-fail"; }
RULE='ALL=(root) NOPASSWD: /usr/bin/tmutil thinlocalsnapshots / 999999999999 4'

for sh in bash /bin/bash; do
  clean; unset STUB_LIST_RC

  out="$(run "$sh" 0 root sudoers-install)"; rc=$?
  check "[$sh] as root it refuses: exit 2, nothing installed, no sudo call" \
        "$([[ $rc -eq 2 && -z "$(ls "$ETC")" && "$(grep -c '^install ' "$TMP/calls")" -eq 0 && "$(grep -c '^sudo' "$TMP/calls")" -eq 0 ]] && echo ok || echo "exit $rc: $out")"
  out="$(run "$sh" 0 root sudoers-install --for-user alice)"; rc=$?
  check "[$sh] --for-user does not make root acceptable" "$([[ $rc -eq 2 && -z "$(ls "$ETC")" ]] && echo ok || echo "exit $rc")"

  clean
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  D="$(file_for 501)"
  check "[$sh] as yourself: sudo -v, then sudo for the check and the install" \
        "$([[ $rc -eq 0 && "$(grep -c '^sudo -v$' "$TMP/calls")" -eq 1 && "$(grep -c '^sudo visudo -cf' "$TMP/calls")" -eq 1 && "$(grep -c '^sudo install ' "$TMP/calls")" -eq 1 ]] && echo ok || echo "exit $rc: $(grep '^sudo' "$TMP/calls" | tr '\n' ';')")"
  check "[$sh] the file is this account's own, tmutil-thin-<uid> (no dot, so sudo reads it), and nothing else is written" \
        "$([[ -f "$D" && "$(ls "$ETC")" == "tmutil-thin-501" ]] && echo ok || ls "$ETC")"
  check "[$sh] the rule is for your numeric user ID and is the one scoped command; no name, never root" \
        "$([[ "$(active_rule "$D")" == "#501 $RULE" && "$(grep -c 'bob\|^root ' "$D")" -eq 0 ]] && echo ok || active_rule "$D")"
  for odd in ALL FOOBAR CWD; do
    clean; out="$(run "$sh" 502 "$odd" sudoers-install)"
    check "[$sh] an account named $odd gets a rule for #502 and its name is never written" \
          "$([[ "$(active_rule "$(file_for 502)")" == "#502 $RULE" && "$(grep -vE '^(# |#$|#[0-9]+ )' "$(file_for 502)" | grep -c .)" -eq 0 && "$(grep -c "$odd" <<< "$(active_rule "$(file_for 502)" | cut -d' ' -f1)")" -eq 0 ]] && echo ok || active_rule "$(file_for 502)")"
  done
  clean; run "$sh" 501 bob sudoers-install > /dev/null
  check "[$sh] visudo -cf validates the file BEFORE it is installed" \
        "$([[ "$(line_no 'visudo -cf')" -lt "$(line_no 'install -m')" ]] && echo ok || tr '\n' ';' < "$TMP/calls")"
  check "[$sh] the check is by LISTING (sudo -n -l ...); tmutil is never called" \
        "$([[ "$(grep -c '^sudo -n -l /usr/bin/tmutil thinlocalsnapshots / 999999999999 4$' "$TMP/calls")" -eq 1 && "$(grep -c '^tmutil' "$TMP/calls")" -eq 0 ]] && echo ok || echo thinned-or-not-listed)"
  clean; out="$(run "$sh" 501 bob sudoers-install)"
  check "[$sh] it says thinning is allowed" "$([[ "$out" == *"snapshot thinning is allowed"* ]] && echo ok || echo "$out")"

  # two accounts: each has its own file, a second install never replaces the first's
  clean; run "$sh" 501 bob sudoers-install > /dev/null; run "$sh" 502 carol sudoers-install > /dev/null
  check "[$sh] a second account's install leaves the first account's file as it was" \
        "$([[ "$(active_rule "$(file_for 501)")" == "#501 $RULE" && "$(active_rule "$(file_for 502)")" == "#502 $RULE" ]] && echo ok || ls "$ETC")"
  out="$(run "$sh" 502 carol sudoers-uninstall)"
  check "[$sh] one account's uninstall removes only its own file" "$([[ ! -e "$(file_for 502)" && -e "$(file_for 501)" ]] && echo ok || ls "$ETC")"

  # a failing visudo check stops it before anything is installed
  clean; : > "$TMP/visudo-fail"
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  check "[$sh] a failing visudo check stops it before anything is installed" "$([[ $rc -eq 1 && -z "$(ls "$ETC")" && "$(grep -c '^install ' "$TMP/calls")" -eq 0 ]] && echo ok || echo "exit $rc")"
  # the live configuration failing after the install: the new file is removed again
  clean; : > "$TMP/visudo-live-fail"
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  check "[$sh] when the live sudoers check fails after the install, the new file is removed again and it fails" "$([[ $rc -eq 1 && -z "$(ls "$ETC")" && "$out" == *"removing the rule just installed"* ]] && echo ok || echo "exit $rc: $(ls "$ETC")")"

  clean; export STUB_LIST_RC=1
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  check "[$sh] if sudo does not list the command as allowed, it says so and fails" "$([[ $rc -eq 1 && "$out" == *"does not list the command"* ]] && echo ok || echo "exit $rc")"
  unset STUB_LIST_RC

  # ---- the old shared file (/etc/sudoers.d/tmutil-thin, the name form) ----
  # theirs, by name: replaced and removed at a terminal
  clean; printf '# old\nbob %s\n' "$RULE" > "$OLD"
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  check "[$sh] old file for this account by name: the new file is written and the old one removed" "$([[ $rc -eq 0 && -f "$(file_for 501)" && ! -e "$OLD" && "$out" == *"removed the old shared file"* ]] && echo ok || echo "exit $rc: $(ls "$ETC"): $out")"
  # theirs, by user ID (written by an earlier build)
  clean; printf '#501 %s\n' "$RULE" > "$OLD"
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  check "[$sh] old file for this account by user ID: removed" "$([[ $rc -eq 0 && ! -e "$OLD" && -f "$(file_for 501)" ]] && echo ok || ls "$ETC")"
  # another account's: left alone, and said so
  clean; printf 'alice %s\n' "$RULE" > "$OLD"
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  check "[$sh] old file for ANOTHER account: left in place, said so, the new file still written" "$([[ $rc -eq 0 && -f "$OLD" && -f "$(file_for 501)" && "$out" == *"left $ETC/tmutil-thin in place"* ]] && echo ok || echo "exit $rc: $(ls "$ETC"): $out")"
  # more than one rule in it: not touched
  clean; printf 'bob %s\nalice %s\n' "$RULE" "$RULE" > "$OLD"
  out="$(run "$sh" 501 bob sudoers-install)"
  check "[$sh] old file with more than one rule: left in place" "$([[ -f "$OLD" ]] && echo ok || echo removed)"
  # the old file is not removed when the new one failed
  clean; printf 'bob %s\n' "$RULE" > "$OLD"; : > "$TMP/visudo-fail"
  out="$(run "$sh" 501 bob sudoers-install)"
  check "[$sh] a failed install leaves the old file as it was" "$([[ -f "$OLD" && ! -e "$(file_for 501)" ]] && echo ok || ls "$ETC")"
  rm -f "$TMP/visudo-fail"

  # ---- sudoers-uninstall and sudoers-status, both files ----
  clean; printf 'bob %s\n' "$RULE" > "$OLD"; run "$sh" 501 bob sudoers-install > /dev/null; printf 'bob %s\n' "$RULE" > "$OLD"
  out="$(run "$sh" 501 bob sudoers-uninstall)"; rc=$?
  check "[$sh] sudoers-uninstall removes this account's file and the old shared one when it is this account's" "$([[ $rc -eq 0 && -z "$(ls "$ETC")" ]] && echo ok || ls "$ETC")"
  clean; printf 'alice %s\n' "$RULE" > "$OLD"; : > "$(file_for 501)"
  out="$(run "$sh" 501 bob sudoers-uninstall)"
  check "[$sh] sudoers-uninstall leaves another account's old file and says how to remove it" "$([[ -f "$OLD" && ! -e "$(file_for 501)" && "$out" == *"sudo rm $ETC/tmutil-thin"* ]] && echo ok || echo "$out")"
  clean
  out="$(run "$sh" 501 bob sudoers-uninstall)"
  check "[$sh] sudoers-uninstall with nothing installed says so" "$([[ "$out" == *"(not installed)"* ]] && echo ok || echo "$out")"

  clean
  out="$(run "$sh" 501 bob sudoers-status)"; rc=$?
  check "[$sh] sudoers-status: nothing, exit 1" "$([[ $rc -eq 1 && "$out" == "not installed" ]] && echo ok || echo "exit $rc: $out")"
  : > "$(file_for 501)"
  out="$(run "$sh" 501 bob sudoers-status)"; rc=$?
  check "[$sh] sudoers-status: this account's file, exit 0" "$([[ $rc -eq 0 && "$out" == "installed: $(file_for 501)" ]] && echo ok || echo "exit $rc: $out")"
  : > "$OLD"
  out="$(run "$sh" 501 bob sudoers-status)"; rc=$?
  check "[$sh] sudoers-status: both files are named" "$([[ $rc -eq 0 && "$out" == *"installed: "* && "$out" == *"earlier shared file: $OLD"* ]] && echo ok || echo "exit $rc: $out")"
  rm -f "$(file_for 501)"
  out="$(run "$sh" 501 bob sudoers-status)"; rc=$?
  check "[$sh] sudoers-status: only the old shared file, exit 0 and says it is an earlier one" "$([[ $rc -eq 0 && "$out" == "earlier shared file: "* ]] && echo ok || echo "exit $rc: $out")"
done

# the template: exactly one rule, the one command, no wildcard, and no --for-user left in the script
T="$HERE/../storage-analyzer/sudoers.d/tmutil-thin"
active="$(grep -v '^[[:space:]]*#' "$T" | grep -v '^[[:space:]]*$')"
check "template holds exactly one rule" "$([[ "$(printf '%s\n' "$active" | wc -l | tr -d ' ')" -eq 1 ]] && echo ok || echo "$active")"
check "template rule is the exact command, for the __UID__ placeholder" "$([[ "$active" == "__UID__ ALL=(root) NOPASSWD: /usr/bin/tmutil thinlocalsnapshots / 999999999999 4" ]] && echo ok || echo "$active")"
check "template rule has no wildcard" "$([[ "$active" != *'*'* ]] && echo ok || echo wildcard)"
check "script has no --for-user" "$(grep -q -- '--for-user' "$SCRIPT" && echo "still there" || echo ok)"

# the real visudo, on scratch files only (-cf checks a file and installs nothing; no password, nothing under /etc)
if [[ -x /usr/sbin/visudo ]]; then
  V="$TMP/visudo-scratch"; mkdir -p "$V"
  rule() { printf '%s ALL=(root) NOPASSWD: /usr/bin/tmutil thinlocalsnapshots / 999999999999 4\n' "$1" > "$V/rule"; /usr/sbin/visudo -cf "$V/rule" > "$V/out" 2>&1; echo $?; }
  check "visudo -cf accepts the rule written for a user ID (#501)" "$([[ "$(rule '#501')" == 0 ]] && echo ok || cat "$V/out")"
  # what a NAME would have meant (the reason no name is written): ALL is every user, an all-capitals name is an alias, a keyword is a syntax error
  echo "INFO  visudo on this Mac: ALL exit $(rule ALL), FOOBAR exit $(rule FOOBAR), CWD exit $(rule CWD) (no name is written any more)"
else
  echo "SKIP  /usr/sbin/visudo not found: the #501 syntax check was not run"
fi
exit $fail
