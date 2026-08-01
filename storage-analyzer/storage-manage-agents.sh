#!/usr/bin/env bash
# storage-manage-agents.sh — install / uninstall / status for the storage
# auto-clean LaunchAgents.
#
#   ./storage-manage-agents.sh install     # validate, copy to ~/Library/LaunchAgents, load
#   ./storage-manage-agents.sh uninstall   # unload + remove
#   ./storage-manage-agents.sh status      # show whether they're loaded + next run
#   ./storage-manage-agents.sh sudoers-install    # install the scoped tmutil-thin NOPASSWD rule (asks for your password)
#   ./storage-manage-agents.sh sudoers-uninstall  # remove that rule
#
# Installing schedules UNATTENDED deletion (daily build caches; deep node_modules
# every 3 days). Review a dry run first:  ./storage-auto-clean.sh --mode deep
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${HERE}/launchd"
DEST="${HOME}/Library/LaunchAgents"
AGENTS=( com.mac-analyzers.storage-autoclean.daily com.mac-analyzers.storage-autoclean.deep )
DOMAIN="gui/$(id -u)"
SUDOERS_SRC="${HERE}/sudoers.d/tmutil-thin"
SUDOERS_DEST="/etc/sudoers.d/tmutil-thin"

cmd="${1:-status}"

case "$cmd" in
  install)
    mkdir -p "$DEST"
    for a in "${AGENTS[@]}"; do
      echo "==> ${a}"
      plutil -lint "${SRC}/${a}.plist" || { echo "   invalid plist, aborting"; exit 1; }
      # preserve a user-customized schedule (set via the app's Schedule pane)
      # across reinstalls/upgrades — the template's time is only the default
      old_h="" old_m="" old_i=""
      if [[ -f "${DEST}/${a}.plist" ]]; then
        old_h=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Hour" "${DEST}/${a}.plist" 2>/dev/null || true)
        old_m=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Minute" "${DEST}/${a}.plist" 2>/dev/null || true)
        old_i=$(/usr/libexec/PlistBuddy -c "Print :StartInterval" "${DEST}/${a}.plist" 2>/dev/null || true)
      fi
      # hydrate the template for this machine (portable across users/locations).
      # Entry point: the app's compiled agent-runner when the app is built
      # (BTM attributes the item to Mac Analyzers); plain script otherwise.
      RUNNER="$(dirname "$HERE")/app/MacAnalyzers.app/Contents/MacOS/agent-runner"
      if [[ -x "$RUNNER" ]]; then
        sed -e "s|__RUNNER__|${RUNNER}|g" \
            -e "s|__SUITE_DIR__|${HERE}|g" -e "s|__HOME__|${HOME}|g" \
            "${SRC}/${a}.plist" > "${DEST}/${a}.plist"
      else
        sed -e "/__RUNNER__/d" \
            -e "s|__SUITE_DIR__|${HERE}|g" -e "s|__HOME__|${HOME}|g" \
            "${SRC}/${a}.plist" > "${DEST}/${a}.plist"
      fi
      if [[ -n "$old_h" && -n "$old_m" ]]; then
        /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour ${old_h}" \
                                -c "Set :StartCalendarInterval:Minute ${old_m}" \
                                "${DEST}/${a}.plist" 2>/dev/null \
          && echo "   kept custom schedule (${old_h}:$(printf '%02d' "$old_m"))"
      fi
      if [[ -n "$old_i" ]]; then
        /usr/libexec/PlistBuddy -c "Set :StartInterval ${old_i}" \
                                "${DEST}/${a}.plist" 2>/dev/null \
          && echo "   kept custom interval (${old_i}s)"
      fi
      launchctl bootout "${DOMAIN}/${a}" 2>/dev/null || true
      launchctl bootstrap "${DOMAIN}" "${DEST}/${a}.plist" && echo "   loaded"
    done
    echo "Done. View schedule with: $0 status"
    ;;
  uninstall)
    for a in "${AGENTS[@]}"; do
      echo "==> ${a}"
      launchctl bootout "${DOMAIN}/${a}" 2>/dev/null && echo "   unloaded" || echo "   (was not loaded)"
      rm -f "${DEST}/${a}.plist" && echo "   removed plist"
    done
    ;;
  status)
    for a in "${AGENTS[@]}"; do
      if launchctl print "${DOMAIN}/${a}" >/dev/null 2>&1; then
        echo "LOADED   ${a}"
        launchctl print "${DOMAIN}/${a}" 2>/dev/null \
          | grep -E 'state|run interval|next firing|last exit' | sed 's/^/         /'
      else
        echo "not set  ${a}"
      fi
    done
    ;;
  sudoers-install)
    # sudo must be able to PROMPT for your password — needs a real terminal.
    if ! sudo -v; then
      echo ""
      echo "‼ sudo couldn't authenticate. Run this in a REAL terminal (iTerm/Terminal),"
      echo "  not via Claude's '!' prefix — that has no TTY for the password prompt."
      exit 1
    fi
    # Substitute the current username (sudoers rules are per-user), then
    # validate syntax FIRST (a malformed sudoers file breaks ALL sudo).
    SUDOERS_TMP="$(mktemp)"
    sed "s/^__USERNAME__ /$(id -un) /" "${SUDOERS_SRC}" > "${SUDOERS_TMP}"
    if ! sudo visudo -cf "${SUDOERS_TMP}"; then
      echo "   sudoers file FAILED visudo syntax check — NOT installing."; rm -f "${SUDOERS_TMP}"; exit 1
    fi
    sudo install -m 0440 -o root -g wheel "${SUDOERS_TMP}" "${SUDOERS_DEST}" \
      && echo "✓ installed ${SUDOERS_DEST} (user: $(id -un))"
    rm -f "${SUDOERS_TMP}"
    sudo visudo -c >/dev/null && echo "✓ live sudoers healthy"
    if sudo -n /usr/bin/tmutil thinlocalsnapshots / 999999999999 4 >/dev/null 2>&1; then
      echo "✓ passwordless thin verified — the deep agent will now reclaim snapshot space automatically."
    else
      echo "⚠ rule installed but the no-password test didn't pass; inspect ${SUDOERS_DEST}."
    fi
    ;;
  sudoers-uninstall)
    if [[ -e "${SUDOERS_DEST}" ]]; then
      sudo rm -f "${SUDOERS_DEST}" && echo "Removed ${SUDOERS_DEST}"
    else
      echo "(not installed)"
    fi
    ;;
  *) echo "usage: $0 {install|uninstall|status|sudoers-install|sudoers-uninstall}"; exit 2 ;;
esac
