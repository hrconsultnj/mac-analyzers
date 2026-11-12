#!/usr/bin/env bash
# sign-app.sh <MacAnalyzers.app> <identity | -> [--timestamp]
#
# The ONE way a copy of the app is signed: build.sh (the local install) and
# scripts/package.sh (the download) both call this, so every copy we make runs
# with the hardened runtime. The runtime makes macOS ignore DYLD_* variables and
# refuse a library the app was not signed with, so a program running as the same
# person cannot make the app load code of its choosing (for instance through
# `launchctl setenv DYLD_INSERT_LIBRARIES …`), and whatever speaks at an
# administrator prompt is the app's own code.
#
# Inside out, never `--deep` (deprecated for signing since macOS 13): each helper
# executable on its own, then the bundle, which signs the main executable and seals
# the scripts and resources. A helper left to the bundle's signature would keep the
# linker's (no hardened runtime), so each gets the runtime here. A helper's identifier
# stays what it has always been, its own file name ("notify", "agent-runner"), and is
# passed explicitly so it can never drift: macOS ties what a person has already
# allowed (a privacy consent, a background-item record) to the identifier in the
# signature, and a new name would make it ask again or forget. The entitlements file
# is the same for all three (app/MacAnalyzers.entitlements, read its comment).
#
# identity "-" signs ad-hoc (no certificate; the runtime still applies and is
# enforced). --timestamp is for a Developer ID signature that will be notarized.
set -euo pipefail

app="${1:?usage: sign-app.sh <app> <identity|-> [--timestamp]}"
identity="${2:?usage: sign-app.sh <app> <identity|-> [--timestamp]}"
timestamp="${3:-}"
here="$(cd "$(dirname "$0")" && pwd)"
entitlements="$here/MacAnalyzers.entitlements"

args=(--force --options runtime --entitlements "$entitlements" --sign "$identity")
[[ "$timestamp" == "--timestamp" ]] && args+=(--timestamp)

for helper in notify agent-runner; do
  [[ -f "$app/Contents/MacOS/$helper" ]] || { echo "sign-app: $app has no $helper" >&2; exit 1; }
  codesign "${args[@]}" --identifier "$helper" "$app/Contents/MacOS/$helper"
done
codesign "${args[@]}" "$app"
codesign --verify --strict --deep "$app"
