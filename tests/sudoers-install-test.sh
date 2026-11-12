#!/usr/bin/env bash
# sudoers-install-test.sh — storage-manage-agents.sh `sudoers-install` and `sudoers-status`.
# `sudoers-install` is for a person at a terminal, run as themselves. The app does NOT run it (nor as root): its
# "Allow..." button runs a fixed command built into the app, so nothing a user account can write is run as root.
# This proves: as root it refuses (exit 2) and installs nothing; as yourself it asks sudo for the password itself,
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

# a copy of the script (and the rule it installs) whose destination is a file in the temp folder
TREE="$TMP/tree"; mkdir -p "$TREE/storage-analyzer/sudoers.d" "$TREE/lib"
cp "$HERE"/../storage-analyzer/sudoers.d/tmutil-thin "$TREE/storage-analyzer/sudoers.d/"
cp "$HERE"/../lib/*.sh "$TREE/lib/" 2>/dev/null
DEST="$TMP/etc-sudoers.d-tmutil-thin"
sed "s#^SUDOERS_DEST=.*#SUDOERS_DEST=\"$DEST\"#" "$SCRIPT" > "$TREE/storage-analyzer/storage-manage-agents.sh"
grep -q "^SUDOERS_DEST=\"$DEST\"" "$TREE/storage-analyzer/storage-manage-agents.sh" || { echo "FAIL  the copy did not take the temp destination"; exit 1; }

S="$TMP/stubs"; mkdir -p "$S"
cat > "$S/id" <<'STUB'
#!/bin/bash
case "$1" in -u) echo "$STUB_UID";; -un) echo "$STUB_USER";; *) echo "uid=$STUB_UID($STUB_USER)";; esac
STUB
cat > "$S/visudo" <<'STUB'
#!/bin/bash
echo "visudo $*" >> "$STUB_LOG"
[[ "$1" == -cf && -f "$STUB_VISUDO_FAIL" ]] && exit 1
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

run() { # shell uid user args... -> output; status in $RC (via the caller's $?)
  local sh="$1" uid="$2" user="$3"; shift 3
  export STUB_UID="$uid" STUB_USER="$user" STUB_LOG="$TMP/calls" STUB_VISUDO_FAIL="$TMP/visudo-fail"
  : > "$STUB_LOG"
  PATH="$S:$PATH" "$sh" "$TREE/storage-analyzer/storage-manage-agents.sh" "$@" 2>&1 < /dev/null
}
# the one rule the script wrote: a line that starts with "#" and a user ID (the template's comments start "# ")
active_rule() { grep -E '^#[0-9]+ ' "$DEST"; }
line_no() { grep -n "$1" "$TMP/calls" | head -1 | cut -d: -f1; }

for sh in bash /bin/bash; do
  rm -f "$DEST" "$TMP/visudo-fail"; unset STUB_LIST_RC

  out="$(run "$sh" 0 root sudoers-install)"; rc=$?
  check "[$sh] as root it refuses: exit 2, nothing installed, no sudo call" \
        "$([[ $rc -eq 2 && ! -e "$DEST" && "$(grep -c '^install ' "$TMP/calls")" -eq 0 && "$(grep -c '^sudo' "$TMP/calls")" -eq 0 ]] && echo ok || echo "exit $rc: $out")"
  out="$(run "$sh" 0 root sudoers-install --for-user alice)"; rc=$?
  check "[$sh] --for-user does not make root acceptable" "$([[ $rc -eq 2 && ! -e "$DEST" ]] && echo ok || echo "exit $rc")"

  rm -f "$DEST"
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  check "[$sh] as yourself: sudo -v, then sudo for the check and the install" \
        "$([[ $rc -eq 0 && "$(grep -c '^sudo -v$' "$TMP/calls")" -eq 1 && "$(grep -c '^sudo visudo -cf' "$TMP/calls")" -eq 1 && "$(grep -c '^sudo install ' "$TMP/calls")" -eq 1 ]] && echo ok || echo "exit $rc: $(grep '^sudo' "$TMP/calls" | tr '\n' ';')")"
  check "[$sh] the rule is for your numeric user ID and is the one scoped command; no name, never root" \
        "$([[ "$(active_rule)" == "#501 ALL=(root) NOPASSWD: /usr/bin/tmutil thinlocalsnapshots / 999999999999 4" && "$(grep -c 'bob\|^root ' "$DEST")" -eq 0 ]] && echo ok || active_rule)"
  for odd in ALL FOOBAR CWD; do
    rm -f "$DEST"; out="$(run "$sh" 502 "$odd" sudoers-install)"
    check "[$sh] an account named $odd gets a rule for #502 and its name is never written" \
          "$([[ "$(active_rule)" == "#502 ALL=(root) NOPASSWD: /usr/bin/tmutil thinlocalsnapshots / 999999999999 4" && "$(grep -vE '^(# |#$|#[0-9]+ )' "$DEST" | grep -c .)" -eq 0 && "$(grep -c "$odd" <<< "$(active_rule | cut -d' ' -f1)")" -eq 0 ]] && echo ok || active_rule)"
  done
  rm -f "$DEST"; run "$sh" 501 bob sudoers-install > /dev/null
  check "[$sh] visudo -cf validates the file BEFORE it is installed" \
        "$([[ "$(line_no 'visudo -cf')" -lt "$(line_no 'install -m')" ]] && echo ok || tr '\n' ';' < "$TMP/calls")"
  check "[$sh] the check is by LISTING (sudo -n -l ...); tmutil is never called" \
        "$([[ "$(grep -c '^sudo -n -l /usr/bin/tmutil thinlocalsnapshots / 999999999999 4$' "$TMP/calls")" -eq 1 && "$(grep -c '^tmutil' "$TMP/calls")" -eq 0 ]] && echo ok || echo thinned-or-not-listed)"
  check "[$sh] it says thinning is allowed" "$([[ "$out" == *"snapshot thinning is allowed"* ]] && echo ok || echo "$out")"

  rm -f "$DEST"; : > "$TMP/visudo-fail"
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  check "[$sh] a failing visudo check stops it before anything is installed" "$([[ $rc -eq 1 && ! -e "$DEST" && "$(grep -c '^install ' "$TMP/calls")" -eq 0 ]] && echo ok || echo "exit $rc")"
  rm -f "$TMP/visudo-fail"

  rm -f "$DEST"; export STUB_LIST_RC=1
  out="$(run "$sh" 501 bob sudoers-install)"; rc=$?
  check "[$sh] if sudo does not list the command as allowed, it says so and fails" "$([[ $rc -eq 1 && "$out" == *"does not list the command"* ]] && echo ok || echo "exit $rc")"
  unset STUB_LIST_RC

  rm -f "$DEST"
  out="$(run "$sh" 501 bob sudoers-status)"; rc=$?
  check "[$sh] sudoers-status: not installed, exit 1" "$([[ $rc -eq 1 && "$out" == "not installed" ]] && echo ok || echo "exit $rc: $out")"
  : > "$DEST"
  out="$(run "$sh" 501 bob sudoers-status)"; rc=$?
  check "[$sh] sudoers-status: installed, exit 0" "$([[ $rc -eq 0 && "$out" == "installed: "* ]] && echo ok || echo "exit $rc: $out")"
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
