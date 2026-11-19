#!/usr/bin/env bash
# memory-manage-agents.sh — install / uninstall / status for the memory-guard +
# daily RAM auto-clean LaunchAgents. Mirrors storage/storage-manage-agents.sh.
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
AGENTS=( com.sparehold.memory-guard com.sparehold.memory-autoclean.daily )
DOMAIN="gui/$(id -u)"
# shellcheck source=../lib/paths.sh
source "${HERE}/../lib/paths.sh"
# shellcheck source=../lib/launchd-migrate.sh
source "${HERE}/../lib/launchd-migrate.sh"
PAUSE_FLAG="$(sparehold_user_root)/reports/memory/.guard-paused"

# reload_agent: unload, wait until launchd has really let go, load, retry.
# The inline version is only for a copy of this script without lib/ beside it.
if [[ -f "${HERE}/../lib/launchd-reload.sh" ]]; then
  # shellcheck source=../lib/launchd-reload.sh
  source "${HERE}/../lib/launchd-reload.sh"
else
  reload_agent() {
    launchctl bootout "$1/$2" >/dev/null 2>&1 || true
    sleep 2
    launchctl bootstrap "$1" "$3" && echo "   loaded"
  }
fi

cmd="${1:-status}"

case "$cmd" in
  install)
    mkdir -p "$DEST"
    not_loaded=0
    for a in "${AGENTS[@]}"; do
      echo "==> ${a}"
      plutil -lint "${SRC}/${a}.plist" || { echo "   invalid plist, aborting"; exit 1; }
      # New plist keeps its own schedule. Otherwise the com.mac-analyzers
      # plist is read, then booted out and deleted. The new label is not booted
      # out here; reload_agent loads it.
      sparehold_hydrate_agent "${SRC}" "${a}" "${DEST}" "${HERE}"
      sparehold_bootout_legacy "${DOMAIN}" "$(sparehold_legacy_label "${a}")" "${DEST}"
      reload_agent "${DOMAIN}" "${a}" "${DEST}/${a}.plist" || not_loaded=$((not_loaded + 1))
    done
    if [[ "$not_loaded" -gt 0 ]]; then
      echo "${not_loaded} background job(s) could not be loaded — see above."
      exit 1
    fi
    echo "Done. View with: $0 status"
    ;;
  uninstall)
    for a in "${AGENTS[@]}"; do
      echo "==> ${a}"
      launchctl bootout "${DOMAIN}/${a}" 2>/dev/null && echo "   unloaded" || echo "   (was not loaded)"
      rm -f "${DEST}/${a}.plist" && echo "   removed plist"
      sparehold_bootout_legacy "${DOMAIN}" "$(sparehold_legacy_label "${a}")" "${DEST}"
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
    if pgrep -qf "memory/memory-guard.sh"; then
      echo "guard    RUNNING (pid $(pgrep -f 'memory/memory-guard.sh' | head -1))$([[ -e "$PAUSE_FLAG" ]] && echo ' — PAUSED via flag')"
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
