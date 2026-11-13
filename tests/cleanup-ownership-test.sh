#!/usr/bin/env bash
# cleanup-ownership-test.sh — what an app removal OWNS, and whether the app is really unused. Every case is a
# reproduction of something that went wrong or could: in a throwaway HOME, with stand-in apps, stand-in `mdls`,
# `mdutil`, `codesign`, `pgrep`, `stat` and `df` on PATH. Never the real /Applications, the real Trash or the
# person's logs. Run under `bash` and /bin/bash (3.2).
#
#   S1  another app's shared data: ids that contain one another (com.vendor.app / com.vendor.app2 / .helper),
#       group containers taken only for groups the app's own entitlements name and no other app names
#   S2  an app that cannot be moved: nothing else of it is touched
#   S3  a folder that carries a generic app name (Electron) is left in place, with its size
#   S4  apps in use that look unused: `open -a`, `open -b`, osascript, a shell wrapper; apps the person configured
#       get the same checks when reviewed; login items need a fresh audit inventory
#   S6  recordings: chosen by their newest file; another disk's own Trash; a disk with none keeps the recording
#
# Usage: tests/cleanup-ownership-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../storage-analyzer/cleanup.sh"
[[ -f "$SCRIPT" ]] || { echo "SKIP: script not found"; exit 0; }

TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }

ENT_HEAD='<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.security.application-groups</key><array>'
ENT_TAIL='</array></dict></plist>'

# the inventory header the audit writes: version 2, the run's date, whether it could read the login items
inventory() { # file [version] [date] [logins]
  printf '#login-items-inventory\t%s\t%s\tdry-run\tid\t%s\n' "${2:-2}" "${3:-$(date '+%Y-%m-%d %H:%M:%S')}" "${4:-logins=read}" > "$1"
}

# a fresh world: HOME, an install folder, a launch folder, an inventory the audit "wrote today", stand-in tools
world() { # name -> sets W (the folder) and S (the stand-ins' folder)
  W="$TMP/w-$K-$1"; S="$W/stubs"
  mkdir -p "$W/home/Library/Application Support" "$W/home/Library/Group Containers" "$W/home/Library/Preferences/ByHost" \
           "$W/home/.Trash" "$W/apps" "$W/launch" "$W/ent" "$S" "$W/tree/storage-analyzer" "$W/tree/lib"
  cp "$SCRIPT" "$W/tree/storage-analyzer/cleanup.sh"; cp "$HERE"/../lib/*.sh "$W/tree/lib/"
  inventory "$W/inventory.tsv"
  printf '#!/bin/bash\nexit 1\n' > "$S/pgrep"        # nothing is running, whatever the real machine has (S4c replaces it)
  printf 'ANALYZERS_APP_DIRS="%s/apps"\nANALYZERS_LAUNCH_DIRS="%s/launch"\nANALYZERS_LOGIN_INVENTORY="%s/inventory.tsv"\n%s' \
    "$W" "$W" "$W" "${EXTRA_CONFIG:-}" > "$W/tree/config.local.sh"
  # Spotlight: every app was last opened long ago and added long ago; the bundle id comes from Info.plist
  cat > "$S/mdls" <<'STUB'
#!/bin/bash
case "$2" in
  kMDItemCFBundleIdentifier) echo "(null)";;
  kMDItemLastUsedDate) [[ "$4" == *RecentNested* ]] && echo "$(date -v-2d '+%Y-%m-%d %H:%M:%S %z')" || echo "2024-01-02 03:04:05 +0000";;
  *) echo "2020-01-01 00:00:00 +0000";;
esac
STUB
  printf '#!/bin/bash\necho "/: Indexing enabled."\n' > "$S/mdutil"
  # codesign: the entitlements of an app come from ent/<App>.xml; none means it is not signed (no groups); ent/<App>.unreadable
  # means codesign fails for another reason (the entitlements cannot be read)
  cat > "$S/codesign" <<STUB
#!/bin/bash
app=""; for a in "\$@"; do app="\$a"; done
n="\${app##*/}"; n="\${n%.app}"; n="\${n%.APP}"; n="\${n%.appex}"; n="\${n%.xpc}"; n="\${n%.systemextension}"; n="\${n%.dext}"
[[ -f "$W/ent/\$n.xml" ]] && { cat "$W/ent/\$n.xml"; exit 0; }
[[ -f "$W/ent/\$n.hang" ]] && { echo \$\$ >> "$W/hang.pids"; exec sleep 60; }        # a codesign that never answers
[[ -f "$W/ent/\$n.die" ]] && kill -9 "\$(ps -o ppid= -p \$PPID | tr -d ' ')"   # a read whose whole job is killed before it writes its file
[[ -f "$W/ent/\$n.stub" ]] && { echo "\$app: bundle format unrecognized, invalid, or unsuitable" >&2; exit 1; }   # a folder that only looks like a bundle
[[ -f "$W/ent/\$n.unreadable" ]] && { echo "\$app: permission denied" >&2; exit 1; }
echo "\$app: code object is not signed at all" >&2; exit 1
STUB
  chmod +x "$S/mdls" "$S/mdutil" "$S/codesign" "$S/pgrep"
}
mkapp() { # name bid [extra plist keys]
  mkdir -p "$W/apps/$1.app/Contents"
  printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string>%s</dict></plist>' "$2" "${3:-}" > "$W/apps/$1.app/Contents/Info.plist"
}
run() { # args: the script's arguments; output on stdout
  PATH="$S:$PATH" HOME="$W/home" "$SH" "$W/tree/storage-analyzer/cleanup.sh" "$@" 2>&1
}
block() { sed -n "/^### APP: $1   (bundle/,/^### APP:/p" <<<"$2"; }                          # one app's part of a run
paths_of() { sed -nE 's/^  \[DRY\] +[0-9.]+ [KMGT]?B +//p' <<<"$1"; }              # the [DRY] paths of a block
in_trash() { [[ -e "$W/home/.Trash/$1" ]]; }

