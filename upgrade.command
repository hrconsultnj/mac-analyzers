#!/usr/bin/env bash
# upgrade.command — double-click me in Finder to update Mac Analyzers.
# For anyone who already cloned the repo: pulls the latest release, rebuilds
# the app, refreshes the background agents, and relaunches the menu-bar app.
# Safe to run any time; your config.local.sh is never touched.
set -euo pipefail
cd "$(dirname "$0")"

# --no-pull: rebuild from this clone as it is (rebuild.command), for work that is not committed yet
pull=1
[[ "${1:-}" == "--no-pull" ]] && pull=0

echo "── Mac Analyzers upgrade ──────────────────────────"
if [[ "$pull" -eq 1 ]]; then
  echo "→ pulling the latest version…"
  git pull --ff-only
else
  echo "→ building this clone as it is (nothing is pulled)…"
fi

echo "→ rebuilding the app (this takes a minute)…"
# The build's full output goes to a file; the screen shows the result, or the
# errors when it fails. Compiler warnings are NOT hidden: the project is meant
# to build with none (scripts/check.sh enforces it), so if a build ever
# reports any, this says how many and keeps the file.
build_log="$(mktemp -t mac-analyzers-build)"
if ./app/build.sh >"$build_log" 2>&1; then
  grep -E '^(installed:|note: could not install)' "$build_log" | sed 's/^/  /' || true
  build_warnings="$(grep -c 'warning: ' "$build_log" || true)"
  if [[ "${build_warnings:-0}" -gt 0 ]]; then
    echo "  ⚠ the build reported ${build_warnings} compiler warning line(s) — they are a defect to report; saved in: $build_log"
  else
    rm -f "$build_log"
  fi
else
  echo "✗ The app could not be built, so the copy you have installed was not changed."
  if grep -q 'error:' "$build_log"; then
    grep -E 'error:' -A3 "$build_log" | head -40
  else
    tail -n 20 "$build_log"
  fi
  echo "  The full build output is in: $build_log"
  exit 1
fi

echo "→ refreshing the background agents…"
agents_ok=1
./memory-analyzer/memory-manage-agents.sh install || agents_ok=0
./storage-analyzer/storage-manage-agents.sh install || agents_ok=0

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

if [[ "$agents_ok" -eq 1 ]]; then
  echo "✓ Done — Mac Analyzers $(cat VERSION) is running. You can close this window."
else
  echo "⚠ Mac Analyzers $(cat VERSION) is running, but a background job could not be started (see above)."
  echo "  Run this again in a minute, or open Mac Analyzers → Setup to start it."
fi
