#!/usr/bin/env bash
# login-items-audit.sh — find & remove ORPHANED login items / background agents
# ---------------------------------------------------------------------------
# Scans everything registered to run at login/boot and verifies each entry's
# target binary/app still exists:
#
#   * ~/Library/LaunchAgents          (user agents — removable without sudo)
#   * /Library/LaunchAgents           (all-user agents — sudo commands printed)
#   * /Library/LaunchDaemons          (root daemons — sudo commands printed)
#   * /Library/PrivilegedHelperTools  (root helpers — sudo commands printed)
#   * System Settings "Open at Login" items (via System Events)
#
# ORPHAN = the program the entry points at is GONE (uninstalled app left its
# launcher behind — TeamViewer, old updaters, etc.). Removing an orphan cannot
# break anything: the entry already cannot run. Entries whose app still exists
# are listed but never touched — remove those apps with cleanup.sh --app "Name".
#
# Note: the "Extensions" seen in System Settings live INSIDE apps (pluginkit) —
# they disappear when the app is deleted; leftover launchd entries like the
# ones this script finds are what keeps dead names on the Login Items screen.
#
# SAFE BY DEFAULT: dry-run unless --apply. --apply removes USER-level orphans
# only; system-level (/Library) removals are printed as exact sudo commands.
#
#   ./login-items-audit.sh            # audit, change nothing
#   ./login-items-audit.sh --apply    # remove user-level orphans + login items
#   ./login-items-audit.sh --apply --only-paths FILE
#                                     # …but only the orphans whose plist path (or,
#                                     # for a login item, app path) is listed in FILE,
#                                     # one per line. The script finds the orphans
#                                     # itself and intersects them with the file, so a
#                                     # stale list can only shrink what is removed.
#
# Besides the log, every run writes login-items.tsv next to it: ONE line per item
# the audit looked at (fine ones too), with this script's own verdict. The app
# reads that file; it never re-derives a verdict. Columns (tab separated):
#   kind     agent | daemon | helper | loginitem
#   scope    user | system
#   label    launchd label, helper file name, or login item name
#   plist    path of the launchd plist ("" for helpers and login items)
#   target   the program it runs / the helper file / the login item's app
#   verdict  ok | orphan | leftover | skip | removed
#   state    running | loaded | notloaded | disabled | enabled (login items)
#   reason   target-missing | no-vendor-app | no-program-key | not-absolute |
#            drive-not-connected | other-disk | unusual-path | ""
#   fix      the exact sudo command this script prints for the item ("" when none)
# ---------------------------------------------------------------------------

set -u
shopt -s nullglob

HOME_DIR="${HOME}"
DRY_RUN=1
ONLY_FILE=""
LOG_DIR="${HOME_DIR}/mac-analyzers/reports/storage"
LOG_FILE="${LOG_DIR}/login-items-audit.log"

ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)   DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;
    --only-paths)
      [[ $# -ge 2 ]] || { echo "--only-paths needs a file" >&2; exit 2; }
      ONLY_FILE="$2"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# An approved list narrows what is removed; it must never widen it. A list that
# cannot be read, or names nothing, STOPS the run: it must not fall back to
# "everything", which is what --apply means without a list.
if [[ -n "$ONLY_FILE" && ! -r "$ONLY_FILE" ]]; then
  echo "Cannot read the approved list: $ONLY_FILE" >&2
  exit 2
fi
if [[ -n "$ONLY_FILE" ]] && ! grep -q '[^[:space:]]' "$ONLY_FILE"; then
  echo "The approved list is empty, so there is nothing to do: $ONLY_FILE" >&2
  exit 2
fi

# ---------- interactive menu (double-click / bare terminal run) ----------
INTERACTIVE=0
if [[ -z "$ORIG_ARGS" ]] && { [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; }; then
  INTERACTIVE=1
  echo ""
  echo "  login-items-audit — orphaned login items & background agents"
  echo "  ------------------------------------------------------------"
  echo "  1) Audit only (change nothing)"
  echo "  2) Audit + remove user-level orphans"
  echo "  q) Quit"
  echo ""
  read -rp "  Choose [1]: " choice
  case "${choice:-1}" in
    1) ;;
    2) DRY_RUN=0 ;;
    q|Q) exit 0 ;;
    *) echo "  Unknown choice '${choice}' — exiting."; exit 2 ;;
  esac
