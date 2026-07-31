#!/usr/bin/env bash
# make-menubar-icon.sh — render the monochrome TEMPLATE menu-bar icon.
# Menu-bar icons must be black-with-alpha (macOS tints them for light/dark and
# Tahoe's translucent bar) — the brand shows through the SHAPE (chip + pulse),
# color stays on the app icon and notifications. Flat ImageMagick draws only
# (this box's IM build mangles composites/SVG — see make-icon.sh).
# Output: MenuBarIcon.png, 36×36 (loaded at 18 pt, so it is the @2x raster).
set -euo pipefail
cd "$(dirname "$0")"

magick -size 144x144 xc:none \
  -fill black \
  -draw "roundrectangle 30,30 113,113 14,14" \
  -fill none -stroke black -strokewidth 10 \
  -draw "line 50,10 50,26"  -draw "line 72,10 72,26"  -draw "line 94,10 94,26" \
  -draw "line 50,118 50,134" -draw "line 72,118 72,134" -draw "line 94,118 94,134" \
  -draw "line 10,50 26,50"  -draw "line 10,72 26,72"  -draw "line 10,94 26,94" \
  -draw "line 118,50 134,50" -draw "line 118,72 134,72" -draw "line 118,94 134,94" \
  \( -size 144x144 xc:none -fill white \
     -draw "roundrectangle 42,42 101,101 8,8" \) \
  -compose DstOut -composite \
  -fill none -stroke black -strokewidth 10 \
  -draw "stroke-linecap round stroke-linejoin round polyline 48,72 60,72 68,54 78,88 84,72 96,72" \
  -resize 36x36 MenuBarIcon.png

magick identify MenuBarIcon.png
echo "built: $(pwd)/MenuBarIcon.png"
