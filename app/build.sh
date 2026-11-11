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

# --disable-keychain + no git credential helper: SwiftPM's default is to look
# in the macOS keychain for a saved login whenever it downloads from a host,
# and git asks its keychain helper the same question — which puts a "wants to
# use your confidential information" prompt in front of whoever is building.
# Everything this build downloads is public, so it never needs a credential.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
swift build -c release --disable-keychain
BIN="$(swift build --show-bin-path -c release --disable-keychain)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
# the repo's VERSION file is the single source of truth — inject it so the
# app can compare itself against the latest GitHub release
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(tr -d ' \n' < ../VERSION)" \
  "$APP/Contents/Info.plist" 2>/dev/null || true
# Build stamp: the version only changes at a release, so two builds made an
# hour apart look identical on screen. The Update screen shows this instead:
# which commit this copy was built from (marked when the working tree had
# uncommitted changes) and when.
REVISION="$(git -C .. rev-parse --short HEAD 2>/dev/null || echo "unknown")"
[[ -n "$(git -C .. status --porcelain 2>/dev/null)" ]] && REVISION="$REVISION, with local changes"
/usr/libexec/PlistBuddy -c "Add :MABuildRevision string $REVISION" \
  -c "Add :MABuildDate string $(date '+%b %-d at %H:%M')" "$APP/Contents/Info.plist" 2>/dev/null || true
cp "$BIN/MacAnalyzersApp" "$APP/Contents/MacOS/MacAnalyzersApp"
cp "$BIN/NotifierCLI" "$APP/Contents/MacOS/notify"
cp "$BIN/AgentRunner" "$APP/Contents/MacOS/agent-runner"

[[ -f AppIcon.icns ]] || ./make-icon.sh
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Bundled changelog: the newest 20 entries of the repo's CHANGELOG.md — the
# same file each GitHub release publishes, so the app's What's New and the
# release page can never say different things.
awk '/^## v[0-9]/{count++} count>20{exit} count>0{print}' ../CHANGELOG.md \
  > "$APP/Contents/Resources/CHANGELOG.md" 2>/dev/null || true

# Bundled engine: the bash suite ships INSIDE the app, so a downloaded copy
# works without cloning anything. The manage-agents installers hydrate
# __SUITE_DIR__ from their own location, so they run unchanged from in here.
ENGINE="$APP/Contents/Resources/engine"
mkdir -p "$ENGINE"
# Only files that belong to the project go in: tracked files plus new ones
# git would accept. A plain recursive copy also swept up whatever happened to
# sit in those folders on the build machine — editor and assistant session
# state, local planning notes, .DS_Store — and shipped it inside the app.
for dir in memory-analyzer storage-analyzer network-analyzer lib; do
  [[ -d "../$dir" ]] || continue
  if git -C .. rev-parse --git-dir >/dev/null 2>&1; then
    (cd .. && git ls-files -z --cached --others --exclude-standard -- "$dir") \
      | while IFS= read -r -d '' file; do
          [[ -f "../$file" && "$file" != */tests/* ]] || continue
          mkdir -p "$ENGINE/$(dirname "$file")"
          cp -p "../$file" "$ENGINE/$file"
        done
  else
    # a source download with no git history: copy, minus the usual strays
    rsync -a --exclude 'tasks-plans' --exclude '.composure' --exclude '.claude' \
      --exclude '.DS_Store' --exclude 'tests' "../$dir" "$ENGINE/"
  fi
done
cp ../config.example.sh "$ENGINE/" 2>/dev/null || true
cp ../VERSION "$ENGINE/" 2>/dev/null || true
find "$ENGINE" -name '*.sh' -exec chmod +x {} +

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

# replace_install <built bundle> <installed path> — swap the installed app for
# the new build without ever leaving that path empty:
#   1. an earlier attempt that died after moving the old app aside is undone
#      first (the old copy goes back), and its half-made copy is removed —
#      copying INTO a leftover would merge two builds;
#   2. the new build is copied next to the installed one;
#   3. the installed one is moved aside, the new one moved in;
#   4. if that last move fails, the old one is moved back.
# The agents' entry point lives inside the installed app, so "no app there"
# would stop every scheduled job.
replace_install() {
  local src="$1" dst="$2"
  if [[ ! -e "$dst" && -e "$dst.old" ]]; then mv "$dst.old" "$dst" 2>/dev/null || return 1; fi
  rm -rf "$dst.new" "$dst.old" 2>/dev/null
  [[ -e "$dst.new" || -e "$dst.old" ]] && return 1
  ditto "$src" "$dst.new" 2>/dev/null || { rm -rf "$dst.new" 2>/dev/null; return 1; }
  if [[ -e "$dst" ]]; then
    mv "$dst" "$dst.old" 2>/dev/null || { rm -rf "$dst.new" 2>/dev/null; return 1; }
  fi
  if mv "$dst.new" "$dst" 2>/dev/null; then
    rm -rf "$dst.old" 2>/dev/null
    return 0
  fi
  [[ -e "$dst.old" ]] && mv "$dst.old" "$dst" 2>/dev/null
  rm -rf "$dst.new" 2>/dev/null
  return 1
}

# install to /Applications — the canonical location for the running app; the
# repo copy is the build artifact / script-only fallback. A locally built app
# carries no quarantine, so no DMG/notarization is involved.
INSTALL="/Applications/MacAnalyzers.app"
# MA_NO_INSTALL=1: build the bundle and stop — scripts/package.sh uses this so
# making a download for other people never touches the copy you are running.
if [[ "${MA_NO_INSTALL:-0}" == "1" ]]; then
  echo "not installed (MA_NO_INSTALL=1)"
elif replace_install "$APP" "$INSTALL"; then
  # REPLACED, not copied over: copying a bundle onto the installed one keeps
  # every file the new build no longer contains, so removed files lived on in
  # /Applications forever and the installed copy's signature stopped
  # verifying (files present that the seal does not list). A running app is
  # unaffected — it keeps the files it already has open until it relaunches.
  echo "installed: $INSTALL"
else
  echo "note: could not install to /Applications (permissions?) — running from the repo copy still works"
fi