fi

mkdir -p "$LOG_DIR"
log() { echo "$*" | tee -a "$LOG_FILE"; }

# One stamp for the run, with an identifier of its own (two runs can start in the
# same second): the log's banner and login-items.tsv carry the same one, so the
# app can tell that the inventory it reads is THIS run's.
RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
RUN_ID="$$-$RANDOM"
RUN_STAMP="$RUN_DATE  (run $RUN_ID)"
ORPHANS_USER=0; ORPHANS_SYS=0; REMOVED=0
SUDO_CMDS=""

# ---------- the inventory the app reads (see the header) ----------
INV_FILE="${LOG_DIR}/login-items.tsv"
INV_TMP="$(mktemp "${TMPDIR:-/tmp}/login-items.XXXXXX")"
MATCHED_TMP="$(mktemp "${TMPDIR:-/tmp}/login-items-matched.XXXXXX")"
trap 'rm -f "$INV_TMP" "$MATCHED_TMP"' EXIT

# what launchd says right now, read once. All read-only, no sudo.
UID_NUM="$(id -u)"
LIST_USER="$(launchctl list 2>/dev/null)"
LIST_SYSTEM="$(launchctl print system 2>/dev/null | sed -n '/^\tservices = {/,/^\t}/p')"
DISABLED_USER="$(launchctl print-disabled "gui/${UID_NUM}" 2>/dev/null)"
DISABLED_SYSTEM="$(launchctl print-disabled system 2>/dev/null)"

