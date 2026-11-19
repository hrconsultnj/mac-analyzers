# shellcheck shell=bash
# lib/notify.sh — shared macOS notifier for Sparehold.
# ---------------------------------------------------------------------------
# Sourced by the analyzer scripts; each keeps a tiny osascript fallback for
# when this file is absent, so every script still runs standalone.
#
#   notify TITLE MESSAGE [SOUND] [LOG_PATH]
#
# Backend order:
#   1. Sparehold's bundled CLI
#      (/Applications/Sparehold.app/Contents/MacOS/notify, then the previous
#      Mac Analyzers app, then the copy in this checkout) — posts to the
#      persistent app; proper identity in System Settings, live click-to-open-log
#   2. `alerter` (brew install vjeantet/tap/alerter) — "Open Log" action
#      button; blocks until click/timeout, so it runs in a detached subshell
#      (the launchd plists set AbandonProcessGroup=true so that handler
#      survives the script exiting)
#   3. classic osascript banner (attributed to Script Editor, no click action)
#
# config.local.sh knobs (all optional):
#   ANALYZERS_NOTIFIER=native|alerter|osascript   force a specific backend
#   ANALYZERS_LOG_VIEWER=TextEdit   app that opens logs (alerter path); set
#                                   empty ("") for the default text editor
#   ANALYZERS_NOTIFY_TIMEOUT=180    seconds an unclicked alerter alert lives
# ---------------------------------------------------------------------------

notify() {  # title, message, [sound], [log path], [subtitle], [pid]
  local title="${1:-Sparehold}" msg="${2:-}" sound="${3:-Glass}"
  local log="${4:-${LOG_FILE:-}}" subtitle="${5:-}" npid="${6:-}"
  local backend="${ANALYZERS_NOTIFIER:-native}"

  # preferred: the menu-bar app's bundled CLI (posts to the persistent app —
  # live click handling; a pid adds a "Stop Process" notification button).
  # /Applications is the canonical install; the checkout is the fallback.
  # An existing ~/mac-analyzers checkout still holds the engine until moved.
  notify_repo() {
    if [[ -n "${ANALYZERS_ROOT:-}" ]]; then
      printf '%s\n' "$ANALYZERS_ROOT"
      return
    fi
    if [[ -n "${SPAREHOLD_SUITE_DIR:-}" ]]; then
      printf '%s\n' "$SPAREHOLD_SUITE_DIR"
      return
    fi
    if [[ -x "$HOME/sparehold/memory-analyzer/memory-guard.sh" ]]; then
      printf '%s\n' "$HOME/sparehold"
      return
    fi
    printf '%s\n' "$HOME/mac-analyzers"
  }
  local repo app_cli
  repo="$(notify_repo)"
  app_cli="/Applications/Sparehold.app/Contents/MacOS/notify"
  [[ -x "$app_cli" ]] || app_cli="/Applications/MacAnalyzers.app/Contents/MacOS/notify"
  [[ -x "$app_cli" ]] || app_cli="${repo}/app/Sparehold.app/Contents/MacOS/notify"
  [[ -x "$app_cli" ]] || app_cli="${repo}/app/MacAnalyzers.app/Contents/MacOS/notify"
  if [[ -x "$app_cli" && "$backend" == "native" ]]; then
    "$app_cli" --title "$title" --message "$msg" --sound "$sound" \
      ${subtitle:+--subtitle "$subtitle"} \
      ${npid:+--pid "$npid"} \
      ${log:+--log "$log"} >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
  fi

  if command -v alerter >/dev/null 2>&1 && [[ "$backend" != "osascript" ]]; then
    (
      out=$(alerter --title "$title" --message "$msg" --sound "$sound" \
        ${subtitle:+--subtitle "$subtitle"} \
        --group "sparehold.${title// /-}" --actions "Open Log" \
        --timeout "${ANALYZERS_NOTIFY_TIMEOUT:-180}" --json 2>/dev/null) || true
      if [[ -n "$log" && -e "$log" ]] &&
         printf '%s' "$out" | grep -qE '"activationType"[^,]*"(contentsClicked|actionClicked)"'; then
        viewer="${ANALYZERS_LOG_VIEWER-TextEdit}"
        if [[ -n "$viewer" ]]; then
          open -a "$viewer" "$log" 2>/dev/null || open -t "$log" 2>/dev/null || true
        else
          open -t "$log" 2>/dev/null || true
        fi
      fi
    ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
  fi

  command -v osascript >/dev/null 2>&1 || return 0
  osascript -e "display notification \"${msg//\"/\'}\" with title \"${title//\"/\'}\"${subtitle:+ subtitle \"${subtitle//\"/\'}\"} sound name \"${sound}\"" >/dev/null 2>&1 || true
}
