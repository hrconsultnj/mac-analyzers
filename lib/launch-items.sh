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

_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# the <string>s of a plist key, each ended by the ASCII record separator (a string can hold new lines and spaces)
_plist_strings() {  # plist key
  plutil -extract "$2" xml1 -o - "$1" 2>/dev/null | awk 'BEGIN { RS = "<" }
    /^string>/ { s = $0; sub(/^string>/, "", s); gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s)
                 gsub(/&apos;/, "\047", s); gsub(/&amp;/, "\\&", s); printf "%s\036", s }'
}

# The file types (extensions) and URL schemes the app declares in its Info.plist, lower case, space-separated and
# surrounded by spaces. Read once per app. An extension of "*" is left out: it would make every file the app's.
_DOC_APP=""; _DOC_EXTS=" "; _DOC_SCHEMES=" "
_load_doc_keys() {  # app
  local app="$1" plist="$1/Contents/Info.plist" xml
  [[ "$_DOC_APP" == "$app" ]] && return 0
  _DOC_APP="$app"; _DOC_EXTS=" "; _DOC_SCHEMES=" "
  [[ -f "$plist" ]] || return 0
  xml="$(plutil -extract CFBundleDocumentTypes xml1 -o - "$plist" 2>/dev/null)"
  _DOC_EXTS=" $(printf '%s' "$xml" | awk 'BEGIN { RS = "<" }
    /^key>CFBundleTypeExtensions/ { f = 1; next }
    f && /^\/array>/ { f = 0 }
    f && /^string>/ { s = $0; sub(/^string>/, "", s); if (s != "*") printf "%s ", tolower(s) }') "
  xml="$(plutil -extract CFBundleURLTypes xml1 -o - "$plist" 2>/dev/null)"
  _DOC_SCHEMES=" $(printf '%s' "$xml" | awk 'BEGIN { RS = "<" }
    /^key>CFBundleURLSchemes/ { f = 1; next }
    f && /^\/array>/ { f = 0 }
    f && /^string>/ { s = $0; sub(/^string>/, "", s); printf "%s ", tolower(s) }') "
}

# Is this a document or URL the app declares it opens? (only asked for an `open` that names no app)
_target_is_apps() {  # app target
  local t="$2" ext scheme
  _load_doc_keys "$1"
  if [[ "$t" == *"://"* ]]; then
    scheme="$(_lc "${t%%://*}")"; [[ "$_DOC_SCHEMES" == *" $scheme "* ]]; return
  fi
  t="${t%%\?*}"; t="${t%/}"
  [[ "${t##*/}" == *.* ]] || return 1
  ext="$(_lc "${t##*.}")"
  [[ -n "$ext" && "$_DOC_EXTS" == *" $ext "* ]]
}

# Do these words (one command line, quotes already removed) run `open` on the app? Parses open's own flags: a
# cluster of single letters (-na, -ga, -Fna) where a, b, s and u take the next word, --bundle-identifier, --args
# ends the flags; the name is compared without regard to case; with no -a or -b, a document or URL the app
# declares it opens counts too (open picks the app that owns it).
_open_words_launch() {  # app bid name words...
  local app="$1" bid="$2" name="$3"; shift 3
  local -a w=( ${1+"$@"} )
  local n=${#w[@]} i j k a letter val lname lbid lapp lv named=0
  local -a targets=()
  lname="$(_lc "$name")"; lbid="$(_lc "$bid")"; lapp="$(_lc "$app")"
  for ((i = 0; i < n; i++)); do
    [[ "${w[i]##*/}" == open ]] || continue
    named=0; targets=()
    for ((j = i + 1; j < n; j++)); do
      a="${w[j]}"
      case "$a" in
        --args) break ;;
        --bundle-identifier) named=1; j=$((j + 1)); val="${w[j]:-}"; [[ -n "$bid" && "$(_lc "$val")" == "$lbid" ]] && return 0 ;;
        --*) : ;;
        -?*)
          for ((k = 1; k < ${#a}; k++)); do
            letter="${a:k:1}"
            case "$letter" in
              a|b|s|u)
                if [[ $((k + 1)) -lt ${#a} ]]; then val="${a:k+1}"; else j=$((j + 1)); val="${w[j]:-}"; fi
                case "$letter" in
                  a) named=1; lv="$(_lc "${val%/}")"
                     if [[ "$lv" == "$lname" || "$lv" == "$lname.app" || "$lv" == "$lapp" || "${lv##*/}" == "$lname.app" ]]; then return 0; fi ;;
                  b) named=1; [[ -n "$bid" && "$(_lc "$val")" == "$lbid" ]] && return 0 ;;
                  u) targets+=( "$val" ) ;;
                esac
                break ;;
            esac
          done ;;
        *) targets+=( "$a" ) ;;
      esac
    done
    if [[ "$named" -eq 0 ]]; then
      for val in ${targets[@]+"${targets[@]}"}; do _target_is_apps "$app" "$val" && return 0; done
    fi
  done
  return 1
}

