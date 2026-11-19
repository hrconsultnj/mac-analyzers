#!/usr/bin/env bash
# upgrade.command — double-click me in Finder to update Mac Analyzers.
# For anyone who already cloned the repo: pulls the latest release, rebuilds
# the app, refreshes the background agents, and relaunches the menu-bar app.
# Safe to run any time; your config.local.sh is never touched.
set -euo pipefail
cd "$(dirname "$0")"

# --no-pull: rebuild from this clone as it is (rebuild.command), for work that is not committed yet
# --beta: move this clone (on development) forward to the tag of the newest published beta instead of pulling
#         (beta.command); when a release newer than that beta is out, the clone moves to that release's tag
pull=1
beta=0
[[ "${1:-}" == "--no-pull" ]] && pull=0
[[ "${1:-}" == "--beta" ]] && beta=1

echo "── Mac Analyzers upgrade ──────────────────────────"
if [[ "$beta" -eq 1 ]]; then
  if [[ "$(git rev-parse --abbrev-ref HEAD)" != "development" ]]; then
    echo "✗ Beta follows the development branch, and this clone is on another branch. Nothing was changed."
    exit 1
  fi
  echo "→ looking for the newest beta…"
  if ! fetch_out="$(git fetch --quiet --tags origin 2>&1)"; then
    echo "✗ Could not fetch from GitHub, so nothing was changed."
    echo "  git said: ${fetch_out}"
    exit 1
  fi
  # The newest PUBLISHED version: a beta sorts below the release it leads to (versionsort.suffix), so a release that
  # has caught up with its beta is what is installed. A tag counts only when GitHub has a release for it: a bare tag
  # (a beta that was tagged and never published) is skipped.
  api="${MA_GITHUB_API:-https://api.github.com/repos/hrconsultnj/mac-analyzers}"
  newest=""
  unreachable=""
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    rc=0
    code="$(curl -sSL --max-time 20 -o /dev/null -w '%{http_code}' "${api}/releases/tags/${candidate}" 2>/dev/null)" || rc=$?
    # 200 (or a file that was read) is a published release, 404 (or a file that is not there) is a bare tag; anything
    # else (no network, a proxy, GitHub limiting this network, a server error) says nothing about the tag
    if [[ "$rc" -eq 0 && ( "$code" == "200" || "$code" == "000" ) ]]; then
      newest="$candidate"
      break
    elif [[ "$rc" -eq 37 || ( "$rc" -eq 0 && "$code" == "404" ) ]]; then
      continue
    else
      unreachable="${code:-no answer}"
      break
    fi
  done < <(git -c versionsort.suffix=-beta tag --list 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$' | head -n 8 || true)
  if [[ -n "$unreachable" ]]; then
    echo "✗ Could not reach GitHub to see which versions are published (answer: ${unreachable}). Nothing was changed."
    echo "  Check the connection, or try again in a while if GitHub is limiting this network."
    exit 1
  fi
  if [[ -z "$newest" ]]; then
    echo "✗ No published beta or release was found on GitHub. Nothing was changed."
    exit 1
  fi
  # The clone moves to that tag exactly, never to the development tip, and only forward.
  target="$(git rev-list -n 1 "$newest")"
  here="$(git rev-parse HEAD)"
  if [[ "$here" == "$target" ]]; then
    echo "→ this clone is already at ${newest}"
  elif git merge-base --is-ancestor "$target" HEAD; then
    echo "✗ This clone is already past ${newest} (it has commits that come after it), so it cannot be moved back to it."
    echo "  Nothing was changed. Use This Copy to rebuild the clone as it is."
    exit 1
  elif ! git merge-base --is-ancestor HEAD "$target"; then
    echo "✗ This clone has commits that ${newest} does not, so it cannot be moved to it without a merge."
    echo "  Nothing was changed. Use This Copy to rebuild the clone as it is."
    exit 1
  else
    echo "→ moving this clone to ${newest}…"
    git merge --ff-only "$target"
  fi
elif [[ "$pull" -eq 1 ]]; then
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

# What is running now, by the name the app gives it (2.72.1 Beta, Dev · 8e2c9b0), not VERSION's number
running="$(/Applications/MacAnalyzers.app/Contents/MacOS/agent-runner --probe-build 2>/dev/null | sed -n 's/^Installed Version: *//p' | head -n 1 || true)"
[[ -n "$running" ]] || running="v$(cat VERSION)"
if [[ "$agents_ok" -eq 1 ]]; then
  echo "✓ Done — Mac Analyzers ${running} is running. You can close this window."
else
  echo "⚠ Mac Analyzers ${running} is running, but a background job could not be started (see above)."
  echo "  Run this again in a minute, or open Mac Analyzers → Setup to start it."
fi
