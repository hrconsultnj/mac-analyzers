#!/usr/bin/env bash
# upgrade.command — double-click me in Finder to update Sparehold.
# For anyone who already cloned the repo: pulls the latest release, moves an
# old checkout onto the Sparehold folders, rebuilds the app, refreshes the
# background agents, and relaunches the menu-bar app.
# Safe to run any time; your config.local.sh is never edited.
set -euo pipefail
# Run a copy of this file, from the clone. Installing a release or a beta checks the
# file out from that version; the copy that started is what has to quit the app and
# open it again. MA_UPGRADE_ROOT is the clone when the app runs the copy it was built with.
if [[ -n "${MA_UPGRADE_ROOT:-}" ]]; then
  root="$MA_UPGRADE_ROOT"
else
  root="$(cd "$(dirname "$0")" && pwd)"
fi
if [[ "${MA_UPGRADE_COPY:-}" != 1 ]]; then
  copy="$(mktemp -t sparehold-upgrade)"
  cp "$0" "$copy"
  chmod +x "$copy"
  export MA_UPGRADE_COPY=1
  export MA_UPGRADE_ROOT="$root"
  exec "${BASH:-/bin/bash}" "$copy" "$@"
fi
cd "$MA_UPGRADE_ROOT"

# --no-pull: rebuild from this clone as it is (rebuild.command), for work that is not committed yet
# --beta: move this clone forward to the newest published beta (beta.command). With --switch, check that
#         version out even when this clone is already past it (the Updates screen, when Beta is chosen)
# --release: check out the newest published release, even when this clone is past it
# --development: build the development branch as it is, returning to that branch first when this clone is elsewhere
# --switch: with --beta, install that beta even if this clone has commits after it. The branch itself is left where it is
pull=1
beta=0
release=0
development=0
switch=0
for arg in "$@"; do
  case "$arg" in
    --no-pull) pull=0 ;;
    --beta) beta=1 ;;
    --release) release=1 ;;
    --development) development=1 ;;
    --switch) switch=1 ;;
  esac
done

