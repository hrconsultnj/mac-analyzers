#!/usr/bin/env bash
# build.sh — compile the SPM package and assemble + ad-hoc-sign MacAnalyzers.app.
# CLT-only (no Xcode). The bundle carries TWO executables: the menu-bar app and
# the `notify` CLI shim the bash scripts call (lib/notify.sh).
# Icon: reuses notifier/AppIcon.icns (regenerate with ../notifier/make-icon.sh).
set -euo pipefail
cd "$(dirname "$0")"

# --pro: include the local overlay package (module resolved via MA_PRO_PATH).
# touch busts SPM's manifest cache, which does not key on environment.
if [[ "${1:-}" == "--pro" ]]; then
  export MA_PRO_PATH="${MA_PRO_PATH:-$HOME/mac-analyzers-pro}"
fi
# Mode switches (overlay <-> plain) poison SPM incremental state: object
# files keep references to the overlay module. Detect and force recompiles.
MODE="$([[ -n "${MA_PRO_PATH:-}" ]] && echo pro || echo public)"
LAST_MODE_FILE=".build/.ma-build-mode"
# Overlay source changes (new files in the local package) are invisible to
# SPM's cached target file lists — fold the overlay's newest mtime into the
# mode key so adding a file there forces a clean resolve.
if [[ -n "${MA_PRO_PATH:-}" && -d "$MA_PRO_PATH/Sources" ]]; then
  MODE="$MODE-$(find "$MA_PRO_PATH/Sources" -name '*.swift' -exec stat -f %m {} + 2>/dev/null | sort -rn | head -1)"
fi
if [[ "$(cat "$LAST_MODE_FILE" 2>/dev/null || echo none)" != "$MODE" ]]; then
  rm -rf .build   # stale overlay refs survive touch-level invalidation
  mkdir -p .build && echo "$MODE" > "$LAST_MODE_FILE"
fi

APP="MacAnalyzers.app"

swift build -c release
BIN="$(swift build --show-bin-path -c release)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
# the repo's VERSION file is the single source of truth — inject it so the
# app can compare itself against the latest GitHub release
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(tr -d ' \n' < ../VERSION)" \
  "$APP/Contents/Info.plist" 2>/dev/null || true
cp "$BIN/MacAnalyzersApp" "$APP/Contents/MacOS/MacAnalyzersApp"
cp "$BIN/NotifierCLI" "$APP/Contents/MacOS/notify"
cp "$BIN/AgentRunner" "$APP/Contents/MacOS/agent-runner"

[[ -f AppIcon.icns ]] || ./make-icon.sh
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Bundled changelog: release-note commits (subjects starting vN.N) ARE the
# notes — newest 20, attribution footers stripped.
git -C .. log --first-parent -E --grep='^v[0-9]+\.[0-9]+' -n 60 \
    --format='## %s%n%n%b%n' development 2>/dev/null \
  | grep -vE '^(Co-Authored-By:|Claude-Session:)' \
  | awk '/^## v[0-9]/{count++} count>20{exit} {print}' \
  > "$APP/Contents/Resources/CHANGELOG.md" || true

[[ -f MenuBarIcon.png ]] || ./make-menubar-icon.sh
cp MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"

# prefer a real Apple Development identity (Team ID → BTM attribution, stable
# TCC identity across rebuilds); ad-hoc fallback keeps zero-setup builds working
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "built + signed: $(pwd)/$APP  [$IDENTITY]"
else
  codesign --force --deep --sign - "$APP"
  echo "built + signed: $(pwd)/$APP  [ad-hoc — add an Apple Development cert for BTM attribution]"
fi

# install to /Applications — the canonical location for the running app; the
# repo copy is the build artifact / script-only fallback. A locally built app
# carries no quarantine, so no DMG/notarization is involved.
INSTALL="/Applications/MacAnalyzers.app"
if ditto "$APP" "$INSTALL" 2>/dev/null; then
  echo "installed: $INSTALL"
else
  echo "note: could not install to /Applications (permissions?) — running from the repo copy still works"
fi
