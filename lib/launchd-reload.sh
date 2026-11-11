# shellcheck shell=bash
# reload_agent <domain> <label> <plist> — replace a loaded launchd agent with
# the plist on disk, and say plainly whether it is loaded afterwards.
#
# `launchctl bootout` returns before launchd has finished removing a service
# whose process is still exiting — the memory guard, a long-running loop,
# takes a moment to go. A `bootstrap` sent in that window fails with
# "Bootstrap failed: 5: Input/output error", and the agent is left running
# its OLD definition, or not loaded at all. So: ask it to go, wait until it
# is really gone, load the new one, and try again if launchd is not ready.
#
# Prints one indented line. Returns 0 when the agent is loaded from the plist
# on disk, 1 when it is not.
#
# Runs under the bash macOS ships (3.2).
reload_agent() {
  local domain="$1" label="$2" plist="$3" i=0 tries=0 err=""
  if launchctl print "${domain}/${label}" >/dev/null 2>&1; then
    launchctl bootout "${domain}/${label}" >/dev/null 2>&1 || true
    # up to 10 s for the old service to disappear
    while launchctl print "${domain}/${label}" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do
      sleep 0.2
      i=$((i + 1))
    done
  fi
  while [ "$tries" -lt 5 ]; do
    if err="$(launchctl bootstrap "$domain" "$plist" 2>&1)"; then
      echo "   loaded"
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  if launchctl print "${domain}/${label}" >/dev/null 2>&1; then
    echo "   NOT reloaded — it is still running its previous settings. Run this again in a minute."
  else
    echo "   NOT loaded — launchd said: $(printf '%s' "$err" | head -n 1). Run this again; if it keeps failing, log out and back in."
  fi
  return 1
}
