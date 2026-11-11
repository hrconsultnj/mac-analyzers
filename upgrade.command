#!/usr/bin/env bash
# upgrade.command — double-click me in Finder to update Mac Analyzers.
# For anyone who already cloned the repo: pulls the latest release, rebuilds
# the app, refreshes the background agents, and relaunches the menu-bar app.
# Safe to run any time; your config.local.sh is never touched.
set -euo pipefail
cd "$(dirname "$0")"

echo "── Mac Analyzers upgrade ──────────────────────────"
echo "→ pulling the latest version…"
git pull --ff-only

echo "→ rebuilding the app…"
./app/build.sh

echo "→ refreshing the background agents…"
./memory-analyzer/memory-manage-agents.sh install
./storage-analyzer/storage-manage-agents.sh install

echo "→ relaunching the menu-bar app…"
# Ask the app to quit the way a person would (so it can offer to stop or finish a
# running cleanup and record it), wait a bounded time, and only then end it.
if pgrep -x MacAnalyzersApp >/dev/null 2>&1; then
  # Wait only if the request got through: when macOS refuses to let Terminal
  # ask (the Automation permission), waiting a minute would achieve nothing.
  if osascript -e 'tell application id "com.mac-analyzers.app" to quit' >/dev/null 2>&1; then
    waited=0
    while pgrep -x MacAnalyzersApp >/dev/null 2>&1 && [[ $waited -lt 60 ]]; do
      sleep 1
      waited=$((waited + 1))
    done
  fi
  pkill -x MacAnalyzersApp 2>/dev/null || true
fi
sleep 1
if [[ -d /Applications/MacAnalyzers.app ]]; then
  open -g /Applications/MacAnalyzers.app
else
  open -g app/MacAnalyzers.app
fi

echo "✓ Done — Mac Analyzers $(cat VERSION) is running. You can close this window."