# Why a program that is not there may still not be GONE. Prints
#   drive-not-connected  it (or the target of a symlink to it) is under /Volumes/<name>
#                        and nothing is mounted by that name
#   other-disk           a disk by that name IS mounted, but the folder the program
#                        should be in does not exist on it: another disk with that name
#   (nothing)            really missing
unavailable_reason() { # program path
  local t="$1" hops=0 dest vol
  while [[ -L "$t" && "$hops" -lt 8 ]]; do   # a dangling link: look at where it points
    dest="$(readlink "$t")"
    [[ "$dest" == /* ]] || dest="$(dirname "$t")/$dest"
    t="$dest"; hops=$((hops+1))
  done
  if [[ "$t" == /Volumes/*/* ]]; then
    vol="/Volumes/$(printf '%s' "${t#/Volumes/}" | cut -d/ -f1)"
    if [[ ! -d "$vol" ]]; then echo "drive-not-connected"; return; fi
    if [[ ! -d "$(dirname "$t")" ]]; then echo "other-disk"; return; fi
  fi
}

# The commands that remove an item by hand, one per kind, every label and path
# quoted with printf %q so a space, quote or semicolon in a name cannot change
# what the copied command does:
#   your own agent: unload from your session, then plain rm of the plist
#   all-users agent: unload from the user's own session (no sudo), then sudo rm
#   daemon:          sudo unload from system, then sudo rm
remove_command() { # plist label [program-to-remove-too]
  local p="$1" label="$2" extra="${3:-}" q_label q_p q_extra=""
  q_label="$(printf '%q' "$label")"; q_p="$(printf '%q' "$p")"
  [[ -n "$extra" ]] && q_extra=" $(printf '%q' "$extra")"
  case "$p" in
    */LaunchDaemons/*) echo "sudo launchctl bootout system/${q_label}; sudo rm ${q_p}${q_extra}" ;;
    # a file in your own folder: no sudo, and only the plist (the program is not ours to delete as root)
    "${HOME_DIR:-$HOME}"/*) echo "launchctl bootout gui/${UID_NUM}/${q_label}; rm ${q_p}" ;;
    *) echo "launchctl bootout gui/${UID_NUM}/${q_label}; sudo rm ${q_p}${q_extra}" ;;
  esac
}

# running | loaded | disabled | notloaded. args: label, domain (user|system)
launchd_state() {
  local label="$1" domain="$2" pid="" found=0 disabled
  if [[ "$domain" == "user" ]]; then
    pid="$(printf '%s\n' "$LIST_USER" | awk -F'\t' -v l="$label" '$3 == l { print $1; exit }')"
    disabled="$DISABLED_USER"
  else
    pid="$(printf '%s\n' "$LIST_SYSTEM" | awk -v l="$label" '$NF == l { print $1; exit }')"
    disabled="$DISABLED_SYSTEM"
  fi
  [[ -n "$pid" ]] && found=1
  if [[ "$found" -eq 1 ]]; then
    case "$pid" in
      ''|-|0) echo loaded ;;
      *[!0-9]*) echo loaded ;;
      *) echo running ;;
    esac
    return
  fi
  if printf '%s\n' "$disabled" | grep -Fq "\"${label}\" => disabled"; then
    echo disabled
  else
    echo notloaded
  fi
}

# one inventory line. args: kind scope label plist target verdict state reason
inv() {
  local f out="" sep=""
  for f in "$@"; do
    f="${f//$'\t'/ }"; f="${f//$'\n'/ }"
    out="${out}${sep}${f}"; sep=$'\t'
  done
  printf '%s\n' "$out" >> "$INV_TMP"
}

# was this item approved? With no list, everything is (the script's own
# --apply scope); with one, only what is listed.
approved() {
  [[ -z "$ONLY_FILE" ]] && return 0
  grep -Fxq -- "$1" "$ONLY_FILE" || return 1
  printf '%s\n' "$1" >> "$MATCHED_TMP"
}

# target of a launchd plist: Program, else ProgramArguments[0]; also
# BundleProgram (relative to the app) via AssociatedBundleIdentifiers apps.
plist_target() {
  local p="$1" t
  t=$(plutil -extract Program raw -o - "$p" 2>/dev/null)
  [[ -z "$t" ]] && t=$(plutil -extract ProgramArguments.0 raw -o - "$p" 2>/dev/null)
  echo "$t"
}

# does any APP from this vendor prefix still exist? Helpers/daemons outlive
# their apps (TeamViewer, Docker, Samsung drivers), so a live target binary
# does NOT prove the entry is still wanted. Checks Spotlight by bundle-id
# prefix plus the non-indexed PrivilegedHelperTools dir.
vendor_has_app() {
  # two statements: in one `local`, "$vendor" would still be empty when the
  # second assignment expands it
  local vendor="$1"
  local tail="${vendor##*.}"
  # real app locations only — an uninstaller stub in App Support must NOT count
  mdfind -onlyin /Applications "kMDItemCFBundleIdentifier == '${vendor}*'" 2>/dev/null | grep -q . && return 0
  mdfind -onlyin "$HOME/Applications" "kMDItemCFBundleIdentifier == '${vendor}*'" 2>/dev/null | grep -q . && return 0
  # bundle-id prefix can differ from vendor label (OrbStack = dev.kdrag0n.*) — match by name too
  # (a glob and `case`, not `ls | grep`: app names with spaces or odd characters
  # stay whole; nocasematch is switched back on every path out)
  local restore d a hit=1
  restore="$(shopt -p nocasematch)"
  shopt -s nocasematch
  for d in /Applications "$HOME/Applications"; do
    for a in "$d"/*; do
      # -L too: an app that is a link to a drive that is not plugged in still
      # counts as installed. Skipping it would report its helper as a leftover
      # and print the command to delete it.
      [[ -e "$a" || -L "$a" ]] || continue
      case "${a##*/}" in *"$tail"*) hit=0; break 2 ;; esac
    done
  done
  if [[ "$hit" -ne 0 ]]; then
    for a in /Library/PrivilegedHelperTools/*.app; do
      [[ -e "$a" || -L "$a" ]] || continue
      case "${a##*/}" in *"$tail"*) hit=0; break ;; esac
    done
  fi
  eval "$restore"
  return "$hit"
}

