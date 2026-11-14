# shellcheck shell=bash
# lib/live-sessions.sh — the live AI-session exemption, shared by every sweep.
# ---------------------------------------------------------------------------
# Finds running AI coding sessions in the process table and lists every
# process that descends from one, so a sweep never touches a live session's
# MCP servers or the commands it is waiting on (CONTRIBUTING.md invariant 3).
#
# Session roots come from lib/coding-agents.tsv (Claude Code, Codex,
# Antigravity, Gemini CLI, Copilot, Grok, Kimi, OpenCode …), the same list the
# app reads. The executable NAME is matched as well as install paths: a
# path-only pattern silently stops matching when the installer moves the
# binary — and then the exemption protects nothing while every sweep still
# looks healthy.
#
#   live_session_roots            → space-separated root pids
#   live_session_exempt [ROOTS]   → every pid descending from ROOTS (roots
#                                   included), one per line
# ---------------------------------------------------------------------------

# The list of coding agents lives in coding-agents.tsv, next to this file, and
# is the SAME list the app reads (CodingAgentHosts). An agent that is not in it
# is not protected.
_LIVE_SESSION_LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/coding-agents.tsv"

# _live_session_filter — "pid args…" lines on stdin → the pids that are roots
_live_session_filter() {
  awk -v list="$_LIVE_SESSION_LIST" '
    BEGIN {
      while ((getline line < list) > 0) {
        sub(/\r$/, "", line)    # a list saved with Windows line endings must still match
        if (line ~ /^#/ || line == "") continue
        n = split(line, f, "\t")
        if (f[2] == "exe") exe[f[3]] = 1
        else if (f[2] == "ignore") ign[f[3]] = 1
        else if (f[2] == "interpreter") interp[f[3]] = 1
        else if (f[2] == "fragment") { nf++; frag[nf] = f[3]; also[nf] = (n >= 4 ? f[4] : "") }
      }
      close(list)
    }
    {
      pid = $1; args = $0; sub(/^[ \t]*[0-9]+[ \t]+/, "", args)
      nw = split(args, w, " "); first = w[1]; m = split(first, seg, "/"); name = seg[m]
      if (name in ign) next
      hit = (name in exe)
      # a fragment is matched against the programs OWN path, not against everything its arguments say
      split("", cand); nc = 1; cand[1] = first
      if (substr(first, 1, 1) == "/") {
        i = index(args, ".app/Contents/")        # an app path can hold spaces
        if (i > 0) {
          rest = substr(args, i + 14); j = index(rest, "/")
          if (j > 0) {
            after = substr(rest, j + 1); k = index(after, " ")
            head = substr(args, 1, i + 13 + j + (k > 0 ? k - 1 : length(after)))
            nc++; cand[nc] = head
            h = split(head, hs, "/"); if (hs[h] in exe) hit = 1
          }
        }
      }
      if (name in interp) {                      # node script.js: the script is the program
        for (q = 2; q <= nw; q++) if (substr(w[q], 1, 1) != "-") { nc++; cand[nc] = w[q]; break }
      }
      for (i = 1; !hit && i <= nf; i++) {
        if (also[i] != "" && index(args, also[i]) == 0) continue
        for (c = 1; c <= nc; c++) if (index(cand[c], frag[i]) > 0) { hit = 1; break }
      }
      if (hit) print pid
    }'
}

# Not knowing which programs belong to a coding session is never read as "none do".
# A list that is missing, unreadable, or names no agent makes this file refuse to be
# sourced, so every caller's "refuse to sweep without the exemption" check fires.
if [[ ! -r "$_LIVE_SESSION_LIST" ]]; then
  echo "lib/coding-agents.tsv is missing or unreadable" >&2
  return 1
fi
if ! awk -F'\t' '{ sub(/\r$/, "") } /^#/ || NF < 3 { next } $2 == "exe" || $2 == "fragment" { found = 1 } END { exit !found }' "$_LIVE_SESSION_LIST" 2>/dev/null; then
  echo "lib/coding-agents.tsv names no coding agent" >&2
  return 1
fi

# Whether the list can be read and names an agent right now: asked again at the moment a stop is about to be sent.
live_session_list_ok() {
  [[ -r "$_LIVE_SESSION_LIST" ]] && awk -F'\t' '{ sub(/\r$/, "") } /^#/ || NF < 3 { next } $2 == "exe" || $2 == "fragment" { found = 1 } END { exit !found }' "$_LIVE_SESSION_LIST" 2>/dev/null
}

# live_session_roots from stdin lines is for tests; with no arguments it reads
# the process table.
live_session_roots() {
  # tr: macOS awk errors on literal newlines in -v values — keep it space-separated
  ps axo pid=,args= | _live_session_filter | tr '\n' ' '
}

live_session_exempt() {
  local roots="${1-$(live_session_roots)}"
  [[ -n "${roots// /}" ]] || return 0
  ps axo pid=,ppid= | awk -v roots="$roots" '
    BEGIN { n = split(roots, r, /[[:space:]]+/); for (i = 1; i <= n; i++) if (r[i] != "") root[r[i]] = 1 }
    { pp[$1] = $2 }
    END {
      for (pid in pp) { q = pid; while (q > 1 && q != "") { if (q in root) { print pid; break }; q = pp[q] } }
      for (p in root) print p
    }'
}
