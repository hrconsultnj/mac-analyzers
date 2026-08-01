#!/usr/bin/env bash
# build.sh — compile the SPM package and assemble + ad-hoc-sign MacAnalyzers.app.
# CLT-only (no Xcode). The bundle carries TWO executables: the menu-bar app and
# the `notify` CLI shim the bash scripts call (lib/notify.sh).
# Icon: reuses notifier/AppIcon.icns (regenerate with ../notifier/make-icon.sh).
set -euo pipefail
cd "$(dirname "$0")"

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

[[ -f AppIcon.icns ]] || ./make-icon.sh
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

[[ -f MenuBarIcon.png ]] || ./make-menubar-icon.sh
cp MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"

codesign --force --deep --sign - "$APP"
echo "built + signed: $(pwd)/$APP"
