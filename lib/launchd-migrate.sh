# shellcheck shell=bash
# Schedule copy and removal of a com.mac-analyzers.* agent when installing
# com.sparehold.*. Sourced by the manage-agents scripts. Bash 3.2.
# sparehold_read_schedule sets the globals old_h, old_m and old_i.

sparehold_legacy_label() {
  printf '%s\n' "$1" | sed 's/^com\.sparehold\./com.mac-analyzers./'
}

sparehold_read_schedule() {
  local plist="$1"
  # Globals. sparehold_hydrate_agent reads them after this returns.
  # shellcheck disable=SC2034
  old_h=""
  # shellcheck disable=SC2034
  old_m=""
  # shellcheck disable=SC2034
  old_i=""
  [[ -f "$plist" ]] || return 0
  old_h=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Hour" "$plist" 2>/dev/null || true)
  old_m=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Minute" "$plist" 2>/dev/null || true)
  old_i=$(/usr/libexec/PlistBuddy -c "Print :StartInterval" "$plist" 2>/dev/null || true)
}

# Writes the hydrated plist for label. Reads the new plist's schedule when it
# exists, otherwise the legacy plist's. Removes the quarantine attribute before
# launchd sees the file (a quarantined plist is refused). Does not bootstrap.
sparehold_hydrate_agent() {
  local src_dir="$1" label="$2" dest="$3" here="$4"
  local legacy runner user_root
  legacy="$(sparehold_legacy_label "$label")"
  user_root="$(sparehold_user_root)"
  sparehold_read_schedule "${dest}/${label}.plist"
  if [[ -z "${old_h}" && -z "${old_m}" && -z "${old_i}" ]]; then
    sparehold_read_schedule "${dest}/${legacy}.plist"
    if [[ -n "${old_h}" || -n "${old_m}" || -n "${old_i}" ]]; then
      echo "   taking the schedule from ${legacy}"
    fi
  fi
  runner="/Applications/Sparehold.app/Contents/MacOS/agent-runner"
  [[ -x "$runner" ]] || runner="/Applications/MacAnalyzers.app/Contents/MacOS/agent-runner"
  [[ -x "$runner" ]] || runner="$(dirname "$here")/app/Sparehold.app/Contents/MacOS/agent-runner"
  [[ -x "$runner" ]] || runner="$(dirname "$here")/app/MacAnalyzers.app/Contents/MacOS/agent-runner"
  # __HOME__/mac-analyzers is the data-root prefix in the template. Replace it
  # before the bare __HOME__ placeholder, or the longer path is never matched.
  if [[ -x "$runner" ]]; then
    sed -e "s|__RUNNER__|${runner}|g" \
        -e "s|__SUITE_DIR__|${here}|g" \
        -e "s|__HOME__/mac-analyzers|${user_root}|g" \
        -e "s|__HOME__|${HOME}|g" \
        "${src_dir}/${label}.plist" > "${dest}/${label}.plist"
  else
    sed -e "/__RUNNER__/d" \
        -e "s|__SUITE_DIR__|${here}|g" \
        -e "s|__HOME__/mac-analyzers|${user_root}|g" \
        -e "s|__HOME__|${HOME}|g" \
        "${src_dir}/${label}.plist" > "${dest}/${label}.plist"
  fi
  # launchd refuses a plist that still carries the quarantine attribute.
  xattr -d com.apple.quarantine "${dest}/${label}.plist" 2>/dev/null || true
  if [[ -n "${old_h}" && -n "${old_m}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour ${old_h}" \
                            -c "Set :StartCalendarInterval:Minute ${old_m}" \
                            "${dest}/${label}.plist" 2>/dev/null \
      && echo "   kept custom schedule (${old_h}:$(printf '%02d' "$old_m"))"
  fi
  if [[ -n "${old_i}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :StartInterval ${old_i}" \
                            "${dest}/${label}.plist" 2>/dev/null \
      && echo "   kept custom interval (${old_i}s)"
  fi
}

# Bootouts the legacy label and deletes its plist. Waits until launchd has let
# go, the same pause lib/launchd-reload.sh uses, so the new agent is not
# started while the old one is still exiting. Does not touch the new label.
sparehold_bootout_legacy() {
  local domain="$1" legacy="$2" dest="$3" i=0
  if [[ ! -f "${dest}/${legacy}.plist" ]] && ! launchctl print "${domain}/${legacy}" >/dev/null 2>&1; then
    return 0
  fi
  launchctl bootout "${domain}/${legacy}" >/dev/null 2>&1 || true
  while launchctl print "${domain}/${legacy}" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do
    sleep 0.2
    i=$((i + 1))
  done
  rm -f "${dest}/${legacy}.plist"
  echo "   removed ${legacy}"
}
