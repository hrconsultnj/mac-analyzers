#!/usr/bin/env bash
# cleanup-only-paths-test.sh — cleanup.sh's app and recordings runs take a reviewed list
# (`--only-paths FILE`): only items whose exact path is a whole line of the file are touched; the
# script still finds everything itself; an empty list touches nothing; a missing list file or a missing
# lib/approved-list.sh stops the run (exit 78) before anything is touched. Runs in a throwaway HOME
# with fixture apps and recording folders the test makes itself; `--execute` is only ever run on those.
# Under `bash` and /bin/bash (3.2).
#
# Usage: tests/cleanup-only-paths-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../storage-analyzer/cleanup.sh"
[[ -f "$SCRIPT" ]] || { echo "SKIP: script not found"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }

make_tree() { # dir: a copy of the script that cannot reach the person's config
  mkdir -p "$1/storage-analyzer" "$1/lib"
  cp "$SCRIPT" "$1/storage-analyzer/cleanup.sh"
  cp "$HERE"/../lib/*.sh "$1/lib/"
}
make_home() { # dir: two fixture apps with a footprint each, two old recording folders
  local h="$1" n
  mkdir -p "$h/Applications" "$h/Library/Application Support" "$h/Recordings"
  for n in FixtureOne FixtureTwo; do
    mkdir -p "$h/Applications/$n.app/Contents" "$h/Library/Application Support/$n"
    printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.%s</string></dict></plist>' "$n" \
      > "$h/Applications/$n.app/Contents/Info.plist"
    printf 'x' > "$h/Library/Application Support/$n/data"
    mkdir -p "$h/Recordings/Old$n"; printf 'r' > "$h/Recordings/Old$n/clip.mov"
  done
  find "$h/Recordings" -exec touch -t 202001010000 {} +
}
write_config() { # tree home
  printf '#login-items-inventory\t2\t%s\tdry-run\tid\tlogins=read\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$2/inventory.tsv"      # the audit ran today
  printf 'ANALYZERS_STALE_APPS=( "%s/Applications/FixtureOne.app" "%s/Applications/FixtureTwo.app" )\nANALYZERS_RECORDINGS_DIR="%s/Recordings"\nANALYZERS_LOGIN_INVENTORY="%s/inventory.tsv"\n' "$2" "$2" "$2" "$2" > "$1/config.local.sh"
}

for sh in bash /bin/bash; do
  k="$(echo "$sh" | tr / _)"
  tree="$TMP/tree-$k"; home="$TMP/home-$k"
  make_tree "$tree"; make_home "$home"; write_config "$tree" "$home"
  one="$home/Applications/FixtureOne.app"; two="$home/Applications/FixtureTwo.app"
  cleanup() { HOME="$home" "$sh" "$tree/storage-analyzer/cleanup.sh" "$@" 2>&1; }

  # (a) a preview is a block with the standard banner, in the log of its own, and removes nothing
  out="$(cleanup --stale-apps)"
  log="$home/mac-analyzers/reports/storage/cleanup-apps.log"
  check "[$sh] an apps preview prints the standard banner" "$(grep -q '^cleanup | apps | DRY RUN | [0-9-]* [0-9:]*$' <<<"$out" && echo ok || echo "no banner")"
  check "[$sh] the same block is in cleanup-apps.log" "$(grep -q '^cleanup | apps | DRY RUN |' "$log" 2>/dev/null && echo ok || echo "no log")"
  check "[$sh] a preview lists each app's bundle as [APP] and removes nothing" \
        "$([[ "$(grep -c '^  \[APP\]' <<<"$out")" -eq 2 && -d "$one" && -d "$two" ]] && echo ok || echo "wrong")"

  # ---- discovery: found by a date, kept when it cannot be judged, removed only through a reviewed list
  disc="$TMP/disc-$k"; mkdir -p "$disc/stubs" "$disc/apps" "$disc/launch" "$disc/home"
  mkapp() { # name [extra plist keys] [extra dirs...]: a stand-in app with an Info.plist
    local n="$1" extra="${2:-}"
    mkdir -p "$disc/apps/$n.app/Contents"
    printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.%s</string>%s</dict></plist>' "$n" "$extra" > "$disc/apps/$n.app/Contents/Info.plist"
  }
  mkapp Old; mkapp Never; mkapp Recent; mkapp NoRecord; mkapp WithAgent; mkapp WithLoginItem; mkapp WithSysExt
  mkapp OpenAtLogin
  # the audit's inventory: an "Open at Login" item whose app is OpenAtLogin (System Settings items have no plist)
  printf '#login-items-inventory\t2\t%s\tdry-run\tid\tlogins=read\nloginitem\tuser\tOpenAtLogin\t\t%s/apps/OpenAtLogin.app\tok\tenabled\t\t\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$disc" > "$disc/login-items.tsv"
  mkapp MenuBar '<key>LSUIElement</key><true/>'; mkapp Holder; mkdir -p "$disc/apps/Holder.app/Contents/Resources/Inner.app/Contents"
  mkdir -p "$disc/apps/WithLoginItem.app/Contents/Library/LoginItems/Helper.app" "$disc/apps/WithSysExt.app/Contents/Library/SystemExtensions/x.systemextension"
  # a launch agent whose program is inside WithAgent
  printf '<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>org.test.agent</string><key>ProgramArguments</key><array><string>%s/apps/WithAgent.app/Contents/MacOS/agent</string></array></dict></plist>' "$disc" > "$disc/launch/org.test.agent.plist"
  today="$(date '+%Y-%m-%d %H:%M:%S %z')"
  # Spotlight's answers: last opened and date added, per app
  cat > "$disc/stubs/mdls" <<STUB
#!/bin/bash
app=""; for a in "\$@"; do app="\$a"; done
attr="\$2"
case "\$app" in
  *NoRecord.app) echo "(null)";;
  *Recent.app)   [[ "\$attr" == kMDItemLastUsedDate ]] && echo "$today" || echo "2020-01-01 00:00:00 +0000";;
  *Never.app)    [[ "\$attr" == kMDItemLastUsedDate ]] && echo "(null)" || echo "2020-01-01 00:00:00 +0000";;
  *)             [[ "\$attr" == kMDItemCFBundleIdentifier ]] && echo "(null)" || { [[ "\$attr" == kMDItemLastUsedDate ]] && echo "2024-01-02 03:04:05 +0000" || echo "2020-01-01 00:00:00 +0000"; };;
esac
STUB
  printf '#!/bin/bash\nif [[ -f "%s/index-off" ]]; then echo "/: Indexing disabled."; else echo "/: Indexing enabled."; fi\n' "$disc" > "$disc/stubs/mdutil"
  chmod +x "$disc/stubs/mdls" "$disc/stubs/mdutil"
  dtree="$TMP/dtree-$k"; make_tree "$dtree"; printf 'ANALYZERS_APP_DIRS="%s/apps"\nANALYZERS_LAUNCH_DIRS="%s/launch"\nANALYZERS_LOGIN_INVENTORY="%s/login-items.tsv"\n' "$disc" "$disc" "$disc" > "$dtree/config.local.sh"
  dscript="$dtree/storage-analyzer/cleanup.sh"
  dcleanup() { PATH="$disc/stubs:$PATH" HOME="$disc/home" "$sh" "$dscript" "$@" 2>&1; }
  out="$(dcleanup --stale-apps)"
  rowfor() { sed -n "/^### APP: $1 /,/^### APP:/p" <<<"$out"; }
  check "[$sh] an app last opened long ago, and one macOS knows but has no use of, are offered (not kept)" \
        "$([[ "$out" == *"[APP]     $disc/apps/Old.app"* && "$(rowfor Old)" != *"[KEEP]"* && "$(rowfor Never)" != *"[KEEP]"* && "$out" == *"[APP]     $disc/apps/Never.app"* ]] && echo ok || echo "wrong")"
  check "[$sh] an app opened recently is not even listed" "$([[ "$out" != *"Recent.app"* ]] && echo ok || echo listed)"
  for pair in "WithAgent|launch entry" "WithLoginItem|login item" "WithSysExt|system extension" "OpenAtLogin|Login & Startup Items" "MenuBar|menu bar" "NoRecord|no record"; do
    n="${pair%%|*}"; why="${pair#*|}"
    check "[$sh] $n is kept, with its reason ($why)" "$([[ "$(rowfor "$n")" == *"[KEEP]"*"$why"* ]] && echo ok || echo "$(rowfor "$n" | grep KEEP)")"
  done
  check "[$sh] Holder holds an app that nothing uses: it is offered, and the row says what goes with it" \
        "$([[ "$(rowfor Holder)" != *"[KEEP]"* && "$(rowfor Holder)" == *"contains: 1 other app(s) inside it, removed with it: Inner.app"* ]] && echo ok || echo "$(rowfor Holder)")"
  : > "$disc/index-off"
  out="$(dcleanup --stale-apps)"
  check "[$sh] with indexing off, an app with no record of use is kept, not 'never opened'" "$([[ "$(rowfor Never)" == *"[KEEP]"*"indexing is off"* ]] && echo ok || echo "$(rowfor Never)")"
  rm -f "$disc/index-off"

  # found by a date, never chosen: --execute needs a reviewed list, with or without --yes; nothing is touched
  for flags in "--execute" "--execute --yes"; do
    out="$(dcleanup --stale-apps $flags)"; rc=$?
    check "[$sh] found apps: '--stale-apps $flags' with no reviewed list refuses (exit 78) and removes nothing" \
          "$([[ $rc -eq 78 && -d "$disc/apps/Old.app" && -d "$disc/apps/Never.app" && "$out" == *"only removed after a review"* ]] && echo ok || echo "exit $rc")"
  done
  # a reviewed list that names a KEPT app still does not remove it; the offered one goes to the Trash with a receipt
  printf '%s\n%s\n' "$disc/apps/WithAgent.app" "$disc/apps/Old.app" > "$disc/list"
  out="$(dcleanup --stale-apps --execute --yes --only-paths "$disc/list")"
  check "[$sh] a reviewed list that names a kept app does not remove it" "$([[ -d "$disc/apps/WithAgent.app" ]] && echo ok || echo removed)"
  check "[$sh] the offered app went to the Trash, not away (and its source is gone)" \
        "$([[ ! -e "$disc/apps/Old.app" && -d "$disc/home/.Trash/Old.app" ]] && echo ok || echo "not in the Trash")"
  check "[$sh] with a receipt Undo reads: [TRASHED] size  source  ->  destination" \
        "$(grep -qE "^  \[TRASHED\] .*  $disc/apps/Old.app  ->  $disc/home/.Trash/Old.app  #id=[0-9]+:[0-9]+\$" <<<"$out" && echo ok || echo "no receipt: $(grep TRASHED <<<"$out" | head -2)")"
  # the person's own choices keep working as before: a configured list, and --app
  printf 'ANALYZERS_STALE_APPS=( "%s/apps/Never.app" )\nANALYZERS_APP_DIRS="%s/apps"\nANALYZERS_LAUNCH_DIRS="%s/launch"\n' "$disc" "$disc" "$disc" > "$dtree/config.local.sh"
  dcleanup --stale-apps --execute --yes >/dev/null; rc=$?
  check "[$sh] a list the person wrote in config.local.sh is removed with --execute --yes, as before" "$([[ $rc -eq 0 && ! -e "$disc/apps/Never.app" ]] && echo ok || echo "exit $rc")"
  dcleanup --app "$disc/apps/NoRecord.app" --execute --yes >/dev/null; rc=$?
  check "[$sh] --app NAME is removed with --execute --yes, as before" "$([[ $rc -eq 0 && ! -e "$disc/apps/NoRecord.app" ]] && echo ok || echo "exit $rc")"

  # (b) a list of one real and one gone path: only the real one is listed, the other is skipped
  printf '%s\n%s\n' "$one" "$home/Applications/Gone.app" > "$TMP/list-$k"
  out="$(cleanup --stale-apps --only-paths "$TMP/list-$k")"
  check "[$sh] a list names one app: it is listed, the other is skipped" \
        "$([[ "$(grep -c '^  \[APP\]' <<<"$out")" -eq 1 && "$(grep -c '\[SKIP\] not in approved set' <<<"$out")" -eq 1 ]] && echo ok || echo "wrong")"
  : > "$TMP/empty-$k"
  out="$(cleanup --stale-apps --only-paths "$TMP/empty-$k")"
  check "[$sh] an empty list lists nothing" "$([[ "$(grep -c '^  \[APP\]' <<<"$out")" -eq 0 && "$(grep -c '\[SKIP\] not in approved set' <<<"$out")" -eq 2 ]] && echo ok || echo "wrong")"

  # (c) the 78 cases: no list file, no library
  out="$(cleanup --stale-apps --only-paths "$TMP/nope-$k")"; rc=$?
  check "[$sh] a list file that does not exist: exit 78, nothing touched" "$([[ $rc -eq 78 && -d "$one" && "$out" == *"not found"* ]] && echo ok || echo "exit $rc")"
  nolib="$TMP/nolib-$k"; make_tree "$nolib"; write_config "$nolib" "$home"; rm "$nolib/lib/approved-list.sh"
  out="$(HOME="$home" "$sh" "$nolib/storage-analyzer/cleanup.sh" --stale-apps --only-paths "$TMP/list-$k" 2>&1)"; rc=$?
  check "[$sh] a missing lib/approved-list.sh: exit 78 with the reason" "$([[ $rc -eq 78 && "$out" == *"approved-list.sh is missing"* ]] && echo ok || echo "exit $rc")"

  # (d) a real run, on these fixtures only: the listed app and its footprint go, the unlisted one stays
  printf '%s\n%s\n' "$one" "$home/Library/Application Support/FixtureOne" > "$TMP/exec-$k"
  cleanup --stale-apps --execute --yes --only-paths "$TMP/exec-$k" >/dev/null
  check "[$sh] a reviewed apply removes the listed app and its footprint" \
        "$([[ ! -e "$one" && ! -e "$home/Library/Application Support/FixtureOne" ]] && echo ok || echo "still there")"
  check "[$sh] and leaves the unlisted app and its footprint alone" \
        "$([[ -d "$two" && -d "$home/Library/Application Support/FixtureTwo" ]] && echo ok || echo "removed")"
  check "[$sh] the apply is in the log with the APPLY banner" "$(grep -q '^cleanup | apps | APPLY |' "$log" && echo ok || echo "no APPLY block")"

  # recordings: the same rules, the folder's path is the key
  out="$(cleanup --recordings-older-than 1)"
  check "[$sh] a recordings preview has its own banner and log" \
        "$(grep -q '^cleanup | recordings | DRY RUN |' <<<"$out" && [[ -f "$home/mac-analyzers/reports/storage/cleanup-recordings.log" ]] && echo ok || echo "wrong")"
  printf '%s\n' "$home/Recordings/OldFixtureOne" > "$TMP/rec-$k"
  rout="$(cleanup --recordings-older-than 1 --execute --yes --only-paths "$TMP/rec-$k")"
  check "[$sh] a removed recording is in the Trash, with a receipt Undo reads" \
        "$([[ -d "$home/.Trash/OldFixtureOne" ]] && grep -qE "^  \[TRASHED\] .*  $home/Recordings/OldFixtureOne  ->  $home/.Trash/OldFixtureOne  #id=[0-9]+:[0-9]+\$" <<<"$rout" && echo ok || echo "$(grep TRASHED <<<"$rout")")"
  check "[$sh] a reviewed recordings apply removes the listed folder only" \
        "$([[ ! -e "$home/Recordings/OldFixtureOne" && -d "$home/Recordings/OldFixtureTwo" ]] && echo ok || echo "wrong")"
  : > "$TMP/rec-empty-$k"
  cleanup --recordings-older-than 1 --execute --yes --only-paths "$TMP/rec-empty-$k" >/dev/null
  check "[$sh] an empty list removes no recording" "$([[ -d "$home/Recordings/OldFixtureTwo" ]] && echo ok || echo "removed")"
done
exit $fail
