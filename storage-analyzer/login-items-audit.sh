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
# ---------------------------------------------------------------------------

set -u
shopt -s nullglob

HOME_DIR="${HOME}"
DRY_RUN=1
LOG_DIR="${HOME_DIR}/mac-analyzers/reports/storage"
LOG_FILE="${LOG_DIR}/login-items-audit.log"

ORIG_ARGS="$*"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)   DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

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

ORPHANS_USER=0; ORPHANS_SYS=0; REMOVED=0
SUDO_CMDS=""

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
  local vendor="$1" tail="${vendor##*.}"
  # real app locations only — an uninstaller stub in App Support must NOT count
  mdfind -onlyin /Applications "kMDItemCFBundleIdentifier == '${vendor}*'" 2>/dev/null | grep -q . && return 0
  mdfind -onlyin "$HOME/Applications" "kMDItemCFBundleIdentifier == '${vendor}*'" 2>/dev/null | grep -q . && return 0
  # bundle-id prefix can differ from vendor label (OrbStack = dev.kdrag0n.*) — match by name too
  ls /Applications "$HOME/Applications" 2>/dev/null | grep -qi -- "$tail" && return 0
  ls -d /Library/PrivilegedHelperTools/*.app 2>/dev/null | grep -qi -- "$tail" && return 0
  return 1
}

# classify one plist. args: plist_path, scope(user|system)
check_plist() {
  local p="$1" scope="$2" target label verdict="" vendor
  label=$(plutil -extract Label raw -o - "$p" 2>/dev/null); label="${label:-$(basename "$p" .plist)}"
  target=$(plist_target "$p")
  if [[ -z "$target" ]]; then
    verdict="unparseable"           # no Program/ProgramArguments — leave alone
  elif [[ "$target" != /* ]]; then
    # relative or env-launcher (sh, /usr/bin/env …) — can't verify mechanically
    verdict="unverifiable"
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
        fi ;;
    esac
  else
    verdict="ORPHAN"
  fi

  case "$verdict" in
    ORPHAN)
      if [[ "$scope" == "user" ]]; then
        ORPHANS_USER=$((ORPHANS_USER+1))
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log "  [ORPHAN]  $label"
          log "            plist:  ${p/#$HOME_DIR/~}"
          log "            target: $target  (MISSING)"
        else
          launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
          rm -f "$p" && { log "  [REMOVED] $label  (target was gone: $target)"; REMOVED=$((REMOVED+1)); }
        fi
      else
        ORPHANS_SYS=$((ORPHANS_SYS+1))
        log "  [ORPHAN·sudo]  $label"
        log "                 plist:  $p"
        log "                 target: $target  (MISSING)"
        SUDO_CMDS="${SUDO_CMDS}sudo launchctl bootout system/$label 2>/dev/null; sudo rm '$p'"$'\n'
      fi
      ;;
    ok) : ;;   # listed only in verbose future; keep output focused on problems
    suspect)
      log "  [LEFTOVER?]  $label  — target exists ($target) but NO app from"
      log "               vendor '$(echo "$label" | awk -F'.' '{print $1"."$2}')' is installed. Review; if unwanted:"
      log "               sudo launchctl bootout system/$label; sudo rm '$p' '$target'"
      ;;
    unverifiable|unparseable)
      log "  [SKIP]    $label  ($verdict: ${target:-no program key}) — verify manually"
      ;;
  esac
}

log "=================================================================="
log " login-items-audit  |  $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN' || echo 'APPLY')  |  $(date '+%Y-%m-%d %H:%M:%S')"
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
    SUDO_CMDS="${SUDO_CMDS}sudo rm '$h'"$'\n'
    ORPHANS_SYS=$((ORPHANS_SYS+1))
  fi
done

log ""
log "### 4. System Settings 'Open at Login' items"
osascript -e 'tell application "System Events" to get {name, path} of every login item' >/dev/null 2>&1 || log "  (System Events not scriptable here — check manually)"
while IFS=$'\t' read -r nm pth; do
  [[ -z "${nm:-}" ]] && continue
  if [[ -n "$pth" && ! -e "$pth" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [ORPHAN]  login item '$nm' → $pth (MISSING)"
      ORPHANS_USER=$((ORPHANS_USER+1))
    else
      osascript -e "tell application \"System Events\" to delete login item \"$nm\"" >/dev/null 2>&1 \
        && { log "  [REMOVED] login item '$nm'"; REMOVED=$((REMOVED+1)); }
    fi
  fi
done < <(osascript -e '
  tell application "System Events"
    set out to ""
    repeat with li in login items
      set out to out & (name of li) & tab & (path of li) & linefeed
    end repeat
    return out
  end tell' 2>/dev/null)

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
