#!/usr/bin/env bash
# package.sh — build the downloads other people get:
#   MacAnalyzers-<V>.dmg   what a new user downloads: the app next to a
#                          shortcut to the Applications folder
#   MacAnalyzers-<V>.zip   the same signed app as an archive — what an
#                          installed copy downloads to update itself
#
#   scripts/package.sh                 # → dist/MacAnalyzers-<version>.{dmg,zip}
#   scripts/package.sh --out ~/Desktop # write them somewhere else
#
# It never touches the copy of the app you are running (the build is not
# installed) and never changes app/MacAnalyzers.app's signature — the image
# is made from a re-signed COPY.
#
# How the copy is signed decides what a stranger sees on first launch:
#
#   Developer ID + notarized   one "downloaded from the internet — Open"
#                              click, like any other Mac app.
#   anything else              macOS blocks the first launch; they must go to
#                              System Settings → Privacy & Security → Open
#                              Anyway. Once. Works, but reads as "unidentified
#                              developer".
#
# The first needs the paid Apple Developer Program. This script picks the best
# level this Mac can do, and says which one it produced:
#
#   MA_DIST_IDENTITY   signing identity for the download. Default: the
#                      keychain's "Developer ID Application" identity if there
#                      is one, otherwise ad-hoc. (A personal "Apple
#                      Development" identity is never used: it does not help a
#                      stranger's Mac trust the app, and it would publish the
#                      developer's email address inside every copy.)
#   MA_NOTARY_PROFILE  a `notarytool store-credentials` profile name. When set
#                      together with a Developer ID identity, the image is
#                      notarized and stapled.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

out="$root/dist"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="${2:?--out needs a folder}"; shift 2 ;;
    -h|--help) sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "package: unknown option '$1'" >&2; exit 2 ;;
  esac
done

version="$(tr -d ' \n' < VERSION)"
dmg="$out/MacAnalyzers-$version.dmg"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stage="$work/image"        # exactly what the disk image will contain
mkdir -p "$stage"

# ── 1. build, without installing ───────────────────────────────────────────
echo "→ building Mac Analyzers $version"
build_log="$work/build.log"
if ! MA_NO_INSTALL=1 ./app/build.sh >"$build_log" 2>&1; then
  echo "package: the build failed — last lines:" >&2
  grep -E "error:" -A4 "$build_log" | tail -30 >&2 || tail -20 "$build_log" >&2
  exit 1
fi

# ── 2. a copy to sign for other people's Macs ──────────────────────────────
app="$stage/MacAnalyzers.app"
ditto app/MacAnalyzers.app "$app"

identity="${MA_DIST_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
fi

if [[ "$identity" == "Developer ID Application:"* ]]; then
  level="Developer ID"
  # the notary service wants every executable signed on its own, with the
  # hardened runtime and a secure timestamp — inside out, never --deep
  for binary in notify agent-runner MacAnalyzersApp; do
    codesign --force --options runtime --timestamp \
      --entitlements app/MacAnalyzers.entitlements \
      --sign "$identity" "$app/Contents/MacOS/$binary"
  done
  codesign --force --options runtime --timestamp \
    --entitlements app/MacAnalyzers.entitlements --sign "$identity" "$app"
else
  level="ad-hoc"
  identity="-"
  codesign --force --deep --sign - "$app" 2>/dev/null
fi
codesign --verify --deep --strict "$app"
echo "→ signed: $level"

# ── 3. the disk image: the app next to a shortcut to Applications ──────────
ln -s /Applications "$stage/Applications"
mkdir -p "$out"
rm -f "$dmg"
# (macOS 27 prints a deprecation note for these flags; the image is the same
#  and this form also works on macOS 26)
hdiutil create -quiet -volname "Mac Analyzers" -srcfolder "$stage" \
  -format UDZO -fs HFS+ "$dmg" 2>/dev/null
hdiutil verify -quiet "$dmg"

# ── 4. sign / notarize the image itself ────────────────────────────────────
if [[ "$level" == "Developer ID" ]]; then
  codesign --force --timestamp --sign "$identity" "$dmg"
  if [[ -n "${MA_NOTARY_PROFILE:-}" ]]; then
    echo "→ notarizing (Apple checks the image; this can take a while)"
    xcrun notarytool submit "$dmg" --keychain-profile "$MA_NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
    level="Developer ID, notarized"
  fi
fi

# ── 5. the update archive: the SAME signed app, zipped ─────────────────────
# (made after stapling, so an update carries the notarization ticket too;
#  --sequesterRsrc --keepParent is the form updaters expect, symlinks intact)
if [[ "$level" == "Developer ID, notarized" ]]; then
  xcrun stapler staple "$app" >/dev/null
fi
zip="$out/MacAnalyzers-$version.zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

for artifact in "$dmg" "$zip"; do
  echo "→ $artifact ($(du -h "$artifact" | awk '{print $1}'))"
  echo "  sha256 $(shasum -a 256 "$artifact" | awk '{print $1}')"
done
case "$level" in
  "Developer ID, notarized")
    echo "  First launch on someone else's Mac: one \"Open\" click." ;;
  "Developer ID")
    echo "  NOT notarized — set MA_NOTARY_PROFILE, or macOS still blocks the first launch." ;;
  *)
    echo "  Signed ad-hoc: macOS blocks the first launch on someone else's Mac until they"
    echo "  choose System Settings → Privacy & Security → Open Anyway. A Developer ID"
    echo "  identity (Apple Developer Program) removes that step." ;;
esac