# Does this text (a script, or one argument that holds a command line) start the app? The path; `open` in any flag
# form; `tell app[lication] "Name"` / `application id "…"` (AppleScript's short form `app` too), in any case.
_text_launches_app() {  # app bid name text
  local app="$1" bid="$2" name="$3" text="$4" lower esc words
  [[ "$text" == *"$app"* ]] && return 0
  lower="$(_lc "$text")"; lower="${lower//\\/}"
  local lname lbid; lname="$(_lc "$name")"; lbid="$(_lc "$bid")"
  case "$lower" in
    *"application \"$lname\""*|*"application \"$lname.app\""*|*"app \"$lname\""*|*"app \"$lname.app\""*) return 0 ;;
  esac
  if [[ -n "$bid" ]]; then
    case "$lower" in *"application id \"$lbid\""*|*"app id \"$lbid\""*) return 0 ;; esac
  fi
  esc="$(printf '%s' "$lname" | sed 's/[][\.*^$(){}?+|/]/\\&/g')"
  printf '%s' "$lower" | grep -qE -- "(^|[[:space:]])-[a-z]*a[[:space:]]+[\"']?${esc}(\\.app)?([\"'[:space:];|&)]|\$)" && return 0
  if [[ -n "$bid" ]]; then
    esc="$(printf '%s' "$lbid" | sed 's/[][\.*^$(){}?+|/]/\\&/g')"
    printf '%s' "$lower" | grep -qE -- "(^|[[:space:]])(-[a-z]*b|--bundle-identifier)[[:space:]=]+[\"']?${esc}([\"'[:space:];|&)]|\$)" && return 0
  fi
  # structurally, line by line: words split at shell separators, quotes removed. (No process substitution here: this
  # runs inside the caller's own loop, and bash 3.2 crashes on nested ones once a few hundred items have gone through.)
  local lines status
  lines="$(printf '%s\n' "$text" | tr ';|&()`' '      ' | tr "\"'" '  ')"
  while IFS= read -r words; do
    [[ -n "$words" ]] || continue
    # shellcheck disable=SC2086  # the words ARE the split
    set -f; _open_words_launch "$app" "$bid" "$name" $words; status=$?; set +f
    [[ $status -eq 0 ]] && return 0
  done <<< "$lines"
  return 1
}

