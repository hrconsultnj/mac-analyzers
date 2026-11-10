# shellcheck shell=bash
# lib/live-sessions.sh — the live AI-session exemption, shared by every sweep.
# ---------------------------------------------------------------------------
# Finds running AI coding sessions in the process table and lists every
# process that descends from one, so a sweep never touches a live session's
# MCP servers or the commands it is waiting on (CONTRIBUTING.md invariant 3).
#
# Session roots:
#   * Claude Code — runs as `claude`: a native binary under
#     ~/.local/share/claude/versions/<v> (or ~/.local/bin/claude); older
#     installs ran `node …/@anthropic-ai/claude-code/cli.js`.
#   * Codex — the ChatGPT app's codex app-server.
# The executable NAME is matched, not one install path: a path-only pattern
# silently stops matching when the installer moves the binary — and then the
# exemption protects nothing while every sweep still looks healthy.
#
#   live_session_roots            → space-separated root pids
#   live_session_exempt [ROOTS]   → every pid descending from ROOTS (roots
#                                   included), one per line
# ---------------------------------------------------------------------------

live_session_roots() {
  # tr: macOS awk errors on literal newlines in -v values — keep it space-separated
  ps axo pid=,args= | awk '
    { n = split($2, part, "/"); exe = part[n] }
    exe ~ /^(awk|grep|ugrep|rg|sed|ps|pgrep|lsof)$/ { next }
    exe == "claude" || exe == "codex" || /\.local\/(bin|share)\/claude|@anthropic-ai\/claude-code|ChatGPT\.app.*codex/ { print $1 }' \
    | tr '\n' ' '
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