# classify one plist. args: plist_path, scope(user|system)
check_plist() {
  local p="$1" scope="$2" target label verdict="" vendor reason="" fix="" kind domain state verdict_word
  label=$(plutil -extract Label raw -o - "$p" 2>/dev/null); label="${label:-$(basename "$p" .plist)}"
  target=$(plist_target "$p")
  # a tab or newline in a path cannot be written to the inventory unchanged, so
  # the row could never be matched again: list it, never act on it
  if [[ "$p$target$label" == *$'\t'* || "$p$target$label" == *$'\n'* ]]; then
    log "  [SKIP]    ${label//[$'\t\n']/ }  (a tab or line break in its name or path) — verify manually"
    inv agent "$scope" "${label//[$'\t\n']/ }" "${p//[$'\t\n']/ }" "${target//[$'\t\n']/ }" skip notloaded unusual-path ""
    return
  fi
  if [[ -z "$target" ]]; then
    verdict="unparseable"           # no Program/ProgramArguments — leave alone
    reason="no-program-key"
  elif [[ "$target" != /* ]]; then
    # relative or env-launcher (sh, /usr/bin/env …) — can't verify mechanically
    verdict="unverifiable"
    reason="not-absolute"
  elif [[ -e "$target" ]]; then
    verdict="ok"
    # target exists — but does the vendor's APP? (com.teamviewer.Helper with
    # no TeamViewer.app anywhere = leftover helper, worth human review).
    # Script/interpreter targets are DELIBERATE user automation, never suspect.
    case "$target" in
      *.sh|*.py|*.rb|*/node|*/bun|*/bash|*/zsh|*/python*|/usr/bin/*|/bin/*) : ;;
      *)
        vendor=$(echo "$label" | awk -F'.' 'NF>=2 {print $1"."$2}')
        if [[ -n "$vendor" ]] && ! vendor_has_app "$vendor"; then
          verdict="suspect"
          reason="no-vendor-app"
        fi ;;
    esac
  elif reason="$(unavailable_reason "$target")"; [[ -n "$reason" ]]; then
    # the program is on a drive that is not plugged in, or behind another disk
    # with the same name: it is not gone
    verdict="unverifiable"
  else
    verdict="ORPHAN"
    reason="target-missing"
  fi

  case "$p" in
    */LaunchDaemons/*) kind="daemon"; domain="system" ;;
    *) kind="agent"; domain="user" ;;
  esac
  state="$(launchd_state "$label" "$domain")"

  case "$verdict" in
    ORPHAN)
      if [[ "$scope" == "user" ]]; then
        ORPHANS_USER=$((ORPHANS_USER+1))
        if ! approved "$p"; then
          log "  [ORPHAN]  $label"
          log "            plist:  ${p/#$HOME_DIR/~}"
          log "            target: $target  (MISSING) — not in the approved list, left in place"
        elif [[ "$DRY_RUN" -eq 1 ]]; then
          log "  [ORPHAN]  $label"
          log "            plist:  ${p/#$HOME_DIR/~}"
          log "            target: $target  (MISSING)"
        else
          launchctl bootout "gui/$(id -u)/$label" 2>/dev/null \
            || log "            note: launchctl did not unload it (it may not have been loaded); removing its file anyway"
          if rm -f "$p"; then
            log "  [REMOVED] $label  (target was gone: $target)"; REMOVED=$((REMOVED+1))
            verdict="REMOVED"
          fi
        fi
      else
        ORPHANS_SYS=$((ORPHANS_SYS+1))
        log "  [ORPHAN·sudo]  $label"
        log "                 plist:  $p"
        log "                 target: $target  (MISSING)"
        fix="$(remove_command "$p" "$label")"
        SUDO_CMDS="${SUDO_CMDS}${fix}"$'\n'
      fi
      ;;
    ok) : ;;   # listed only in verbose future; keep output focused on problems
    suspect)
      log "  [LEFTOVER?]  $label  — target exists ($target) but NO app from"
      log "               vendor '$(echo "$label" | awk -F'.' '{print $1"."$2}')' is installed. Review; if unwanted:"
      fix="$(remove_command "$p" "$label" "$target")"
      if [[ "$fix" == sudo* || "$fix" == *"; sudo "* ]]; then
        log "               (removing the file needs an administrator: it is in a folder that belongs to the system)"
      else
        log "               (no administrator needed: the file is in your own folder)"
      fi
      log "               $fix"
      ;;
    unverifiable|unparseable)
      if [[ "$reason" == "drive-not-connected" ]]; then
        log "  [SKIP]    $label  (its drive is not connected: $target) — left alone"
      elif [[ "$reason" == "other-disk" ]]; then
        log "  [SKIP]    $label  (that path is on another disk with the same name: $target) — left alone"
      else
        log "  [SKIP]    $label  ($verdict: ${target:-no program key}) — verify manually"
      fi
      ;;
  esac

  case "$verdict" in
    ok) verdict_word="ok" ;;
    ORPHAN) verdict_word="orphan" ;;
    REMOVED) verdict_word="removed" ;;
    suspect) verdict_word="leftover" ;;
    *) verdict_word="skip" ;;
  esac
  inv "$kind" "$scope" "$label" "$p" "$target" "$verdict_word" "$state" "$reason" "$fix"
}

log "=================================================================="
log " login-items-audit  |  $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY')  |  $RUN_STAMP"
log "=================================================================="

log ""
log "### 1. ~/Library/LaunchAgents (user — removable without sudo)"
found=0
for p in "$HOME_DIR"/Library/LaunchAgents/*.plist; do found=1; check_plist "$p" user; done
[[ $found -eq 0 ]] && log "  (none present)"

log ""
log "### 2. /Library/LaunchAgents + /Library/LaunchDaemons (system — sudo needed)"
for p in /Library/LaunchAgents/*.plist /Library/LaunchDaemons/*.plist; do check_plist "$p" system; done

log ""
log "### 3. /Library/PrivilegedHelperTools whose owning app is gone"
for h in /Library/PrivilegedHelperTools/*; do
  [[ -f "$h" ]] || continue
  hb=$(basename "$h")
  # helper naming convention: com.vendor.app.helper — look for ANY launchd plist
  # or app bundle still referencing this vendor prefix
  vendor=$(echo "$hb" | awk -F'.' '{print $1"."$2}')
  if ! ls /Library/LaunchDaemons/${vendor}.* ~/Library/LaunchAgents/${vendor}.* /Library/LaunchAgents/${vendor}.* >/dev/null 2>&1 \
     && ! mdfind "kMDItemCFBundleIdentifier == '${vendor}.*'" 2>/dev/null | grep -q .; then
    log "  [ORPHAN·sudo]  $hb  (no launchd entry or app with prefix ${vendor} remains)"
    SUDO_CMDS="${SUDO_CMDS}sudo rm $(printf '%q' "$h")"$'\n'
    ORPHANS_SYS=$((ORPHANS_SYS+1))
    inv helper system "$hb" "" "$h" orphan notloaded no-vendor-app "sudo rm $(printf '%q' "$h")"
  # a helper that a launchd plist above already runs is that plist's row, not a second one
  elif ! awk -F'\t' -v t="$h" '$5 == t { found = 1 } END { exit !found }' "$INV_TMP"; then
    inv helper system "$hb" "" "$h" ok notloaded ""
  fi
done

log ""
log "### 4. System Settings 'Open at Login' items"
osascript -e 'tell application "System Events" to get {name, path} of every login item' >/dev/null 2>&1 || log "  (System Events not scriptable here — check manually)"
while IFS=$'\t' read -r nm pth; do
  [[ -z "${nm:-}" ]] && continue
  li_reason=""
  [[ -n "$pth" && ! -e "$pth" ]] && li_reason="$(unavailable_reason "$pth")"
  if [[ -n "$li_reason" ]]; then
    log "  [SKIP]    login item '$nm'  (${li_reason//-/ }: $pth) — left alone"
    inv loginitem user "$nm" "" "$pth" skip enabled "$li_reason"
  elif [[ -n "$pth" && ! -e "$pth" ]]; then
    if ! approved "$pth"; then
      log "  [ORPHAN]  login item '$nm' → $pth (MISSING) — not in the approved list, left in place"
      ORPHANS_USER=$((ORPHANS_USER+1))
      inv loginitem user "$nm" "" "$pth" orphan enabled target-missing
    elif [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [ORPHAN]  login item '$nm' → $pth (MISSING)"
      ORPHANS_USER=$((ORPHANS_USER+1))
      inv loginitem user "$nm" "" "$pth" orphan enabled target-missing
    else
      # System Events reports how many it deleted; none is "not removed" (deleting
      # an empty selection is not an error, so the exit status says nothing)
      removed_count="$(osascript -e 'on run argv' \
        -e 'tell application "System Events"' \
        -e 'set found to (every login item whose path is (item 1 of argv))' \
        -e 'set n to count of found' \
        -e 'if n > 0 then delete found' \
        -e 'return n' \
        -e 'end tell' \
        -e 'end run' "$pth" 2>/dev/null)"
      if [[ "$removed_count" =~ ^[1-9][0-9]*$ ]]; then
        log "  [REMOVED] login item '$nm'"; REMOVED=$((REMOVED+1))
        inv loginitem user "$nm" "" "$pth" removed enabled target-missing
      else
        log "  [NOT REMOVED] login item '$nm' → $pth: System Events found no login item with that path"
        inv loginitem user "$nm" "" "$pth" orphan enabled target-missing
      fi
    fi
  else
    inv loginitem user "$nm" "" "$pth" ok enabled ""
  fi
done < <(osascript -e '
  tell application "System Events"
    set out to ""
    repeat with li in login items
      try
        set p to path of li
        if p is not missing value then set out to out & (name of li) & tab & p & linefeed
      end try
    end repeat
    return out
  end tell' 2>/dev/null)

# Listed paths that are not a user-level leftover right now are ignored, and
# said so: the list narrows what this script finds, it never adds to it.
if [[ -n "$ONLY_FILE" ]]; then
  header_done=0
  while IFS= read -r listed || [[ -n "$listed" ]]; do
    [[ -z "${listed//[[:space:]]/}" ]] && continue
    grep -Fxq -- "$listed" "$MATCHED_TMP" && continue
    if [[ "$header_done" -eq 0 ]]; then
      log ""
      log "### 5. Approved-list entries that are not user-level leftovers"
      header_done=1
    fi
    log "  [SKIP]    $listed  (not a user-level leftover right now) — left alone"
  done < "$ONLY_FILE"
fi

# publish the inventory in one move, so the app never reads half of it
{
  printf '#login-items-inventory\t1\t%s\t%s\t%s\n' "$RUN_DATE" "$([[ $DRY_RUN -eq 1 ]] && echo dry-run || echo apply)" "$RUN_ID"
  cat "$INV_TMP"
} > "${INV_FILE}.new" && mv -f "${INV_FILE}.new" "$INV_FILE"

log ""
log "=================================================================="
if [[ "$DRY_RUN" -eq 1 ]]; then
  log " DRY RUN — user-level orphans: ${ORPHANS_USER}, system-level: ${ORPHANS_SYS}."
  log " Remove user-level with: $0 --apply"
else
  log " Removed ${REMOVED} user-level orphan(s). System-level found: ${ORPHANS_SYS}."
fi
if [[ -n "$SUDO_CMDS" ]]; then
  log ""
  log " System-level removals need sudo — run these yourself (or via Claude's ! prefix):"
  printf '%s' "$SUDO_CMDS" | sed 's/^/   /' | tee -a "$LOG_FILE"
fi
log ""
log " Entries whose app still EXISTS are untouched by design — uninstall those"
log " apps properly with:  ./cleanup.sh --app \"App Name\" --execute"
log "=================================================================="

if [[ "$INTERACTIVE" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 && "$ORPHANS_USER" -gt 0 ]]; then
    echo ""
    read -rp "  Remove the user-level orphans now? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] && "$0" --apply
  fi
  echo ""
  read -rp "  Done — press Enter to close this window… " _
fi
