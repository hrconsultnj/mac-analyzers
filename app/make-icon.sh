#!/usr/bin/env bash
# make-icon.sh — render the MacAnalyzers app icon and assemble AppIcon.icns.
# Pure ImageMagick draw (its SVG renderer drops gradients), Composure palette:
#   navy oklch(0.45 .12 255)≈#33639C · navy-light oklch(0.55 .14 255)≈#4A7FC1
#   gold oklch(0.82 .15 80)≈#E9BA4F
# Requires: imagemagick (brew), sips + iconutil (macOS).
set -euo pipefail
cd "$(dirname "$0")"

# 1) flat navy macOS rounded square (840px on a 1024 canvas) — deliberately no
#    gradient: this ImageMagick build mangles mask composites at this size, and
#    flat reads better at menu-bar/notification sizes anyway
magick -size 1024x1024 xc:none -fill '#2E5C97' \
  -draw "roundrectangle 92,92 931,931 189,189" icon_base.png

# 2) chip glyph: gold pins, gold body, navy die, gold monitoring pulse
magick icon_base.png \
  -fill '#E9BA4F' \
  -draw "roundrectangle 252,368 331,407 20,20" \
  -draw "roundrectangle 252,464 331,503 20,20" \
  -draw "roundrectangle 252,560 331,599 20,20" \
  -draw "roundrectangle 252,656 331,695 20,20" \
  -draw "roundrectangle 692,368 771,407 20,20" \
  -draw "roundrectangle 692,464 771,503 20,20" \
  -draw "roundrectangle 692,560 771,599 20,20" \
  -draw "roundrectangle 692,656 771,695 20,20" \
  -draw "roundrectangle 400,252 439,331 20,20" \
  -draw "roundrectangle 492,252 531,331 20,20" \
  -draw "roundrectangle 584,252 623,331 20,20" \
  -draw "roundrectangle 400,732 439,811 20,20" \
  -draw "roundrectangle 492,732 531,811 20,20" \
  -draw "roundrectangle 584,732 623,811 20,20" \
  -fill '#EBBE55' -draw "roundrectangle 312,312 711,751 64,64" \
  -fill '#1A3355' -draw "roundrectangle 352,352 671,711 40,40" \
  -fill none -stroke '#F0C868' -strokewidth 26 \
  -draw "stroke-linecap round stroke-linejoin round polyline 376,548 448,548 484,452 528,624 564,500 588,548 648,548" \
  icon_1024.png
rm -f icon_base.png

# 3) iconset → AppIcon.icns
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" icon_1024.png --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" icon_1024.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset
echo "built: $(pwd)/AppIcon.icns"
