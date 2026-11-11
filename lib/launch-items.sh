#!/usr/bin/env bash
# launch-items.sh — what is registered to run on its own, shared by the login items audit and by
# cleanup.sh's discovery of unused apps. One inventory, read one way: an app that registers anything
# here is in use whether or not a person ever opens it.
#
#   plist_target <plist>             the program a launchd plist starts
#   launch_plist_files               every launchd plist: the user's and the system's agents and daemons
#   app_runs_on_its_own <app> <bid>  prints WHY an app must be kept (nothing when no sign was found):
#                                    a launchd entry that starts it or one of its helpers, a login item,
#                                    daemon or helper tool inside its bundle, a system extension, a
#                                    background-only app, other apps living inside it.

# target of a launchd plist: Program, else ProgramArguments[0]; also
# BundleProgram (relative to the app) via AssociatedBundleIdentifiers apps.
plist_target() {
  local p="$1" t
  t=$(plutil -extract Program raw -o - "$p" 2>/dev/null)
  [[ -z "$t" ]] && t=$(plutil -extract ProgramArguments.0 raw -o - "$p" 2>/dev/null)
  echo "$t"
}

# the folders launchd reads (ANALYZERS_LAUNCH_DIRS, colon-separated, replaces them: a test, or a Mac with others)
launch_plist_files() {
  local dirs d f
  IFS=: read -r -a dirs <<< "${ANALYZERS_LAUNCH_DIRS:-${HOME}/Library/LaunchAgents:/Library/LaunchAgents:/Library/LaunchDaemons}"
  for d in "${dirs[@]}"; do
    for f in "$d"/*.plist; do [[ -e "$f" ]] && echo "$f"; done
  done
}

# a plist value that is a boolean true (1/true/yes), whichever way defaults prints it
_is_true() { case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in 1|true|yes) return 0 ;; esac; return 1; }

# Does this launchd entry start the app, by any form recognised here? The program or ANY argument naming the
# bundle's path; `open -a <name|path>`, `open -b <bundle id>` (and --bundle-identifier); `osascript -e 'tell
# application "Name"'` or `application id "…"`; a shell wrapper (any argument that is a readable text file under
# 64 KB) whose text names the bundle's path or an `open -a "Name"` / `open -b <id>` of it.
# NOT recognised, so an app started only like this looks unused: a script that builds the path from variables,
# `launchctl asuser`, an `open` of a URL scheme the app handles, cron, Shortcuts or Automator, a login hook, and an
# app that another program opens on demand.
launch_entry_mentions_app() {  # plist app bid name
  local p="$1" app="$2" bid="$3" name="$4" i el prev="" prog
  prog="$(plutil -extract Program raw -o - "$p" 2>/dev/null)"
  local -a elements=()
  [[ -n "$prog" ]] && elements+=( "$prog" )
  for ((i = 0; i < 16; i++)); do
    el="$(plutil -extract "ProgramArguments.$i" raw -o - "$p" 2>/dev/null)" || break
    elements+=( "$el" )
  done
  for el in ${elements[@]+"${elements[@]}"}; do
    [[ "$el" == "$app" || "$el" == "$app"/* ]] && return 0
    if [[ "$prev" == "-a" && ( "$el" == "$name" || "$el" == "$name.app" ) ]]; then return 0; fi
    if [[ ( "$prev" == "-b" || "$prev" == "--bundle-identifier" ) && -n "$bid" && "$el" == "$bid" ]]; then return 0; fi
    case "$el" in
      *"application \"$name\""*|*"application \"$name.app\""*|*"application \"$app\""*) return 0 ;;
      *"application id \"$bid\""*) [[ -n "$bid" ]] && return 0 ;;
    esac
    if [[ -f "$el" && -r "$el" ]] && [[ "$(stat -f %z "$el" 2>/dev/null || echo 999999)" -le 65536 ]] && grep -Iq . "$el" 2>/dev/null; then
      grep -qF -e "$app" -e "-a \"$name\"" -e "-a '$name'" -e "-a $name" ${bid:+-e "-b $bid"} "$el" 2>/dev/null && return 0
    fi
    prev="$el"
  done
  return 1
}

app_runs_on_its_own() {
  local app="$1" bid="$2" p label assoc d
  # inside the bundle: login items, launch agents and daemons (SMAppService), privileged helpers
  for d in LoginItems LaunchAgents LaunchDaemons LaunchServices; do
    if [[ -d "$app/Contents/Library/$d" ]] && [[ -n "$(ls -A "$app/Contents/Library/$d" 2>/dev/null)" ]]; then
      echo "Runs in the background: it registers a login item, agent or helper"; return 0
    fi
  done
  # a system extension (drivers, VPNs, endpoint security, virtual cameras)
  if [[ -d "$app/Contents/Library/SystemExtensions" ]] && [[ -n "$(ls -A "$app/Contents/Library/SystemExtensions" 2>/dev/null)" ]]; then
    echo "Has a system extension"; return 0
  fi
  if find "$app/Contents" -maxdepth 4 -name '*.systemextension' 2>/dev/null | grep -q .; then
    echo "Has a system extension"; return 0
  fi
  # launchd entries that start the app (or something inside it) in any recognised form, or that name it
  local name="${app##*/}"; name="${name%.app}"
  while IFS= read -r p; do
    if launch_entry_mentions_app "$p" "$app" "$bid" "$name"; then
      echo "Runs in the background: a launch entry starts it"; return 0
    fi
    label=$(plutil -extract Label raw -o - "$p" 2>/dev/null)
    if [[ -n "$bid" && -n "$label" && ( "$label" == "$bid" || "$label" == "$bid".* ) ]]; then echo "Runs in the background: a launch entry belongs to it"; return 0; fi
    assoc=$(plutil -extract AssociatedBundleIdentifiers xml1 -o - "$p" 2>/dev/null)
    if [[ -n "$bid" && -n "$assoc" && "$assoc" == *"<string>${bid}</string>"* ]]; then
      echo "Runs in the background: a launch entry belongs to it"; return 0
    fi
  done < <(launch_plist_files)
  # the Login & Startup Items audit's own inventory (login-items.tsv), when it has run: its rows add what
  # the plists above cannot show, the System Settings "Open at Login" items, and every entry whose program
  # is inside the app. A stale file can only ADD a reason to keep an app, never remove one.
  local inventory="${ANALYZERS_LOGIN_INVENTORY:-${HOME}/mac-analyzers/reports/storage/login-items.tsv}"
  if [[ -f "$inventory" ]] && awk -F'\t' -v app="$app" '
        /^#/ { next }
        $5 == app || index($5, app "/") == 1 { found = 1; exit }
        END { exit found ? 0 : 1 }' "$inventory"; then
    echo "Runs in the background: it is in your Login & Startup Items"; return 0
  fi
  # an app with no window of its own: a menu-bar tool, an input method, a background service
  for d in LSUIElement LSBackgroundOnly; do
    if _is_true "$(defaults read "$app/Contents/Info" "$d" 2>/dev/null)"; then
      echo "Runs without a window, in the menu bar or the background"; return 0
    fi
  done
  # other apps live inside it
  if find "$app/Contents" -mindepth 2 -maxdepth 5 -name '*.app' 2>/dev/null | grep -q .; then
    echo "Other apps live inside it"; return 0
  fi
  return 1
}
