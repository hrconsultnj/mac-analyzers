#!/usr/bin/env bash
# make-menubar-icon.sh — copy the Keep menu-bar template.
# The app loads MenuBarIcon.png at 18 pt, so this file is the 36×36 @2x raster.
# Pixels are replaced from Assets/MenuBar. Nothing is drawn here.
set -euo pipefail
cd "$(dirname "$0")"

src="Assets/MenuBar/SpareholdTemplate-18@2x.png"
[[ -f "$src" ]] || { echo "missing $src" >&2; exit 1; }
cp "$src" MenuBarIcon.png
echo "built: $(pwd)/MenuBarIcon.png"
