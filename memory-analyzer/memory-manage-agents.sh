#!/usr/bin/env bash
# memory-manage-agents.sh — install / uninstall / status for the memory-guard +
# daily RAM auto-clean LaunchAgents. Mirrors storage-analyzer/storage-manage-agents.sh.
#
#   ./memory-manage-agents.sh install     # validate, copy to ~/Library/LaunchAgents, load
#   ./memory-manage-agents.sh uninstall   # unload + remove
#   ./memory-manage-agents.sh status      # loaded? next run? guard alive?
#   ./memory-manage-agents.sh pause       # pause the guard's ACTIONS (agent stays loaded)
#   ./memory-manage-agents.sh resume      # resume the guard
#
# Installing schedules UNATTENDED process kills (orphaned MCP servers, dev
# servers >24h, stale playwright; guard kills dev tooling at critical
# pressure). Review a dry run first:  ./memory-auto-clean.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${HERE}/launchd"
DEST="${HOME}/Library/LaunchAgents"
AGENTS=( com.mac-analyzers.memory-guard com.mac-analyzers.memory-autoclean.daily )
DOMAIN="gui/$(id -u)"
PAUSE_FLAG="${HOME}/mac-analyzers/reports/memory/.guard-paused"

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
      RUNNER="/Applications/MacAnalyzers.app/Contents/MacOS/agent-runner"
      [[ -x "$RUNNER" ]] || RUNNER="$(dirname "$HERE")/app/MacAnalyzers.app/Contents/MacOS/agent-runner"
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
    echo "Done. View with: $0 status"
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
    if pgrep -qf "memory-analyzer/memory-guard.sh"; then
      echo "guard    RUNNING (pid $(pgrep -f 'memory-analyzer/memory-guard.sh' | head -1))$([[ -e "$PAUSE_FLAG" ]] && echo ' — PAUSED via flag')"
    else
      echo "guard    NOT running"
    fi
    ;;
  pause)
    mkdir -p "$(dirname "$PAUSE_FLAG")"
    touch "$PAUSE_FLAG" && echo "guard paused (flag: ${PAUSE_FLAG}). Resume with: $0 resume"
    ;;
  resume)
    rm -f "$PAUSE_FLAG" && echo "guard resumed."
    ;;
  *) echo "usage: $0 {install|uninstall|status|pause|resume}"; exit 2 ;;
esac
