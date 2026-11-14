# shellcheck shell=bash
# lib/guard-select.sh — what the memory guard may choose from, and what it reads from the rules engine.
# ---------------------------------------------------------------------------
# Plain functions with no side effects, so memory-analyzer/tests/guard-exemption-test.sh can judge them on a stand-in
# process table. Works under the bash macOS ships (3.2) and the awk it ships: no associative arrays, no mapfile.
#
#   guard_select_candidates KILLRE PROTRE SELFPID EXEMPT_PIDS NEVERFILE
#       stdin: `ps axo pid=,rss=,args=` lines.   stdout: pid <TAB> rss_kb <TAB> args, for each process that
#       matches KILLRE, does not match PROTRE, is not the guard itself, is not in EXEMPT_PIDS (a live coding session and
#       everything below it: `live_session_exempt`), and does not start with a Never Close path from NEVERFILE (or run it as the script an interpreter was given).
#   guard_fallback_value FILE KEY      → the value of KEY in the rules engine's fallback file, nothing if absent
#
# The fallback file (reports/memory/.guard-fallback.tsv, written by the app on every rules change) is plain
# `key<TAB>value` lines: hardCapMB, hardCapStop, pressureStop, neverClosePath (once per path), pause. A Never Close path
# is matched as plain text with index(), never as a pattern, so a path holding regex characters protects exactly itself.
# ---------------------------------------------------------------------------

guard_select_candidates() {
  awk -v killre="$1" -v protre="$2" -v self="$3" -v exempt="$4" -v neverfile="$5" '
    BEGIN {
      n = split(exempt, e, /[[:space:]]+/)
      for (i = 1; i <= n; i++) if (e[i] != "") ex[e[i]] = 1
      nn = 0
      if (neverfile != "") {
        while ((getline line < neverfile) > 0) {
          split(line, f, "\t")
          if (f[1] == "neverClosePath" && f[2] != "") { nn++; never[nn] = f[2] }
        }
        close(neverfile)
      }
    }
    { pid = $1; rss = $2; $1 = ""; $2 = ""; sub(/^ +/, "")
      if (pid + 0 <= 500 || pid == self) next
      if (pid in ex) next
      if ($0 !~ killre) next
      if ($0 ~ protre) next
      # the own path of the program: the command starts with it, or it is the script given to an interpreter, the word after the first
      rest = $0; sub(/^[^ ]+ +/, "", rest)
      for (i = 1; i <= nn; i++) if (index($0, never[i]) == 1 || index(rest, never[i]) == 1) next
      gsub(/\t/, " ")
      printf "%s\t%s\t%.400s\n", pid, rss, $0 }'
}

guard_fallback_value() {
  [[ -r "$1" ]] || return 0
  awk -F'\t' -v key="$2" '$1 == key { print $2; exit }' "$1" 2>/dev/null
}
