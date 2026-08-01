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
  touch Package.swift
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
