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