for SH in bash /bin/bash; do
  K="$(echo "$SH" | tr / _)"
  sh="$SH"

  # ---------------------------------------------------------------- S1: what an app owns, by exact name
  world s1
  mkapp VendorApp com.vendor.app; mkapp VendorApp2 com.vendor.app2; mkapp NoEnt com.nogroups.app
  printf '%s<string>TEAM123.com.vendor.app</string><string>group.shared</string>%s' "$ENT_HEAD" "$ENT_TAIL" > "$W/ent/VendorApp.xml"
  printf '%s<string>TEAM123.com.vendor.app2</string><string>group.shared</string>%s' "$ENT_HEAD" "$ENT_TAIL" > "$W/ent/VendorApp2.xml"
  L="$W/home/Library"
  mkdir -p "$L/Application Support/com.vendor.app" "$L/Group Containers/TEAM123.com.vendor.app" "$L/Group Containers/TEAM123.com.vendor.app2" \
           "$L/Group Containers/group.shared" "$L/Group Containers/TEAM9.com.nogroups.app"
  printf x > "$L/Application Support/com.vendor.app/data"; printf x > "$L/Group Containers/TEAM123.com.vendor.app/d"
  printf x > "$L/Group Containers/TEAM123.com.vendor.app2/d"; printf x > "$L/Group Containers/group.shared/d"; printf x > "$L/Group Containers/TEAM9.com.nogroups.app/d"
  printf x > "$L/Preferences/ByHost/com.vendor.app.helper.ABCD.plist"
  printf x > "$L/Preferences/ByHost/com.vendor.app.01234567-89AB-CDEF-0123-456789ABCDEF.plist"
  out="$(run --stale-apps)"; mine="$(block VendorApp "$out")"
  check "[$sh] S1 the app's own group container (its entitlements name it) and its exact ByHost file are listed" \
        "$([[ "$mine" == *"$L/Group Containers/TEAM123.com.vendor.app"$'\n'* && "$mine" == *"com.vendor.app.01234567-89AB-CDEF-0123-456789ABCDEF.plist"* ]] && echo ok || echo "$mine")"
  check "[$sh] S1 another app's group container (com.vendor.app2) is NOT in this app's footprint" \
        "$([[ "$(paths_of "$mine")" != *"TEAM123.com.vendor.app2"* ]] && echo ok || echo "taken")"
  check "[$sh] S1 a different component's ByHost file (com.vendor.app.helper…) is NOT in it" \
        "$([[ "$(paths_of "$mine")" != *"helper.ABCD"* ]] && echo ok || echo "taken")"
  check "[$sh] S1 a group both apps declare is left in place, and says another app shares it" \
        "$([[ "$mine" == *"[LEFT]"*"group.shared"*"another app shares"* && "$(paths_of "$mine")" != *"group.shared"* ]] && echo ok || echo "wrong")"
  check "[$sh] S1 an app whose entitlements cannot be read takes no group container" \
        "$([[ "$(paths_of "$(block NoEnt "$out")")" != *"Group Containers"* ]] && echo ok || echo "taken")"
  paths_of "$mine" > "$W/list"; printf '%s\n' "$W/apps/VendorApp.app" >> "$W/list"
  run --stale-apps --execute --yes --only-paths "$W/list" >/dev/null
  check "[$sh] S1 applying removes the app's own data" "$([[ ! -e "$L/Application Support/com.vendor.app" && ! -e "$L/Group Containers/TEAM123.com.vendor.app" ]] && in_trash VendorApp.app && echo ok || echo "not moved")"
  check "[$sh] S1 and leaves the neighbours' data where it was" \
        "$([[ -e "$L/Group Containers/TEAM123.com.vendor.app2" && -e "$L/Group Containers/group.shared" && -e "$L/Group Containers/TEAM9.com.nogroups.app" && -e "$L/Preferences/ByHost/com.vendor.app.helper.ABCD.plist" && -d "$W/apps/VendorApp2.app" ]] && echo ok || echo "touched")"

  # ---------------------------------------------------------------- S1b: a group shared with an app anywhere else
  world s1b
  L="$W/home/Library"; G="$L/Group Containers"
  nested() { mkdir -p "$1/Contents"; printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>' "$2" > "$1/Contents/Info.plist"; }
  mkapp GroupA com.g.a
  printf '%s<string>TEAM.shared.group</string><string>TEAM.only.a</string><string>TEAM.own.helper</string><string>TEAM.hostshared</string>%s' "$ENT_HEAD" "$ENT_TAIL" > "$W/ent/GroupA.xml"
  nested "$W/apps/Suite/GroupB.app" com.g.b                                          # one folder down
  printf '%s<string>TEAM.shared.group</string>%s' "$ENT_HEAD" "$ENT_TAIL" > "$W/ent/GroupB.xml"
  nested "$W/apps/GroupA.app/Contents/Helpers/AHelper.app" com.g.a.helper # the app's OWN helper, same group as the app
  printf '%s<string>TEAM.own.helper</string>%s' "$ENT_HEAD" "$ENT_TAIL" > "$W/ent/AHelper.xml"
  mkapp Host com.g.host
  nested "$W/apps/Host.app/Contents/Library/LoginItems/Hlp.app" com.g.host.hlp        # a helper INSIDE another app's bundle
  printf '%s<string>TEAM.hostshared</string>%s' "$ENT_HEAD" "$ENT_TAIL" > "$W/ent/Hlp.xml"
  for g in TEAM.shared.group TEAM.only.a TEAM.own.helper TEAM.hostshared; do mkdir -p "$G/$g"; printf x > "$G/$g/d"; done
  # (an app with an app inside it is kept when found, so its footprint is read the way a named app's is: --list-app)
  list_a() { run --list-app "$W/apps/GroupA.app"; }
  out="$(list_a)"; mine="$(block GroupA "$out")"
  check "[$sh] T1 a group shared with an app one folder down (Suite/GroupB.app) is left in place, not taken" \
        "$([[ "$mine" == *"[LEFT]"*"TEAM.shared.group"*"another app shares"* && "$(paths_of "$mine")" != *"TEAM.shared.group"* ]] && echo ok || echo "$mine")"
  check "[$sh] T1 a group shared with a helper app inside ANOTHER app's bundle is left in place" \
        "$([[ "$mine" == *"[LEFT]"*"TEAM.hostshared"*"another app shares"* && "$(paths_of "$mine")" != *"TEAM.hostshared"* ]] && echo ok || echo "$mine")"
  check "[$sh] T1 a group only the app and ITS OWN helper declare is still the app's" \
        "$([[ "$(paths_of "$mine")" == *"TEAM.own.helper"* && "$(paths_of "$mine")" == *"TEAM.only.a"* ]] && echo ok || echo "$mine")"
  # an app whose entitlements cannot be read anywhere: "shared elsewhere" is unknown, so nothing is taken, and it says so
  mkapp Broken com.g.broken; : > "$W/ent/Broken.unreadable"
  out="$(list_a)"; mine="$(block GroupA "$out")"
  check "[$sh] T1 when some app's entitlements cannot be read, no group container is taken and the reason says why" \
        "$([[ "$(paths_of "$mine")" != *"Group Containers"* && "$mine" == *"[LEFT]"*"TEAM.only.a"*"could not be read"* ]] && echo ok || echo "$mine")"
  rm -f "$W/ent/Broken.unreadable"; rm -rf "$W/apps/Broken.app"
  # an unsigned app: its group container named for it is shown as left, never taken
  mkapp Unsigned com.un.signed; mkdir -p "$G/group.com.un.signed" "$G/ABCDE12345.com.un.signed" "$G/group.com.un.signedother"
  out="$(run --stale-apps)"; mine="$(block Unsigned "$out")"
  check "[$sh] T9 an unsigned app's group.<id> and <team>.<id> containers are shown as left in place, and not taken" \
        "$([[ "$mine" == *"[LEFT]"*"group.com.un.signed"* && "$mine" == *"[LEFT]"*"ABCDE12345.com.un.signed"* && "$mine" == *"does not declare it"* && "$(paths_of "$mine")" != *"Group Containers"* && "$mine" != *"signedother"* ]] && echo ok || echo "$mine")"

  # ---------------------------------------------------------------- S1c: every way a bundle can sit under an app folder
  world s1c
  L="$W/home/Library"; G="$L/Group Containers"
  nested() { mkdir -p "$1/Contents"; printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>' "$2" > "$1/Contents/Info.plist"; }
  groups() { printf '%s' "$ENT_HEAD"; for g in "$@"; do printf '<string>%s</string>' "$g"; done; printf '%s' "$ENT_TAIL"; }
  mkapp GroupA com.g.a; groups TEAM.deep.group TEAM.only.a TEAM.appex.group TEAM.upper.group TEAM.nest2.group > "$W/ent/GroupA.xml"
  mkapp Host com.g.host; nested "$W/apps/Host.app/Contents/Frameworks/X.framework/Versions/A/Helpers/OtherVendor.app" com.g.other     # depth 8
  groups TEAM.deep.group > "$W/ent/OtherVendor.xml"
  mkapp Host2 com.g.host2; nested "$W/apps/Host2.app/Contents/Library/LoginItems/H.app" com.g.h
  nested "$W/apps/Host2.app/Contents/Library/LoginItems/H.app/Contents/Library/LoginItems/Inner.app" com.g.inner                        # an app inside an app inside an app
  groups TEAM.nest2.group > "$W/ent/Inner.xml"
  mkapp Host3 com.g.host3; nested "$W/apps/Host3.app/Contents/PlugIns/Ext.appex" com.g.ext; groups TEAM.appex.group > "$W/ent/Ext.xml"   # an app extension
  nested "$W/apps/Suite2/Shared.APP" com.g.upper; groups TEAM.upper.group > "$W/ent/Shared.xml"                                       # upper-case suffix
  for g in TEAM.deep.group TEAM.only.a TEAM.appex.group TEAM.upper.group TEAM.nest2.group; do mkdir -p "$G/$g"; printf x > "$G/$g/d"; done
  list_a() { run --list-app "$W/apps/GroupA.app"; }
  out="$(list_a)"; mine="$(block GroupA "$out")"
  for g in "TEAM.deep.group|a helper nine levels down in a framework" "TEAM.nest2.group|an app inside an app inside an app" "TEAM.appex.group|an app extension of another app" "TEAM.upper.group|a bundle named .APP"; do
    check "[$sh] U1 a group shared with ${g#*|} is left in place" "$([[ "$mine" == *"[LEFT]"*"${g%%|*}"*"another app shares"* && "$(paths_of "$mine")" != *"${g%%|*}"* ]] && echo ok || echo "$mine")"
  done
  check "[$sh] U1 the walk found everything, so a group nobody else declares is still the app's" "$([[ "$(paths_of "$mine")" == *"TEAM.only.a"* && "$out" != *"[CONTAINERS-KEPT]"* ]] && echo ok || echo "$mine")"

  # a linked folder inside an app folder is never followed: its presence makes "shared elsewhere" unknown
  world s1d
  L="$W/home/Library"; G="$L/Group Containers"
  mkapp GroupA com.g.a; groups TEAM.linked.group TEAM.only.a > "$W/ent/GroupA.xml"
  mkdir -p "$W/outside/Linked"; nested "$W/outside/Linked/GroupL.app" com.g.l; groups TEAM.linked.group > "$W/ent/GroupL.xml"
  ln -s "$W/outside/Linked" "$W/apps/LinkedSuite"
  for g in TEAM.linked.group TEAM.only.a; do mkdir -p "$G/$g"; printf x > "$G/$g/d"; done
  out="$(run --list-app "$W/apps/GroupA.app")"; mine="$(block GroupA "$out")"
  check "[$sh] U1 a linked suite folder: every group container is left in place, with the reason" \
        "$([[ "$(paths_of "$mine")" != *"Group Containers"* && "$mine" == *"[LEFT]"*"TEAM.linked.group"*"could not be read"* && "$mine" == *"[LEFT]"*"TEAM.only.a"* ]] && echo ok || echo "$mine")"
  check "[$sh] U1 and the run says once why, naming the link" "$([[ "$out" == *"[CONTAINERS-KEPT]"*"a link to a folder inside an app folder is not followed: $W/apps/LinkedSuite"* ]] && echo ok || echo "$out" | grep -i kept)"
  # a loop of links: a link back to its own parent is not followed (so it ends), and is a problem like any linked folder
  world s1e
  L="$W/home/Library"; G="$L/Group Containers"
  mkapp GroupA com.g.a; groups TEAM.only.a > "$W/ent/GroupA.xml"; mkdir -p "$W/apps/Suite" "$G/TEAM.only.a"; printf x > "$G/TEAM.only.a/d"
  ln -s .. "$W/apps/Suite/back"
  start=$SECONDS; out="$(run --list-app "$W/apps/GroupA.app")"; took=$((SECONDS - start))
  check "[$sh] U1 a link back to its own parent ends at once and keeps the containers" \
        "$([[ $took -lt 20 && "$out" == *"[CONTAINERS-KEPT]"*"Suite/back"* && "$(paths_of "$(block GroupA "$out")")" != *"Group Containers"* ]] && echo ok || echo "took ${took}s: $out" | tail -4)"
  # two links that point at each other point at nothing: not a folder, not a problem
  rm -rf "$W/apps/Suite"; ln -s "$W/apps/l2" "$W/apps/l1"; ln -s "$W/apps/l1" "$W/apps/l2"
  out="$(run --list-app "$W/apps/GroupA.app")"
  check "[$sh] U1 links that only point at each other are not folders: nothing is held back" "$([[ "$out" != *"[CONTAINERS-KEPT]"* && "$(paths_of "$(block GroupA "$out")")" == *"TEAM.only.a"* ]] && echo ok || echo "$out" | tail -5)"
  # an app folder that is itself a link is the folder the person named: it is walked
  world s1f
  L="$W/home/Library"; G="$L/Group Containers"
  mkapp GroupA com.g.a; groups TEAM.shared.group TEAM.only.a > "$W/ent/GroupA.xml"
  nested "$W/apps/Suite/GroupB.app" com.g.b; groups TEAM.shared.group > "$W/ent/GroupB.xml"
  ln -s "$W/apps" "$W/appslink"
  printf 'ANALYZERS_APP_DIRS="%s/appslink"\nANALYZERS_LAUNCH_DIRS="%s/launch"\nANALYZERS_LOGIN_INVENTORY="%s/inventory.tsv"\n' "$W" "$W" "$W" > "$W/tree/config.local.sh"
  for g in TEAM.shared.group TEAM.only.a; do mkdir -p "$G/$g"; printf x > "$G/$g/d"; done
  out="$(run --list-app "$W/appslink/GroupA.app")"; mine="$(block GroupA "$out")"
  check "[$sh] U1 an app folder that is a link is walked, and a group shared inside it is left" "$([[ "$mine" == *"[LEFT]"*"TEAM.shared.group"*"another app shares"* && "$(paths_of "$mine")" == *"TEAM.only.a"* ]] && echo ok || echo "$mine")"
  # a codesign that never answers: stopped at the limit, the app is unreadable, nothing is taken, and it is named
  world s1g
  L="$W/home/Library"; G="$L/Group Containers"
  mkapp GroupA com.g.a; groups TEAM.only.a > "$W/ent/GroupA.xml"; mkapp Hang com.g.hang; : > "$W/ent/Hang.hang"
  mkdir -p "$G/TEAM.only.a"; printf x > "$G/TEAM.only.a/d"
  start=$SECONDS; out="$(ANALYZERS_CODESIGN_LIMIT=2 run --list-app "$W/apps/GroupA.app")"; took=$((SECONDS - start))
  check "[$sh] U1 a codesign that hangs is stopped at the limit, the run finishes, and no container is taken" \
        "$([[ $took -lt 25 && "$(paths_of "$(block GroupA "$out")")" != *"Group Containers"* && "$(block GroupA "$out")" == *"[LEFT]"*"TEAM.only.a"* ]] && echo ok || echo "took ${took}s: $(block GroupA "$out")")"
  check "[$sh] U4 and the run says once which app could not be read" "$([[ "$out" == *"[CONTAINERS-KEPT]"*"the settings of Hang.app could not be read"* ]] && echo ok || echo "$out" | grep -i kept)"
  [[ -f "$W/hang.pids" ]] && while read -r hp; do kill "$hp" 2>/dev/null; done < "$W/hang.pids"     # only the stand-ins this test started

  # a read whose job dies leaves no result file: the index notices and is not trusted
  world s1h
  L="$W/home/Library"; G="$L/Group Containers"
  mkapp GroupA com.g.a; groups TEAM.only.a > "$W/ent/GroupA.xml"; mkapp Die com.g.die; : > "$W/ent/Die.die"
  mkdir -p "$G/TEAM.only.a"; printf x > "$G/TEAM.only.a/d"
  out="$(run --list-app "$W/apps/GroupA.app")"
  check "[$sh] U4 an index with a read that never finished is not trusted: no container is taken, and the run says so" \
        "$([[ "$(paths_of "$(block GroupA "$out")")" != *"Group Containers"* && "$out" == *"[CONTAINERS-KEPT]"* ]] && echo ok || echo "$out" | tail -5)"

  # ---------------------------------------------------------------- S1i: every kind of bundle that can declare a group (V1)
  world s1i
  L="$W/home/Library"; G="$L/Group Containers"
  mkapp GroupA com.g.a; groups TEAM.xpc.group TEAM.deepxpc.group TEAM.sysext.group TEAM.dext.group TEAM.only.a > "$W/ent/GroupA.xml"
  mkapp Host com.g.host; nested "$W/apps/Host.app/Contents/XPCServices/Svc.xpc" com.g.svc; groups TEAM.xpc.group > "$W/ent/Svc.xml"
  nested "$W/apps/Host.app/Contents/Frameworks/Y.framework/Versions/A/XPCServices/Deep.xpc" com.g.deep; groups TEAM.deepxpc.group > "$W/ent/Deep.xml"
  nested "$W/apps/Host.app/Contents/Library/SystemExtensions/Ext.systemextension" com.g.ext; groups TEAM.sysext.group > "$W/ent/Ext.xml"
  nested "$W/apps/Host.app/Contents/Library/SystemExtensions/Drv.dext" com.g.drv; groups TEAM.dext.group > "$W/ent/Drv.xml"
  for g in TEAM.xpc.group TEAM.deepxpc.group TEAM.sysext.group TEAM.dext.group TEAM.only.a; do mkdir -p "$G/$g"; printf x > "$G/$g/d"; done
  out="$(run --list-app "$W/apps/GroupA.app")"; mine="$(block GroupA "$out")"
  for g in "TEAM.xpc.group|an XPC service in another app" "TEAM.deepxpc.group|an XPC service deep inside a framework" "TEAM.sysext.group|a system extension of another app" "TEAM.dext.group|a driver extension of another app"; do
    check "[$sh] V1 a group shared with ${g#*|} is left in place" "$([[ "$mine" == *"[LEFT]"*"${g%%|*}"*"another app shares"* && "$(paths_of "$mine")" != *"${g%%|*}"* ]] && echo ok || echo "$mine")"
  done
  check "[$sh] V1 nothing was missed, so a group nobody else declares is still the app's" "$([[ "$(paths_of "$mine")" == *"TEAM.only.a"* && "$out" != *"[CONTAINERS-KEPT]"* ]] && echo ok || echo "$mine")"
  # a folder that only looks like a bundle (Xcode's SDKs hold .xpc stubs with no executable) holds no code: it is not "unreadable"
  nested "$W/apps/Host.app/Contents/XPCServices/Stub.xpc" com.g.stub; : > "$W/ent/Stub.stub"
  out="$(run --list-app "$W/apps/GroupA.app")"
  check "[$sh] V1 a stub that only looks like a bundle does not switch container removal off" "$([[ "$out" != *"[CONTAINERS-KEPT]"* && "$(paths_of "$(block GroupA "$out")")" == *"TEAM.only.a"* ]] && echo ok || echo "$out" | tail -4)"
  # an XPC service does not own an app's name
  mkdir -p "$L/Application Support/GroupA"; printf x > "$L/Application Support/GroupA/d"
  nested "$W/apps/Host.app/Contents/XPCServices/GroupA.xpc" com.g.namesake
  out="$(run --stale-apps)"          # reviewed (the name check only applies then)
  check "[$sh] V1 a folder named for the app is still taken when the only other thing with that name is an XPC service" "$([[ "$(paths_of "$(block GroupA "$out")")" == *"Application Support/GroupA"* ]] && echo ok || echo "$(block GroupA "$out")")"

  # a configured app folder that is not there: the apps on it cannot be seen, so sharing is unknown
  world s1j
  L="$W/home/Library"; G="$L/Group Containers"
  mkapp GroupA com.g.a; groups TEAM.only.a > "$W/ent/GroupA.xml"; mkdir -p "$G/TEAM.only.a"; printf x > "$G/TEAM.only.a/d"
  printf 'ANALYZERS_APP_DIRS="%s/apps:%s/unplugged-disk/Applications"\nANALYZERS_LAUNCH_DIRS="%s/launch"\nANALYZERS_LOGIN_INVENTORY="%s/inventory.tsv"\n' "$W" "$W" "$W" "$W" > "$W/tree/config.local.sh"
  out="$(run --list-app "$W/apps/GroupA.app")"; mine="$(block GroupA "$out")"
  check "[$sh] V1 an app folder that is configured but not there: no container is taken, and the run names the folder" \
        "$([[ "$(paths_of "$mine")" != *"Group Containers"* && "$out" == *"[CONTAINERS-KEPT]"*"an app folder that is configured is not there: $W/unplugged-disk/Applications"* ]] && echo ok || echo "$out" | tail -5)"
  mkdir -p "$W/unplugged-disk/Applications"
  out="$(run --list-app "$W/apps/GroupA.app")"
  check "[$sh] V1 and once the folder is there, the container is taken again" "$([[ "$(paths_of "$(block GroupA "$out")")" == *"TEAM.only.a"* && "$out" != *"[CONTAINERS-KEPT]"* ]] && echo ok || echo "$out" | tail -4)"

  # ---------------------------------------------------------------- S2: an app that cannot be moved
  world s2; EXTRA_CONFIG=""
  mkdir -p "$W/locked"; mkapp VendorApp com.vendor.app          # a normal app so the install folder is not empty
  mkdir -p "$W/locked/Locked.app/Contents"
  printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.locked.app</string></dict></plist>' > "$W/locked/Locked.app/Contents/Info.plist"
  mkdir -p "$W/home/Library/Application Support/com.locked.app"; printf x > "$W/home/Library/Application Support/com.locked.app/data"
  chmod 555 "$W/locked"
  printf 'ANALYZERS_STALE_APPS=( "%s/locked/Locked.app" )\nANALYZERS_LOGIN_INVENTORY="%s/inventory.tsv"\nANALYZERS_LAUNCH_DIRS="%s/launch"\n' "$W" "$W" "$W" > "$W/tree/config.local.sh"
  out="$(run --stale-apps)"
  check "[$sh] S2 reviewed, an app in a folder the person cannot change is kept, not offered" \
        "$([[ "$(block Locked "$out")" == *"[KEEP]"*"Installed for all users"* ]] && echo ok || echo "$(block Locked "$out")")"
  out="$(run --stale-apps --execute --yes)"
  check "[$sh] S2 when the app cannot be moved, the run says why" "$([[ "$out" == *"[FAILED]"*"Locked.app"*"administrator"* ]] && echo ok || echo "$out" | grep -i fail)"
  check "[$sh] S2 and its settings and data are NOT touched (the app stays installed with them)" \
        "$([[ -d "$W/locked/Locked.app" && -e "$W/home/Library/Application Support/com.locked.app/data" ]] && ! in_trash com.locked.app && echo ok || echo "settings were moved")"
  chmod -R u+w "$W/locked"

  # ---------------------------------------------------------------- S3: a generic name does not own a folder
  world s3
  mkapp Electron com.someone.electronshell; mkapp "Electron Fiddle" com.someone.fiddle; mkapp Slack com.tinyspeck.slack; mkapp Python org.python.shell
  L="$W/home/Library/Application Support"; mkdir -p "$L/Electron" "$L/Slack" "$L/Python"; printf x > "$L/Electron/d"; printf x > "$L/Slack/d"; printf x > "$L/Python/d"
  out="$(run --stale-apps)"
  check "[$sh] S3 a folder named like the app is left in place when another app could own the name (Electron)" \
        "$([[ "$(block Electron "$out")" == *"[LEFT]"*"Application Support/Electron"*"another program may use"* && "$(paths_of "$(block Electron "$out")")" != *"Application Support/Electron"* ]] && echo ok || echo "$(block Electron "$out")")"
  check "[$sh] S3 a runtime name (Python) is left in place even when only one app carries it" \
        "$([[ "$(paths_of "$(block Python "$out")")" != *"Application Support/Python"* && "$(block Python "$out")" == *"[LEFT]"* ]] && echo ok || echo "taken")"
  check "[$sh] S3 a name only one app could own (Slack) is taken with the app" \
        "$([[ "$(paths_of "$(block Slack "$out")")" == *"Application Support/Slack"* ]] && echo ok || echo "not taken")"
  paths_of "$(block Electron "$out")" > "$W/list"; printf '%s\n' "$W/apps/Electron.app" >> "$W/list"
  run --stale-apps --execute --yes --only-paths "$W/list" >/dev/null
  check "[$sh] S3 applying removes the app but not the shared-name folder" "$([[ -d "$L/Electron" ]] && in_trash Electron.app && echo ok || echo "wrong")"

  # ---------------------------------------------------------------- S4a: an app started through something else
  world s4a
  agent() { printf '<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array>%s</array></dict></plist>' "$1" "$2" > "$W/launch/$1.plist"; }
  mkapp Opener com.test.opener; mkapp OpenerB com.test.openerb; mkapp OpenerName com.test.openername; mkapp Scripted com.test.scripted
  mkapp Wrapped com.test.wrapped; mkapp Unrelated com.test.unrelated; mkapp Quiet com.test.quiet
  agent org.a '<string>/usr/bin/open</string><string>-a</string><string>'"$W"'/apps/Opener.app</string>'
  agent org.b '<string>/usr/bin/open</string><string>-b</string><string>com.test.openerb</string>'
  agent org.c '<string>/usr/bin/open</string><string>-a</string><string>OpenerName</string>'
  agent org.d '<string>/usr/bin/osascript</string><string>-e</string><string>tell application "Scripted" to activate</string>'
  printf '#!/bin/bash\nopen -a "Wrapped"\n' > "$W/wrap.sh"; chmod +x "$W/wrap.sh"
  agent org.e '<string>/bin/bash</string><string>'"$W"'/wrap.sh</string>'
  agent org.f '<string>/usr/bin/true</string>'
  # T3: forms that used to slip past
  mkapp OpNa com.test.opna; mkapp OpGa com.test.opga; mkapp opcase com.test.opcase; mkapp OpApp com.test.opapp; mkapp OpShC com.test.opshc
  mkapp OpMany com.test.opmany; mkapp OpDoc com.test.opdoc '<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeExtensions</key><array><string>opdoc</string></array></dict></array><key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>opscheme</string></array></dict></array>'
  mkapp OpScheme com.test.opscheme '<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>opsch2</string></array></dict></array>'
  mkapp OpOther com.test.opother '<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeExtensions</key><array><string>opother</string></array></dict></array>'
  mkapp OpClust com.test.opclust; mkapp OpEnvB com.test.openvb
  agent org.na '<string>/usr/bin/open</string><string>-na</string><string>OpNa</string>'
  agent org.ga '<string>/usr/bin/open</string><string>-ga</string><string>OpGa</string>'
  agent org.cl '<string>/usr/bin/open</string><string>-Fgj</string><string>-a</string><string>OpClust</string>'
  agent org.case '<string>/usr/bin/open</string><string>-a</string><string>OPCASE</string>'
  agent org.tellapp '<string>/usr/bin/osascript</string><string>-e</string><string>tell app "OpApp" to launch</string>'
  agent org.doc '<string>/usr/bin/open</string><string>/Users/x/docs/start.opdoc</string>'
  agent org.scheme '<string>/usr/bin/open</string><string>opsch2://go</string>'
  agent org.shc '<string>/bin/sh</string><string>-c</string><string>sleep 5; open -a OpShC</string>'
  agent org.envb '<string>/usr/bin/env</string><string>A=1</string><string>-i</string><string>/usr/bin/open</string><string>--bundle-identifier</string><string>COM.test.openvb</string>'
  many=""; for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do many="$many<string>V$n=$n</string>"; done
  agent org.many '<string>/usr/bin/env</string>'"$many"'<string>/usr/bin/open</string><string>-a</string><string>OpMany</string>'
  # not the app's: another app is named, so a document it owns is not a sign this one runs
  agent org.other '<string>/usr/bin/open</string><string>-a</string><string>TextEdit</string><string>/x/start.opother</string>'
  out="$(run --stale-apps)"
  for pair in "OpNa|open -na (a new instance)" "OpGa|open -ga (combined flags)" "OpClust|open -Fgj -a (several flag letters)" "opcase|open -a with the name in another case" \
              "OpApp|osascript tell app (the short form)" "OpDoc|open of a document the app owns" "OpScheme|open of a URL scheme the app handles" \
              "OpShC|sh -c with open -a inside" "OpEnvB|open --bundle-identifier behind env, in another case" "OpMany|open -a after eighteen other arguments"; do
    n="${pair%%|*}"
    check "[$sh] T3 $n is kept: started at login through ${pair#*|}" "$([[ "$(block "$n" "$out")" == *"[KEEP]"*"launch entry"* ]] && echo ok || echo "offered")"
  done
  check "[$sh] T3 an app whose document type is only opened by ANOTHER named app (open -a TextEdit x.opother) is still offered" \
        "$([[ "$(block OpOther "$out")" != *"[KEEP]"* ]] && echo ok || echo kept)"
  for pair in "Opener|open -a with the app's path" "OpenerB|open -b with its bundle id" "OpenerName|open -a with its name" "Scripted|osascript tell application" "Wrapped|a shell wrapper that opens it"; do
    n="${pair%%|*}"
    check "[$sh] S4a $n is kept: started at login through ${pair#*|}" "$([[ "$(block "$n" "$out")" == *"[KEEP]"*"launch entry"* ]] && echo ok || echo "$(block "$n" "$out" | grep -c KEEP) kept")"
  done
  check "[$sh] S4a an app no launch entry names is still offered (Unrelated, Quiet)" \
        "$([[ "$(block Unrelated "$out")" != *"[KEEP]"* && "$(block Quiet "$out")" != *"[KEEP]"* ]] && echo ok || echo "kept")"

  # ---------------------------------------------------------------- S4c: configured apps get the same checks when reviewed
  world s4c
  mkapp Configured com.test.configured; mkdir -p "$W/apps/Configured.app/Contents/Library/LoginItems/Helper.app"
  mkapp Busy com.test.busy
  printf 'ANALYZERS_STALE_APPS=( "%s/apps/Configured.app" "%s/apps/Busy.app" )\nANALYZERS_LOGIN_INVENTORY="%s/inventory.tsv"\nANALYZERS_LAUNCH_DIRS="%s/launch"\nANALYZERS_APP_DIRS="%s/apps"\n' "$W" "$W" "$W" "$W" "$W" > "$W/tree/config.local.sh"
  printf '#!/bin/bash\n[[ "$*" == *Busy* ]] && exit 0\nexit 1\n' > "$S/pgrep"; chmod +x "$S/pgrep"
  out="$(run --stale-apps)"
  check "[$sh] S4c a configured app with a login item is shown as kept when the app reviews it" "$([[ "$(block Configured "$out")" == *"[KEEP]"*"background"* ]] && echo ok || echo "not kept")"
  check "[$sh] S4c a configured app that is running is shown as running" "$([[ "$(block Busy "$out")" == *"appears to be RUNNING"* ]] && echo ok || echo "not shown")"
  printf '%s\n%s\n' "$W/apps/Configured.app" "$W/apps/Busy.app" > "$W/list"
  run --stale-apps --execute --yes --only-paths "$W/list" >/dev/null
  check "[$sh] S4c a reviewed list naming them removes neither" "$([[ -d "$W/apps/Configured.app" && -d "$W/apps/Busy.app" ]] && echo ok || echo "removed")"
  run --app "$W/apps/Configured.app" --execute --yes >/dev/null
  check "[$sh] S4c from Terminal, --app still removes it, as before" "$([[ ! -e "$W/apps/Configured.app" ]] && in_trash Configured.app && echo ok || echo "not removed")"

  # ---------------------------------------------------------------- S4d: apps inside apps (U7)
  world s4d
  nested() { mkdir -p "$1/Contents"; printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string>%s</dict></plist>' "$2" "${3:-}" > "$1/Contents/Info.plist"; }
  agent() { printf '<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array>%s</array></dict></plist>' "$1" "$2" > "$W/launch/$1.plist"; }
  for n in Quiet1 Quiet2 Quiet3; do mkapp $n com.q.$n; done
  for n in Sparkle1 Sparkle2 Sparkle3 Sparkle4; do                       # an updater the app starts when it needs it
    mkapp $n com.s.$n; nested "$W/apps/$n.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" com.s.$n.updater '<key>LSUIElement</key><true/>'
  done
  for n in LoginHelper1 LoginHelper2; do mkapp $n com.l.$n; nested "$W/apps/$n.app/Contents/Library/LoginItems/Helper.app" com.l.$n.helper; done
  mkapp SuiteRunning com.u.run; nested "$W/apps/SuiteRunning.app/Contents/Applications/RunningTool.app" com.u.runtool
  mkapp SuiteRecent com.u.recent; nested "$W/apps/SuiteRecent.app/Contents/Applications/RecentNested.app" com.u.recenttool
  mkapp SuiteAgent com.u.agent; nested "$W/apps/SuiteAgent.app/Contents/Applications/AgentTool.app" com.u.agenttool
  mkapp SuiteDeep com.u.deep; nested "$W/apps/SuiteDeep.app/Contents/Applications/Middle.app" com.u.mid
  nested "$W/apps/SuiteDeep.app/Contents/Applications/Middle.app/Contents/Applications/DeepTool.app" com.u.deeptool
  agent org.agent '<string>/usr/bin/open</string><string>-a</string><string>AgentTool</string>'      # by name: only the nested app is named
  agent org.deep '<string>/usr/bin/open</string><string>-a</string><string>DeepTool</string>'
  printf '#!/bin/bash\n[[ "$*" == *RunningTool* ]] && exit 0\nexit 1\n' > "$S/pgrep"; chmod +x "$S/pgrep"
  out="$(run --stale-apps)"
  offered=0; kept=0; total=0
  for n in Quiet1 Quiet2 Quiet3 Sparkle1 Sparkle2 Sparkle3 Sparkle4 LoginHelper1 LoginHelper2 SuiteRunning SuiteRecent SuiteAgent SuiteDeep; do
    total=$((total + 1)); if [[ "$(block "$n" "$out")" == *"[KEEP]"* ]]; then kept=$((kept + 1)); else offered=$((offered + 1)); fi
  done
  check "[$sh] U7 apps whose only nested app is an updater are offered, not kept (Sparkle1 to 4)" \
        "$([[ "$(block Sparkle1 "$out")" != *"[KEEP]"* && "$(block Sparkle4 "$out")" != *"[KEEP]"* ]] && echo ok || block Sparkle1 "$out")"
  check "[$sh] U7 and the row says what goes with the app" "$([[ "$(block Sparkle2 "$out")" == *"contains: 1 other app(s) inside it, removed with it: Updater.app"* ]] && echo ok || block Sparkle2 "$out")"
  check "[$sh] U7 an app holding an app that is running is kept, and says which" "$([[ "$(block SuiteRunning "$out")" == *"[KEEP]"*"An app inside it is in use on its own: RunningTool"* ]] && echo ok || block SuiteRunning "$out")"
  check "[$sh] U7 an app holding an app opened within the window is kept" "$([[ "$(block SuiteRecent "$out")" == *"[KEEP]"*"RecentNested"* ]] && echo ok || block SuiteRecent "$out")"
  check "[$sh] U7 an app holding an app a launch entry starts is kept" "$([[ "$(block SuiteAgent "$out")" == *"[KEEP]"*"An app inside it is in use on its own: AgentTool"* ]] && echo ok || block SuiteAgent "$out")"
  check "[$sh] U7 an app holding an app that holds an app a launch entry starts is kept" "$([[ "$(block SuiteDeep "$out")" == *"[KEEP]"*"An app inside it is in use on its own: Middle"* ]] && echo ok || block SuiteDeep "$out")"
  check "[$sh] U7 an app with a login-item helper registered inside is still kept" "$([[ "$(block LoginHelper1 "$out")" == *"[KEEP]"*"registers a login item"* ]] && echo ok || block LoginHelper1 "$out")"
  check "[$sh] U7 of $total apps $offered are offered and $kept kept (with the updater rule: 7 and 6)" "$([[ $offered -eq 7 && $kept -eq 6 ]] && echo ok || echo "$offered/$kept")"
  mv "$S/pgrep" "$S/pgrep.off"; printf '#!/bin/bash\nexit 1\n' > "$S/pgrep"; chmod +x "$S/pgrep"

  # V3: every level is counted, and what belongs to the apps inside stays
  world s4e
  nested() { mkdir -p "$1/Contents"; printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>' "$2" > "$1/Contents/Info.plist"; }
  mkapp SuiteTwo com.suite.two
  nested "$W/apps/SuiteTwo.app/Contents/Applications/Middle.app" com.suite.mid
  nested "$W/apps/SuiteTwo.app/Contents/Applications/Middle.app/Contents/Applications/Deepest.app" com.suite.inner
  mkdir -p "$W/home/Library/Application Support/com.suite.inner" "$W/home/Library/Application Support/com.suite.two"; printf x > "$W/home/Library/Application Support/com.suite.inner/d"; printf x > "$W/home/Library/Application Support/com.suite.two/d"
  out="$(run --stale-apps)"
  check "[$sh] V3 the contains line counts every level and says the inner apps' own files stay" \
        "$([[ "$(block SuiteTwo "$out")" == *"contains: 2 other app(s) inside it, removed with it: Middle.app; Deepest.app (their own settings and data are left in place)"* ]] && echo ok || block SuiteTwo "$out")"
  paths_of "$(block SuiteTwo "$out")" > "$W/list"
  run --stale-apps --execute --yes --only-paths "$W/list" > /dev/null
  check "[$sh] V3 the suite and its own data go; the inner app's own Application Support stays where it was" \
        "$([[ ! -e "$W/apps/SuiteTwo.app" && ! -e "$W/home/Library/Application Support/com.suite.two" && -e "$W/home/Library/Application Support/com.suite.inner/d" ]] && in_trash SuiteTwo.app && echo ok || echo "wrong")"

  # ---------------------------------------------------------------- S4f: "running" is read from the real process table, not from another run's pgrep
  world s4f
  rm -f "$S/pgrep"                                              # the real pgrep, on purpose
  mkapp Runner com.r.runner; mkapp Idle com.r.idle
  # The stand-in program is a script of our own. A COPY of a system binary (/bin/sleep) inside a bundle is killed by
  # macOS at launch ("Launch Constraint Violation") and shows the person a "damaged app" dialog: never do that.
  mkdir -p "$W/apps/Runner.app/Contents/MacOS"
  # (no exec: the running process must keep the bundle's path in its command line, as a real app's does)
  printf '#!/bin/sh\nn=0; while [ "$n" -lt "${1:-60}" ]; do /bin/sleep 1; n=$((n+1)); done\n' >"$W/apps/Runner.app/Contents/MacOS/Runner"; chmod +x "$W/apps/Runner.app/Contents/MacOS/Runner"
  "$W/apps/Runner.app/Contents/MacOS/Runner" 60 & runner=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do      # until the process table shows it (a loaded Mac is slow)
    [[ "$(ps -o command= -p "$runner" 2>/dev/null)" == *"/Runner.app/Contents/MacOS/Runner"* ]] && break; sleep 0.2
  done
  out="$(run --stale-apps)"
  check "[$sh] V5 an app whose program is running is seen as running (real pgrep)" "$([[ "$(block Runner "$out")" == *"appears to be RUNNING"* ]] && echo ok || block Runner "$out")"
  check "[$sh] V5 and an app that is not running is not" "$([[ "$(block Idle "$out")" != *"appears to be RUNNING"* ]] && echo ok || block Idle "$out")"
  kill "$runner" 2>/dev/null; wait "$runner" 2>/dev/null
  # a program that runs THROUGH an interpreter has the interpreter first on its command line: still running (scripts of our
  # own, never a copy of a system binary)
  mkapp RunnerSh com.r.runnersh; mkapp RunnerEnv com.r.runnerenv
  for n in RunnerSh RunnerEnv; do
    mkdir -p "$W/apps/$n.app/Contents/MacOS"
    printf '#!/bin/sh\nn=0; while [ "$n" -lt 60 ]; do /bin/sleep 1; n=$((n+1)); done\n' > "$W/apps/$n.app/Contents/MacOS/$n"; chmod +x "$W/apps/$n.app/Contents/MacOS/$n"
  done
  /bin/sh "$W/apps/RunnerSh.app/Contents/MacOS/RunnerSh" & via_sh=$!
  /usr/bin/env sh "$W/apps/RunnerEnv.app/Contents/MacOS/RunnerEnv" & via_env=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    [[ "$(ps -o command= -p "$via_sh" 2>/dev/null)" == *"RunnerSh.app/Contents/MacOS/RunnerSh"* && "$(ps -ax -o command= | grep -c "[R]unnerEnv.app/Contents/MacOS/RunnerEnv")" -ge 1 ]] && break; sleep 0.2
  done
  out="$(run --stale-apps)"
  check "[$sh] V5 a program run as /bin/sh <path> is seen as running" "$([[ "$(block RunnerSh "$out")" == *"appears to be RUNNING"* ]] && echo ok || block RunnerSh "$out")"
  check "[$sh] V5 a program run as /usr/bin/env sh <path> is seen as running" "$([[ "$(block RunnerEnv "$out")" == *"appears to be RUNNING"* ]] && echo ok || block RunnerEnv "$out")"
  kill "$via_sh" "$via_env" 2>/dev/null; wait "$via_sh" "$via_env" 2>/dev/null
  # many runs at once: each run's own pgrep holds the pattern text in its command line, and must not make an idle app look running
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do ( run --list-app "$W/apps/Idle.app" > "$W/conc$n" ) & done; wait
  seen=0; for n in 1 2 3 4 5 6 7 8 9 10 11 12; do grep -q "appears to be RUNNING" "$W/conc$n" && seen=$((seen + 1)); done
  check "[$sh] V5 twelve runs at once: none sees another run's pgrep as the app running" "$([[ $seen -eq 0 ]] && echo ok || echo "$seen of 12 saw it")"

  # ---------------------------------------------------------------- S4b: login items need a recent inventory
  world s4b
  mkapp Plain com.test.plain
  rm -f "$W/inventory.tsv"
  out="$(run --stale-apps)"
  check "[$sh] S4b with no audit inventory, no app is offered: each says to run Login & Startup Items first" \
        "$([[ "$(block Plain "$out")" == *"[KEEP]"*"Login & Startup Items first"* ]] && echo ok || echo "$(block Plain "$out")")"
  inventory "$W/inventory.tsv" 2 "2020-01-01 00:00:00"
  out="$(run --stale-apps)"
  check "[$sh] S4b an inventory whose HEADER says it ran long ago counts as none" "$([[ "$(block Plain "$out")" == *"[KEEP]"*"Login & Startup Items first"* ]] && echo ok || echo "$(block Plain "$out")")"
  inventory "$W/inventory.tsv" 2 "2020-01-01 00:00:00"; touch "$W/inventory.tsv"
  out="$(run --stale-apps)"
  check "[$sh] S4b the file's own (new) time does not make an old header fresh" "$([[ "$(block Plain "$out")" == *"[KEEP]"* ]] && echo ok || echo "offered")"
  inventory "$W/inventory.tsv"
  out="$(run --stale-apps)"
  check "[$sh] S4b with a fresh inventory the same app is offered" "$([[ "$(block Plain "$out")" != *"[KEEP]"* ]] && echo ok || echo "$(block Plain "$out")")"
  # T2: an inventory that is not one, or cannot be trusted, counts as none
  : > "$W/inventory.tsv"
  out="$(run --stale-apps)"; check "[$sh] T2 an empty inventory file counts as none" "$([[ "$(block Plain "$out")" == *"[KEEP]"*"Login & Startup Items first"* ]] && echo ok || echo offered)"
  printf 'garbage\n' > "$W/inventory.tsv"
  out="$(run --stale-apps)"; check "[$sh] T2 a file that is not an inventory counts as none" "$([[ "$(block Plain "$out")" == *"[KEEP]"*"Login & Startup Items first"* ]] && echo ok || echo offered)"
  inventory "$W/inventory.tsv" 2 "2030-01-01 00:00:00"
  out="$(run --stale-apps)"; check "[$sh] T2 an inventory dated in the future counts as none" "$([[ "$(block Plain "$out")" == *"[KEEP]"*"Login & Startup Items first"* ]] && echo ok || echo offered)"
  printf '#login-items-inventory\t1\t%s\tdry-run\tid\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$W/inventory.tsv"
  out="$(run --stale-apps)"; check "[$sh] T2 an inventory of an unknown (older) version counts as none" "$([[ "$(block Plain "$out")" == *"[KEEP]"*"Login & Startup Items first"* ]] && echo ok || echo offered)"
  inventory "$W/inventory.tsv" 2 "not a date"
  out="$(run --stale-apps)"; check "[$sh] T2 a header date that cannot be read counts as none" "$([[ "$(block Plain "$out")" == *"[KEEP]"*"Login & Startup Items first"* ]] && echo ok || echo offered)"
  inventory "$W/inventory.tsv" 2 "$(date '+%Y-%m-%d %H:%M:%S')" "logins=unreadable"
  out="$(run --stale-apps)"
  check "[$sh] T2 an inventory from a run that could not read the login items: kept, and the reason says why and what to do" \
        "$([[ "$(block Plain "$out")" == *"[KEEP]"*"could not read your Login Items"*"from the Mac Analyzers app"* ]] && echo ok || echo "$(block Plain "$out")")"
  printf '#login-items-inventory\t2\t%s\tdry-run\tid\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$W/inventory.tsv"
  out="$(run --stale-apps)"; check "[$sh] T2 a header with no statement about the login items is not trusted either" "$([[ "$(block Plain "$out")" == *"[KEEP]"* ]] && echo ok || echo offered)"

  # ---------------------------------------------------------------- S6: recordings
  world s6
  mkdir -p "$W/home/Rec/Old" "$W/home/Rec/Busy/sub"; printf x > "$W/home/Rec/Old/clip"; printf x > "$W/home/Rec/Busy/sub/new.mov"
  find "$W/home/Rec/Old" "$W/home/Rec/Busy" -not -name new.mov -exec touch -t 202001010000 {} +
  printf 'ANALYZERS_RECORDINGS_DIR="%s/home/Rec"\n' "$W" > "$W/tree/config.local.sh"
  out="$(run --recordings-older-than 30)"
  check "[$sh] S6 a folder is old by its newest file: a busy folder whose new recording is one level down is not listed" \
        "$([[ "$out" == *"/Rec/Old"* && "$out" != *"/Rec/Busy"* ]] && echo ok || echo "$out" | grep Rec)"
  # T5: a part of a folder that cannot be searched means it cannot be told whether something in it is new
  mkdir -p "$W/home/Rec/Unreadable/inner"; printf x > "$W/home/Rec/Unreadable/inner/new.mov"
  find "$W/home/Rec/Unreadable" -exec touch -t 202001010000 {} +; chmod 000 "$W/home/Rec/Unreadable/inner"
  out="$(run --recordings-older-than 30)"
  check "[$sh] T5 a recording folder with an unreadable subfolder is kept, with the reason, not offered" \
        "$([[ "$out" == *"[KEEP]"*"Rec/Unreadable"*"could not be read"* && "$out" != *"[DRY]"*"Rec/Unreadable"* ]] && echo ok || echo "$out" | grep Unreadable)"
  chmod 755 "$W/home/Rec/Unreadable/inner"
  check "[$sh] T5 the preview's last line says recordings go to the Trash, not that they are deleted" \
        "$([[ "$out" == *"to move them to the Trash"* && "$out" != *"--execute to delete"* ]] && echo ok || echo "$out" | tail -3)"
  # another disk: stand-in stat/df make the recordings folder a different volume with its own Trash
  world s6b
  mkdir -p "$W/extvol/Rec/Old" "$W/extvol/.Trashes/$(id -u)"; printf x > "$W/extvol/Rec/Old/clip"; find "$W/extvol/Rec" -exec touch -t 202001010000 {} +
  printf 'ANALYZERS_RECORDINGS_DIR="%s/extvol/Rec"\n' "$W" > "$W/tree/config.local.sh"
  printf '#!/bin/bash\nif [[ "$1" == "-f" && "$2" == "%%d" && "$3" == *"/extvol"* ]]; then echo 4242; exit 0; fi\nexec /usr/bin/stat "$@"\n' > "$S/stat"
  printf '#!/bin/bash\nprintf "Filesystem 512-blocks Used Available Capacity Mounted on\\n/dev/x 1 1 1 1%%%% %s/extvol\\n"\n' "$W" > "$S/df"
  chmod +x "$S/stat" "$S/df"
  printf '%s\n' "$W/extvol/Rec/Old" > "$W/list"
  out="$(run --recordings-older-than 30 --execute --yes --only-paths "$W/list")"
  check "[$sh] S6 a recording on another disk goes to THAT disk's Trash, with a receipt" \
        "$([[ -d "$W/extvol/.Trashes/$(id -u)/Old" && ! -e "$W/home/.Trash/Old" && "$out" == *"->  $W/extvol/.Trashes/$(id -u)/Old  #id="* ]] && echo ok || echo "$out" | grep -i "trash\|fail")"
  rm -rf "$W/extvol/.Trashes"; mkdir -p "$W/extvol/Rec/Old2"; printf x > "$W/extvol/Rec/Old2/clip"; find "$W/extvol/Rec/Old2" -exec touch -t 202001010000 {} +
  chmod 555 "$W/extvol"
  out="$(run --recordings-older-than 30)"
  check "[$sh] S6 a disk with no Trash (and none can be made) keeps the recording, with the reason" \
        "$([[ "$out" == *"[KEEP]"*"Old2"*"no Trash"* ]] && echo ok || echo "$out" | grep -i "Old2")"
  chmod -R u+w "$W/extvol"
done
exit $fail