# Does this launchd entry start the app, by any form recognised here? Every argument is read (no limit) and the
# program too: any argument naming the bundle's path; `open` in any flag form (-a, -b, -na, -ga, -Fna, a name in
# any case, a path, --bundle-identifier), or `open` of a document or URL the app declares it opens; `osascript -e` with
# `tell app "Name"` / `tell application "Name"` / `application id "…"`; a command line inside a `-c` or `-e`
# string, also behind `env`, `arch`, `nohup`, `launchctl asuser`; a shell wrapper (any argument that is a readable text
# file under 64 KB) read the same way.
# NOT recognised, so an app started only like this looks unused: a script that builds the name or path from
# variables or command substitution, cron, Shortcuts or Automator, a login hook, a file type the app handles only by
# a UTI it does not list as an extension, a file or URL `open` hands to an app the person chose as default, and an app
# that another program opens on demand.
launch_entry_mentions_app() {  # plist app bid name
  local p="$1" app="$2" bid="$3" name="$4" el prog
  local -a elements=()
  prog="$(plutil -extract Program raw -o - "$p" 2>/dev/null)"
  [[ -n "$prog" ]] && elements+=( "$prog" )
  local strings
  strings="$(_plist_strings "$p" ProgramArguments)"
  while IFS= read -r -d $'\036' el; do elements+=( "$el" ); done <<< "$strings"
  [[ ${#elements[@]} -gt 0 ]] || return 1
  for el in "${elements[@]}"; do
    [[ "$el" == "$app" || "$el" == "$app"/* ]] && return 0
    _text_launches_app "$app" "$bid" "$name" "$el" && return 0
    if [[ -f "$el" && -r "$el" ]] && [[ "$(stat -f %z "$el" 2>/dev/null || echo 999999)" -le 65536 ]] && grep -Iq . "$el" 2>/dev/null; then
      _text_launches_app "$app" "$bid" "$name" "$(cat "$el" 2>/dev/null)" && return 0
    fi
  done
  _open_words_launch "$app" "$bid" "$name" "${elements[@]}" && return 0
  return 1
}

# Is something set up to start this app: a launchd entry (any recognised form, or one that names its bundle id), or a
# row of the Login & Startup Items audit's inventory (which adds what the plists cannot show, the System Settings
# "Open at Login" items, and every entry whose program is inside the app; a stale file can only ADD a reason)?
# Prints why and returns 0, or returns 1. Used for an app and for an app nested inside another.
_registered_to_run() {  # app bid
  local app="$1" bid="$2" p label assoc plists
  local name="${app##*/}"; name="${name%.app}"
  plists="$(launch_plist_files)"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if launch_entry_mentions_app "$p" "$app" "$bid" "$name"; then
      echo "Runs in the background: a launch entry starts it"; return 0
    fi
    label=$(plutil -extract Label raw -o - "$p" 2>/dev/null)
    if [[ -n "$bid" && -n "$label" && ( "$label" == "$bid" || "$label" == "$bid".* ) ]]; then echo "Runs in the background: a launch entry belongs to it"; return 0; fi
    assoc=$(plutil -extract AssociatedBundleIdentifiers xml1 -o - "$p" 2>/dev/null)
    if [[ -n "$bid" && -n "$assoc" && "$assoc" == *"<string>${bid}</string>"* ]]; then
      echo "Runs in the background: a launch entry belongs to it"; return 0
    fi
  done <<< "$plists"
  local inventory="${ANALYZERS_LOGIN_INVENTORY:-${HOME}/mac-analyzers/reports/storage/login-items.tsv}"
  if [[ -f "$inventory" ]] && awk -F'\t' -v app="$app" '
        /^#/ { next }
        $5 == app || index($5, app "/") == 1 { found = 1; exit }
        END { exit found ? 0 : 1 }' "$inventory"; then
    echo "Runs in the background: it is in your Login & Startup Items"; return 0
  fi
  return 1
}

# the apps inside a bundle, at any depth (an app inside an app is found when that app is asked), one path per line
nested_app_paths() {  # app
  find "$1/Contents" \( -type d -o -type l \) -iname '*.app' -prune -print 2>/dev/null
}

# every app inside this one at every level (an app inside an app inside an app too), one path per line
nested_app_paths_all() {  # app
  local n list
  list="$(nested_app_paths "$1")"
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    printf '%s\n' "$n"
    nested_app_paths_all "$n"
  done <<< "$list"
}

# the names of the apps inside this one at every level, "; " apart, and how many (for the line the review shows)
nested_app_names() {  # app -> prints "N<TAB>name; name"
  local n count=0 names="" list
  list="$(nested_app_paths_all "$1")"
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    count=$((count + 1)); names="${names:+$names; }${n##*/}"
  done <<< "$list"
  printf '%s\t%s\n' "$count" "$names"
}

# Is a program of an app running? Matching a pattern against every command line also matches the `pgrep` of ANOTHER
# run that holds the same pattern in its own command line (two previews at once, a person's own `pgrep -f`), which
# made an app look "RUNNING" when it was not. The pattern is anchored at the start of the command line (a program of
# a bundle starts with its path) and every special character is escaped, so the text of a pattern never matches
# the command line that carries it (it holds `Name\.app`, the pattern wants `Name.app`).
_ere_escape() { printf '%s' "$1" | sed 's/[][\\.*^$(){}?+|\/]/\\&/g'; }

# a program inside this bundle (the path of the .app) is running
bundle_is_running() { pgrep -f -- "^$(_ere_escape "$1")/Contents/MacOS/" >/dev/null 2>&1; }

# a process called exactly this, or a program of an app of this name in any folder, is running
app_name_is_running() { pgrep -x -- "$1" >/dev/null 2>&1 || pgrep -f -- "^/.*/$(_ere_escape "$1")\\.app/Contents/MacOS/" >/dev/null 2>&1; }

# Was this app opened within the window (ANALYZERS_STALE_APP_DAYS, 180) by its own Spotlight last-used date?
_used_within_window() {  # app
  local days="${ANALYZERS_STALE_APP_DAYS:-180}" lu ts
  lu="$(mdls -name kMDItemLastUsedDate -raw "$1" 2>/dev/null)"
  [[ -n "$lu" && "$lu" != "(null)" ]] || return 1
  ts="$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$lu" +%s 2>/dev/null)" || return 1
  [[ "$ts" -ge $(( $(date +%s) - days * 86400 )) ]]
}

# An app inside another app is part of it, and goes with it. It keeps the outer app only when it is in use in its own
# right: running now, opened within the window by its own last-used date, started by something (a launch entry or a
# login item), or holding an app that is. An updater or a helper the outer app starts when it needs it is none of
# these. Prints the nested app's name and returns 0 when one is in use.
_nested_in_use() {  # app
  local n bid list
  list="$(nested_app_paths "$1")"
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    bid="$(defaults read "$n/Contents/Info" CFBundleIdentifier 2>/dev/null)"
    if bundle_is_running "$n" || _used_within_window "$n" \
       || _registered_to_run "$n" "$bid" >/dev/null || _nested_in_use "$n" >/dev/null; then
      echo "${n##*/}"; return 0
    fi
  done <<< "$list"
  return 1
}

app_runs_on_its_own() {
  local app="$1" bid="$2" d inuse
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
  # launchd entries and login items that start the app
  _registered_to_run "$app" "$bid" && return 0
  # an app with no window of its own: a menu-bar tool, an input method, a background service
  for d in LSUIElement LSBackgroundOnly; do
    if _is_true "$(defaults read "$app/Contents/Info" "$d" 2>/dev/null)"; then
      echo "Runs without a window, in the menu bar or the background"; return 0
    fi
  done
  # apps inside it are part of it; one that is in use in its own right keeps it
  if inuse="$(_nested_in_use "$app")"; then
    echo "An app inside it is in use on its own: ${inuse%.app}"; return 0
  fi
  return 1
}