# A dirty tree is never thrown away. Checking out another version leaves the branch pointers where they are.
dirty() { [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; }
# The process name is what Launch Services records. Match that and the executable path.
app_running() {
  pgrep -x SpareholdApp >/dev/null 2>&1 || pgrep -x MacAnalyzersApp >/dev/null 2>&1 \
    || pgrep -f '/Sparehold.app/Contents/MacOS/SpareholdApp' >/dev/null 2>&1 \
    || pgrep -f '/MacAnalyzers.app/Contents/MacOS/MacAnalyzersApp' >/dev/null 2>&1
}
move_to() {
  local target="$1" label="$2" here
  here="$(git rev-parse HEAD)"
  if [[ "$here" == "$target" ]]; then
    echo "→ this clone is already at ${label}"
    return 0
  fi
  if dirty; then
    echo "✗ This clone has changes that are not committed, so it was not moved to ${label}."
    echo "  Nothing was changed. Commit them, or build Development to keep them."
    return 1
  fi
  echo "→ moving this clone to ${label}…"
  git checkout --detach "$target"
}

echo "── Sparehold upgrade ──────────────────────────────"
if [[ "$beta" -eq 1 ]]; then
  # beta.command only moves a clone that is on development, and only forward.
  # --switch is the Updates screen choosing this beta on purpose: check it out
  # from wherever this clone is, including a detached release or commits past it.
  # The branch pointer stays where it is. A dirty tree is still refused.
  if [[ "$switch" -eq 0 && "$(git rev-parse --abbrev-ref HEAD)" != "development" ]]; then
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
  api="${SPAREHOLD_GITHUB_API:-${MA_GITHUB_API:-https://api.github.com/repos/hrconsultnj/sparehold}}"
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
  if [[ "$switch" -eq 1 ]]; then
    move_to "$target" "$newest" || exit 1
  elif [[ "$here" == "$target" ]]; then
    echo "→ this clone is already at ${newest}"
  elif git merge-base --is-ancestor "$target" HEAD; then
    echo "✗ This clone is already past ${newest} (it has commits that come after it), so it cannot be moved back to it."
    echo "  Nothing was changed. Use Development to rebuild the clone as it is."
    exit 1
  elif ! git merge-base --is-ancestor HEAD "$target"; then
    echo "✗ This clone has commits that ${newest} does not, so it cannot be moved to it without a merge."
    echo "  Nothing was changed. Use Development to rebuild the clone as it is."
    exit 1
  else
    echo "→ moving this clone to ${newest}…"
    git merge --ff-only "$target"
  fi
elif [[ "$release" -eq 1 ]]; then
  echo "→ looking for the newest release…"
  if ! fetch_out="$(git fetch --quiet --tags origin 2>&1)"; then
    echo "✗ Could not fetch from GitHub, so nothing was changed."
    echo "  git said: ${fetch_out}"
    exit 1
  fi
  api="${SPAREHOLD_GITHUB_API:-${MA_GITHUB_API:-https://api.github.com/repos/hrconsultnj/sparehold}}"
  newest=""
  unreachable=""
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    rc=0
    code="$(curl -sSL --max-time 20 -o /dev/null -w '%{http_code}' "${api}/releases/tags/${candidate}" 2>/dev/null)" || rc=$?
    if [[ "$rc" -eq 0 && ( "$code" == "200" || "$code" == "000" ) ]]; then
      newest="$candidate"
      break
    elif [[ "$rc" -eq 37 || ( "$rc" -eq 0 && "$code" == "404" ) ]]; then
      continue
    else
      unreachable="${code:-no answer}"
      break
    fi
  done < <(git tag --list 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 8 || true)
  if [[ -n "$unreachable" ]]; then
    echo "✗ Could not reach GitHub to see which versions are published (answer: ${unreachable}). Nothing was changed."
    exit 1
  fi
  if [[ -z "$newest" ]]; then
    echo "✗ No published release was found on GitHub. Nothing was changed."
    exit 1
  fi
  target="$(git rev-list -n 1 "$newest")"
  move_to "$target" "$newest" || exit 1
elif [[ "$development" -eq 1 ]]; then
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$branch" != "development" ]]; then
    if dirty; then
      echo "✗ This clone has changes that are not committed, so it was not returned to development."
      echo "  Nothing was changed."
      exit 1
    fi
    echo "→ returning to the development branch…"
    if ! git checkout development 2>/dev/null; then
      # development can be held by another worktree (the release worktree):
      # its tip is the same commits, so detach onto it and build that —
      # the build reads as the dev version it is.
      echo "  (development is checked out by another worktree — building from its tip)"
      git checkout --detach development
    fi
  fi
  echo "→ building this clone as it is (nothing is pulled)…"
elif [[ "$pull" -eq 1 ]]; then
  echo "→ pulling the latest version…"
  git pull --ff-only
else
  echo "→ building this clone as it is (nothing is pulled)…"
fi

# The checkout is the new layout now. An older folder name is renamed and the
# old name is left as a link, so a schedule or a script that still uses it
# keeps working. The version probe's scratch clone has no copy of this file.
# shellcheck source=lib/layout-migrate.sh
if [[ -f lib/layout-migrate.sh ]]; then
  source lib/layout-migrate.sh
  sparehold_migrate_layout
fi

# build.sh also moves the checkout. This tells it the current updater is
# driving, so it leaves quitting, removing Mac Analyzers, and opening
# Sparehold to the steps below. An older updater does not set this, and
# build.sh finishes that cutover itself: that updater would open Mac
# Analyzers again.
export SPAREHOLD_UPGRADE=1
echo "→ rebuilding the app (this takes a minute)…"
# The Pro overlay joins when its package is on this Mac (build.sh --pro's own
# rule), so a channel install keeps what a local --pro build put in — without
# it, every update would quietly strip the licence features back out.
# a plain string, not an array: bash 3.2 explodes on an empty-array
# expansion under set -u, and the flags are at most one safe word
build_flags=""
if [[ -d "$HOME/sparehold-pro" || -d "$HOME/mac-analyzers-pro" ]]; then
  build_flags="--pro"
fi
# The build's full output goes to a file; the screen shows the result, or the
# errors when it fails. Compiler warnings are NOT hidden: the project is meant
# to build with none (scripts/check.sh enforces it), so if a build ever
# reports any, this says how many and keeps the file.
build_log="$(mktemp -t sparehold-build)"
if ./app/build.sh $build_flags >"$build_log" 2>&1; then
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

echo "→ quitting the running app before the background jobs move…"
# Quit first. The new app is already installed beside the old one. Do not
# delete MacAnalyzers.app until the new agent-runner answers.
if app_running; then
  osascript -e 'tell application id "com.mac-analyzers.app" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application id "com.sparehold.app" to quit' >/dev/null 2>&1 || true
  waited=0
  while app_running && [[ $waited -lt 8 ]]; do
    sleep 1
    waited=$((waited + 1))
  done
  if app_running; then
    pkill -TERM -x MacAnalyzersApp >/dev/null 2>&1 || true
    pkill -TERM -x SpareholdApp >/dev/null 2>&1 || true
    pkill -TERM -f '/MacAnalyzers.app/Contents/MacOS/MacAnalyzersApp' >/dev/null 2>&1 || true
    pkill -TERM -f '/Sparehold.app/Contents/MacOS/SpareholdApp' >/dev/null 2>&1 || true
    waited=0
    while app_running && [[ $waited -lt 5 ]]; do
      sleep 1
      waited=$((waited + 1))
    done
  fi
  if app_running; then
    pkill -KILL -x MacAnalyzersApp >/dev/null 2>&1 || true
    pkill -KILL -x SpareholdApp >/dev/null 2>&1 || true
    pkill -KILL -f '/MacAnalyzers.app/Contents/MacOS/MacAnalyzersApp' >/dev/null 2>&1 || true
    pkill -KILL -f '/Sparehold.app/Contents/MacOS/SpareholdApp' >/dev/null 2>&1 || true
    waited=0
    while app_running && [[ $waited -lt 5 ]]; do
      sleep 1
      waited=$((waited + 1))
    done
  fi
fi

echo "→ moving the background jobs to Sparehold…"
# install copies a custom Hour, Minute or StartInterval off the old plist when
# the new one is not there yet, boots out the old label, deletes that plist,
# and loads the new one. It does not boot out the new agent afterwards.
agents_ok=1
./memory/memory-manage-agents.sh install || agents_ok=0
./storage/storage-manage-agents.sh install || agents_ok=0

# The move is done and the jobs point at the new folders. Drop the old names
# so this Mac does not keep a second copy.
if declare -F sparehold_remove_old_names >/dev/null 2>&1; then
  sparehold_remove_old_names
fi

echo "→ checking the new app…"
probe_bin="/Applications/Sparehold.app/Contents/MacOS/agent-runner"
[[ -x "$probe_bin" ]] || probe_bin="$MA_UPGRADE_ROOT/app/Sparehold.app/Contents/MacOS/agent-runner"
if ! running="$("$probe_bin" --probe-build 2>/dev/null | sed -n 's/^Installed Version: *//p' | head -n 1)"; then
  echo "✗ Sparehold's agent-runner did not answer, so Mac Analyzers was left installed."
  [[ -d /Applications/MacAnalyzers.app ]] && open -g /Applications/MacAnalyzers.app || true
  exit 1
fi
[[ -n "$running" ]] || running="v$(cat VERSION)"

# Only after the new app answers. Never pkill once Sparehold is opened below.
if [[ -d /Applications/MacAnalyzers.app ]]; then
  echo "→ removing the previous app…"
  rm -rf /Applications/MacAnalyzers.app
fi

echo "→ opening Sparehold…"
if [[ -d /Applications/Sparehold.app ]]; then
  open -g /Applications/Sparehold.app
else
  open -g "$MA_UPGRADE_ROOT/app/Sparehold.app"
fi
if [[ "$agents_ok" -eq 1 ]]; then
  echo "✓ Done — Sparehold ${running} is running. You can close this window."
else
  echo "⚠ Sparehold ${running} is running, but a background job could not be started (see above)."
  echo "  Run this again in a minute, or open Sparehold → Setup to start it."
fi
