# shellcheck shell=bash
# lib/guard-select.sh — what the memory guard and the cleanups may choose from, and what the app asks them to keep.
# ---------------------------------------------------------------------------
# Plain functions with no side effects, so memory-analyzer/tests/guard-exemption-test.sh can judge them on a stand-in
# process table. Works under the bash macOS ships (3.2) and the awk it ships: no associative arrays, no mapfile.
#
#   guard_select_candidates KILLRE PROTRE SELFPID EXEMPT_PIDS NEVERFILE
#       stdin: `ps axo pid=,rss=,args=` lines.   stdout: pid <TAB> rss_kb <TAB> args, for each process that
#       matches KILLRE, does not match PROTRE, is not the guard itself, is not in EXEMPT_PIDS (a live coding session and
#       everything below it: `live_session_exempt`), and is not on the person's Never Close list (NEVERFILE).
#   guard_never_pids NEVERFILE ARGCOL
#       stdin: tab-separated rows whose first field is the pid and whose field ARGCOL is the command line.
#       stdout: the pids on the Never Close list, one per line (for the cleanups, which build their own tables).
#   guard_is_never_closed NEVERFILE ARGS      → succeeds when one command line is on the Never Close list
#   guard_fallback_value FILE KEY             → the value of KEY in the app's file, nothing if absent
#
# THE FILE (reports/memory/.guard-fallback.tsv, written by the app whenever the person's lists change) can only NARROW
# what the scripts do, never widen it. It holds `key<TAB>value` lines and nothing else counts:
#   neverClosePath  a program's full path   — the command starts with it, or it is the script handed to an interpreter
#                   (the first two words after the program that are not flags: `node --inspect x.js`, `bun run x.ts`)
#   neverCloseName  a program's or app's name — the file name of the program (or of that script), or an app bundle of that name
#   pause           1 = the guard takes no action (the pause flag file does the same)
# Both kinds are matched as plain text, never as a pattern, so a name or path holding regex characters protects exactly
# itself. The numbers (the hard cap, whether a stop is allowed) come from config.local.sh alone: a file can no more
# lower a cap or switch a stop on than the person's setting can be overruled by a stale copy. A line with more than two
# fields, a carriage return, or a key not listed here is ignored whole (a path holding a line break must not become a key).
# ---------------------------------------------------------------------------

# awk helpers shared by every matcher: never_load FILE, then never_hit(COMMAND LINE) → 1 when the command is on the list
_GUARD_NEVER_AWK='
function never_load(file,   line, n, f) {
  nn = 0; nm = 0
  if (file == "") return
  while ((getline line < file) > 0) {
    if (index(line, "\r") > 0) continue
    n = split(line, f, "\t")
    if (n != 2 || f[2] == "") continue
    if (f[1] == "neverClosePath" && substr(f[2], 1, 1) == "/") { nn++; npath[nn] = f[2] }
    else if (f[1] == "neverCloseName") { nm++; nname[nm] = tolower(f[2]) }
  }
  close(file)
}
function base(word,   k, parts) { k = split(word, parts, "/"); return tolower(parts[k]) }
function stem(name) { sub(/\.(js|mjs|cjs|ts|py|rb|sh)$/, "", name); return name }
function never_hit(args,   i, k, c, first, nt, tok, nc, cand, lower) {
  first = args; sub(/ .*/, "", first)
  # the program is the first word; for an interpreter it is also the script it was handed: the first words after it that
  # are not flags (node --inspect x.js, python3 -u x.py, bun run x.ts: the first two, so a subcommand does not hide the script)
  nt = split(args, tok, " "); nc = 0
  for (k = 2; k <= nt && nc < 2; k++) if (tok[k] != "" && substr(tok[k], 1, 1) != "-") cand[++nc] = tok[k]
  for (i = 1; i <= nn; i++) {
    if (index(args, npath[i]) == 1) return 1
    for (c = 1; c <= nc; c++) if (index(cand[c], npath[i]) == 1) return 1
  }
  lower = tolower(args)
  for (i = 1; i <= nm; i++) {
    if (base(first) == nname[i] || stem(base(first)) == nname[i]) return 1
    for (c = 1; c <= nc; c++) if (base(cand[c]) == nname[i] || stem(base(cand[c])) == nname[i]) return 1
    if (index(lower, "/" nname[i] ".app/") > 0) return 1
  }
  return 0
}
'

guard_select_candidates() {
  awk -v killre="$1" -v protre="$2" -v self="$3" -v exempt="$4" -v neverfile="$5" "$_GUARD_NEVER_AWK"'
    BEGIN {
      n = split(exempt, e, /[[:space:]]+/)
      for (i = 1; i <= n; i++) if (e[i] != "") ex[e[i]] = 1
      never_load(neverfile)
    }
    { pid = $1; rss = $2; $1 = ""; $2 = ""; sub(/^ +/, "")
      if (pid + 0 <= 500 || pid == self) next
      if (pid in ex) next
      if ($0 !~ killre) next
      if ($0 ~ protre) next
      if (never_hit($0)) next
      gsub(/\t/, " ")
      printf "%s\t%s\t%.400s\n", pid, rss, $0 }'
}

guard_never_pids() {
  awk -F'\t' -v neverfile="$1" -v col="$2" "$_GUARD_NEVER_AWK"'
    BEGIN { never_load(neverfile) }
    nn + nm > 0 && never_hit($col) { print $1 }'
}

guard_is_never_closed() {
  [[ -r "$1" ]] || return 1
  awk -v neverfile="$1" -v args="$2" "$_GUARD_NEVER_AWK"'
    BEGIN { never_load(neverfile); exit (nn + nm > 0 && never_hit(args)) ? 0 : 1 }'
}

guard_fallback_value() {
  [[ -r "$1" ]] || return 0
  awk -F'\t' -v key="$2" 'NF == 2 && $1 == key && index($0, "\r") == 0 { print $2; exit }' "$1" 2>/dev/null
}
