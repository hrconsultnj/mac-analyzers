#!/usr/bin/env bash
# make-icon.sh — assemble AppIcon.icns from the Keep mark already drawn.
# The Default sizes live in Assets/AppIcon (16, 32, 128, 256, 512 and @2x).
# This copies them. It does not draw, and it does not call ictool or actool.
# iconutil ships with the Command Line Tools. build.sh only copies the icns.
set -euo pipefail
cd "$(dirname "$0")"

src="Assets/AppIcon"
rm -rf AppIcon.iconset
mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  base="${src}/icon-Default-${s}"
  [[ -f "${base}.png" ]] || { echo "missing ${base}.png" >&2; exit 1; }
  [[ -f "${base}@2x.png" ]] || { echo "missing ${base}@2x.png" >&2; exit 1; }
  cp "${base}.png" "AppIcon.iconset/icon_${s}x${s}.png"
  cp "${base}@2x.png" "AppIcon.iconset/icon_${s}x${s}@2x.png"
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset
echo "built: $(pwd)/AppIcon.icns"
