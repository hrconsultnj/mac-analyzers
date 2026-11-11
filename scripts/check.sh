#!/usr/bin/env bash
# check.sh — the ONE place every repository check lives.
#
#   scripts/check.sh                       every check that can run here
#   scripts/check.sh <name>...             just those checks
#   scripts/check.sh --changed <a>..<b>    only the checks whose inputs changed
#                                          in that git range (any range git
#                                          diff accepts, e.g. origin/x...HEAD)
#   scripts/check.sh <name>... --changed <a>..<b>
#                                          of the named checks, only the ones
#                                          whose inputs changed in that range
#   scripts/check.sh --list                the checks, one per line, with
#                                          what each one covers
#
# The pre-push hook (scripts/install-git-hooks.sh) is the gate for the
# maintainer's own pushes: it runs this script on the Mac, the only machine
# that can judge all of it. The GitHub workflows run the same script for pull
# requests, whose authors do not have that hook. No check logic lives
# anywhere else.
#
# Output: one line per check — ✓ passed, ✗ failed (its output follows),
# – not run (with the reason; a check that did not run is never a pass) —
# then a summary line. Exit 1 when any check failed.
#
# This script must run under the bash macOS ships (3.2): no associative
# arrays, mapfile, ${x,,}, or |& in here.
set -u

# A git hook may export GIT_DIR and friends; every git call below must find
# the repository from the working directory instead.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX

ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2

ALL="syntax lint secrets changelog tests workflows strays spi env snapshot names probes outline app"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ma-check.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out"      # detail text for the check that just ran
DETAIL=""           # the short text after the check name

usage() {
  sed -n '2,/^set -u/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

describe() {
  case "$1" in
    syntax)    echo "bash -n on every tracked *.sh and *.command; also under /bin/bash when it is older than 4" ;;
    lint)      echo "shellcheck on every tracked *.sh and *.command: any warning or error fails the check" ;;
    secrets)   echo "curated secret-pattern sweep over every tracked file" ;;
    changelog) echo "CHANGELOG.md has a '## Next' section or an entry for VERSION, and that entry reads as release notes" ;;
    tests)     echo "every executable under memory-analyzer/tests/ and tests/ (macOS only; skipped, visibly, elsewhere)" ;;
    workflows) echo "actionlint on .github/workflows (optional: skipped, visibly, when not installed)" ;;
    strays)    echo "no untracked Package.swift, .build* or zero-byte file at the repository root; no source file hidden by .gitignore" ;;
    spi)       echo "@_spi(TestSupport) appears only in AnalyzersKit (its declarations), AgentRunner and SnapshotRunner" ;;
    env)       echo "the app people install reads no environment variable: ProcessInfo's environment and getenv appear only in AgentRunner, SnapshotRunner and the one file that passes the environment on to the engine scripts" ;;
    snapshot)  echo "the snapshot tool's main.swift has no top-level await: one makes its top-level code an async task, and an app run inside a task never fires its delayed capture, so every render hangs" ;;
    probes)    echo "the probes that judge themselves on stand-in data and exit non-zero when a rule breaks: review session, run matcher, Activity row ids (agent-runner; macOS only)" ;;
    names)     echo "every name in the app's central name table (Names.swift, listed in Names.all) is in title-style capitalization — labels typed elsewhere are not covered (agent-runner --probe-names; macOS only)" ;;
    outline)   echo "the shared OutlineTable, headless: open all and re-sort with text and with hosted cells log no AppKit reentrancy warning (scripts/outline-probe.sh; macOS only)" ;;
    app)       echo "swift build of app/ (macOS only; skipped, visibly, elsewhere)" ;;
  esac
}

# ── checks ──────────────────────────────────────────────────────────────────
# Each sets DETAIL, may write detail text to $OUT, and returns
# 0 = passed, 1 = failed, 2 = not run (DETAIL says why).

script_list() { git ls-files -- '*.sh' '*.command'; }

check_syntax() {
  local f n=0 bad=0 old=""
  local sys="/bin/bash" major
  if [ -x "$sys" ] && [ "$sys" != "${BASH:-}" ]; then
    major="$("$sys" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 9)"
    [ "$major" -lt 4 ] && old="$sys"
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    n=$((n + 1))
    if ! "${BASH:-bash}" -n "$f" >>"$OUT" 2>&1; then bad=$((bad + 1)); continue; fi
    if [ -n "$old" ] && ! "$old" -n "$f" >>"$OUT" 2>&1; then
      echo "  ^ $f does not parse under $old (bash 3.2) — see the bash-3.2 rule in CLAUDE.md" >>"$OUT"
      bad=$((bad + 1))
    fi
  done <<EOF
$(script_list)
EOF
  if [ "$bad" -gt 0 ]; then DETAIL="$bad of $n scripts do not parse"; return 1; fi
  if [ -n "$old" ]; then DETAIL="$n scripts (also parsed by $old, bash 3.2)"; else DETAIL="$n scripts"; fi
  return 0
}

check_lint() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    DETAIL="shellcheck is not installed"
    echo "install it:  brew install shellcheck   (macOS)   |   sudo apt-get install shellcheck   (Debian/Ubuntu)" >"$OUT"
    return 1
  fi
  local n findings rc
  n="$(script_list | wc -l | tr -d ' ')"
  # Warnings are defects: shellcheck is telling us the code is not written the
  # way its documentation intends. Fix the code; where a warning is a false
  # positive, say why with a `# shellcheck disable=SCxxxx  # reason` line.
  # One file per shellcheck run: given every script at once, shellcheck can
  # stay silent about a finding it reports when the file is checked alone (an
  # unused local did exactly that), and an editor checks one file at a time.
  script_list | tr '\n' '\0' | xargs -0 -n1 shellcheck -f gcc -S warning >"$TMP/lint.out" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    findings="$(grep -c -E ': (warning|error): ' "$TMP/lint.out")"
    [ "$findings" -gt 0 ] || findings="?"
    DETAIL="$findings finding(s) in $n scripts (a warning fails the check)"
    cat "$TMP/lint.out" >"$OUT"
    return 1
  fi
  DETAIL="$n scripts"
  return 0
}

check_secrets() {
  # Pattern prefixes are split so this file never contains a contiguous
  # secret-shaped literal (which trips secret scanners, this sweep included).
  local S1='sk_' S2='rk_' G1='ghp_' G2='gho_' A1='AKIA' X1='xox'
  git ls-files -z | xargs -0 grep -nEI \
    -e "${A1}[0-9A-Z]{16}" \
    -e "${G1}[A-Za-z0-9]{36}|${G2}[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}" \
    -e '\-\-\-\-\-BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY' \
    -e "${S1}live_[A-Za-z0-9]{20,}|${S2}live_[A-Za-z0-9]{20,}" \
    -e "${X1}[baprs]-[A-Za-z0-9-]{10,}" \
    -e '(postgres|postgresql|mysql|mongodb(\+srv)?|redis|amqp)://[^ "]*:[^ "]*@' \
    -e 'AIza[0-9A-Za-z_-]{35}' \
    -e 'https://hooks\.slack\.com/services/T[A-Za-z0-9_/]+' \
    2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' >"$TMP/secrets.hits"
  if [ -s "$TMP/secrets.hits" ]; then
    # file:line only — the match itself is the secret, so it is not echoed
    cut -d: -f1,2 "$TMP/secrets.hits" >"$OUT"
    DETAIL="possible secret on $(wc -l <"$TMP/secrets.hits" | tr -d ' ') line(s) — inspect the file:line pairs below"
    return 1
  fi
  DETAIL="no secrets detected"
  return 0
}

check_changelog() {
  if [ ! -f CHANGELOG.md ] || [ ! -f VERSION ]; then
    DETAIL="CHANGELOG.md or VERSION is missing"
    return 1
  fi
  local version entry next
  version="$(tr -d ' \n' <VERSION)"
  entry="$(grep -c -E "^## v${version//./\\.}( |\$)" CHANGELOG.md)"
  next="$(grep -c -E '^## Next[[:space:]]*$' CHANGELOG.md)"
  if [ "$entry" -gt 0 ]; then
    if scripts/changelog-check.sh "$version" >"$OUT" 2>&1; then
      : >"$OUT"
      DETAIL="entry for v$version passes the release-notes check"
      return 0
    fi
    DETAIL="entry for v$version does not pass scripts/changelog-check.sh"
    return 1
  fi
  if [ "$next" -gt 0 ]; then
    DETAIL="'## Next' section present (v$version has no entry yet — it is not released)"
    return 0
  fi
  DETAIL="no '## Next' section and no entry for v$version in CHANGELOG.md"
  return 1
}

check_tests() {
  # The engine is macOS-only and its tests assert what macOS `ps` prints for a
  # process that renamed itself; Linux `ps` answers differently, so a run there
  # proves nothing about the engine. Not run is reported as not run.
  if [ "$(uname -s)" != "Darwin" ]; then DETAIL="skipped: the engine tests need macOS"; return 2; fi
  local f n=0 bad=0 unrun=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] && [ -x "$f" ] || continue
    if ! "$ROOT/$f" >"$TMP/test.out" 2>&1; then
      n=$((n + 1)); bad=$((bad + 1))
      { echo "--- $f (exit non-zero)"; cat "$TMP/test.out"; } >>"$OUT"
    elif head -n 1 "$TMP/test.out" | grep -q '^SKIP'; then
      # a test that bowed out (a tool it needs is missing) did not pass
      unrun=$((unrun + 1))
      { echo "--- $f did not run"; head -n 1 "$TMP/test.out"; } >>"$OUT"
    else
      n=$((n + 1))
    fi
  done <<EOF
$(git ls-files -- 'memory-analyzer/tests/*' 'tests/*')
EOF
  if [ "$bad" -gt 0 ]; then DETAIL="$bad of $n test scripts failed"; return 1; fi
  if [ "$n" -eq 0 ] && [ "$unrun" -gt 0 ]; then
    DETAIL="skipped: $(head -n 2 "$OUT" | tail -n 1 | sed 's/^SKIP[: ]*//')"; return 2
  fi
  if [ "$n" -eq 0 ]; then DETAIL="skipped: no executable test scripts found"; return 2; fi
  DETAIL="$n test script(s)"
  [ "$unrun" -gt 0 ] && DETAIL="$DETAIL, $unrun did not run"
  return 0
}

check_workflows() {
  if ! command -v actionlint >/dev/null 2>&1; then
    DETAIL="skipped: actionlint not installed (optional — brew install actionlint)"
    return 2
  fi
  local n
  n="$(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n" -eq 0 ]; then
    DETAIL="skipped: no workflow files"
    return 2
  fi
  if ! actionlint >"$OUT" 2>&1; then
    DETAIL="actionlint found problems in the workflows"
    return 1
  fi
  DETAIL="$n workflow file(s)"
  return 0
}

check_strays() {
  local f name bad=0
  for f in "$ROOT"/* "$ROOT"/.[!.]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    name="$(basename "$f")"
    case "$name" in
      .build*)
        echo "$name — build output at the repository root (builds belong in app/.build)" >>"$OUT"; bad=$((bad + 1)) ;;
      Package.swift)
        if [ -z "$(git ls-files -- "$name")" ]; then
          echo "$name — untracked Package.swift at the repository root (the package lives in app/)" >>"$OUT"; bad=$((bad + 1))
        fi ;;
      *)
        if [ -f "$f" ] && [ ! -s "$f" ] && [ -z "$(git ls-files -- "$name")" ]; then
          echo "$name — zero-byte file at the repository root" >>"$OUT"; bad=$((bad + 1))
        fi ;;
    esac
  done
  # A source file that an ignore rule hides is never committed: the app builds
  # here and fails from any clean copy (an upgrade, a download, a pull request).
  # It happened with `reports/` matching `Screens/System/Reports/` on a
  # case-insensitive disk. No file under the app's sources or the engine's
  # script folders may be ignored.
  local ignored
  ignored="$(git ls-files --others --ignored --exclude-standard -- \
      app/Sources app/Package.swift scripts lib tests \
      memory-analyzer storage-analyzer network-analyzer 2>/dev/null \
    | grep -v -E '(^|/)\.[^/]+/' \
    | grep -E '\.(swift|sh|c|h|m|json|plist|strings|entitlements|command)$' || true)"
  if [ -n "$ignored" ]; then
    while IFS= read -r f; do
      echo "$f — a source file that .gitignore hides, so it would never be committed" >>"$OUT"
      bad=$((bad + 1))
    done <<EOF
$ignored
EOF
  fi
  if [ "$bad" -gt 0 ]; then DETAIL="$bad stray or hidden item(s)"; return 1; fi
  DETAIL="repository root is clean, no source file is hidden by .gitignore"
  return 0
}

# The job store's test hooks (`scriptOverride`, `outcomeOverride`, the clock and
# schedule readers, `JobOutcome.init`) are `@_spi(TestSupport)`: only code that
# writes `@_spi(TestSupport) import AnalyzersKit` can see them. That is a compile-time
# wall between our own targets, not a runtime one (the symbols are still in the
# binary). This check keeps the wall where it is: the attribute may appear in
# AnalyzersKit (where the hooks are declared) and in the two targets that are
# never part of the shipped app's behaviour — AgentRunner's probes and
# SnapshotRunner's fixtures — and nowhere else.
# One thing outside this check ON PURPOSE: `ReviewFixtureProbe` (SettingsFeature/Screens/Shared/Review) is a
# `public` type compiled into the shipped module, with no `@_spi`, that only SnapshotRunner reaches. It builds
# scenarios from the fixture rows only, exposes `report()` and named steps, and cannot apply anything: the same
# wall as `DeepLinkRouter.installFixtures()`. Do not copy the pattern for anything that can change a real preview.
# MA_SPI_ROOT points the check at another copy of app/Sources (used to prove it fails).
check_spi() {
  local root="${MA_SPI_ROOT:-$ROOT/app/Sources}"
  if [ ! -d "$root" ]; then DETAIL="skipped: no app/Sources"; return 2; fi
  local hits
  hits="$(cd "$root" && grep -rnE '@_spi[[:space:]]*\([[:space:]]*TestSupport[[:space:]]*\)' --include='*.swift' . 2>/dev/null \
    | grep -v '^\./AnalyzersKit/' | grep -v '^\./AgentRunner/' | grep -v '^\./SnapshotRunner/' || true)"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >"$OUT"
    echo "the test-only interface is used outside AnalyzersKit, AgentRunner and SnapshotRunner" >>"$OUT"
    DETAIL="$(printf '%s\n' "$hits" | wc -l | tr -d ' ') use(s) of @_spi(TestSupport) in the app's own code"
    return 1
  fi
  DETAIL="@_spi(TestSupport) stays in AnalyzersKit, AgentRunner and SnapshotRunner"
  return 0
}

# The names of screens, tasks, scopes and states are written once, in
# `AnalyzersKit/Naming/Names.swift`, and are all title-style names. The probe
# lives in `agent-runner` so the check never parses Swift with grep: it builds
# the runner, asks it to print every name and exits 1 on one that
# `TitleStyle` rejects. MA_NAMES_APP points the check at another copy of app/
# (used to prove it fails on a lowercased name).
# The app reads no environment variable. A variable is a switch nobody can see:
# a test hook left in shipping code changes what the installed app does for
# whoever happens to have it set. The two tools that never ship (AgentRunner's
# probes, SnapshotRunner) may read them and hand the value in; EngineProcess
# passes the environment on to the engine scripts, which is its job.
check_env() {
  if [ ! -d app/Sources ]; then DETAIL="skipped: no app/Sources"; return 2; fi
  grep -rnE 'processInfo\.environment|(^|[^A-Za-z_])(getenv|setenv|unsetenv|putenv)\(' --include='*.swift' app/Sources 2>/dev/null \
    | grep -v -E '^app/Sources/(AgentRunner|SnapshotRunner)/' \
    | grep -v -E '^app/Sources/AnalyzersKit/Jobs/EngineProcess\.swift:' \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*//' \
    | cut -c1-300 >"$OUT"
  if [ -s "$OUT" ]; then
    DETAIL="shipping code reads the environment — pass the value in from AgentRunner or SnapshotRunner instead"
    return 1
  fi
  DETAIL="no environment read outside AgentRunner, SnapshotRunner and EngineProcess"
  return 0
}

# SnapshotRunner renders a screen and captures it after a delay on the main
# dispatch queue. One `await` in main.swift's top-level code turns that code
# into an async task; NSApplication.run() started inside a task never services
# the main dispatch queue, the capture never fires, and every render hangs
# until something kills it (found 2026-11-11, after a night of renders blamed on
# a locked screen). A real render cannot be a check (it needs an unlocked
# screen), so the cause is refused instead: no `await` at the start of a line
# outside a function, closure or type in that file.
check_snapshot() {
  local file="app/Sources/SnapshotRunner/main.swift"
  if [ ! -f "$file" ]; then DETAIL="skipped: no $file"; return 2; fi
  grep -nE '^(await|let [A-Za-z_]+ = (try )?await|try await|_ = (try )?await) ' "$file" | cut -c1-300 >"$OUT"
  if [ -s "$OUT" ]; then
    DETAIL="a top-level await in the snapshot tool — call it directly (top-level code is on the main actor) or move it into a Task"
    return 1
  fi
  DETAIL="no top-level await in the snapshot tool"
  return 0
}

# Probes that judge themselves: each builds its own stand-in data in a temporary
# folder, reads nothing of the person's, and exits non-zero when a rule breaks.
# A probe that only prints (review rules, quit, failures) is not here: nothing
# would fail. Add a probe to PROBES when it has an exit status worth trusting.
PROBES="--probe-review-session --probe-run-matcher --probe-activity-ids --probe-storage-setting --probe-disk-runway"
check_probes() {
  local app="$ROOT/app"
  if [ "$(uname -s)" != "Darwin" ]; then DETAIL="skipped: not on macOS"; return 2; fi
  if [ ! -f "$app/Package.swift" ]; then DETAIL="skipped: no app/Package.swift"; return 2; fi
  if ! command -v swift >/dev/null 2>&1; then DETAIL="skipped: swift is not installed"; return 2; fi
  local bin probe started=$SECONDS count=0
  if ! ( cd "$app" && env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
          swift build --disable-keychain --product AgentRunner ) >"$TMP/probes-build.out" 2>&1; then
    grep -a -E ': error: ' "$TMP/probes-build.out" | cut -c1-300 | awk '!seen[$0]++' | head -10 >"$OUT"
    [ -s "$OUT" ] || tail -n 10 "$TMP/probes-build.out" | cut -c1-300 >"$OUT"
    DETAIL="could not build agent-runner"
    return 1
  fi
  bin="$(cd "$app" && swift build --disable-keychain --show-bin-path 2>/dev/null)/AgentRunner"
  if [ ! -x "$bin" ]; then DETAIL="agent-runner was not built"; return 1; fi
  for probe in $PROBES; do
    if ! "$bin" "$probe" >"$TMP/probe.out" 2>&1; then
      { grep -a -E '^(FAIL|✗)' "$TMP/probe.out" | head -15; tail -n 2 "$TMP/probe.out"; } | cut -c1-300 >"$OUT"
      DETAIL="$probe failed"
      return 1
    fi
    count=$((count + 1))
  done
  DETAIL="$count probe(s) hold ($((SECONDS - started))s)"
  return 0
}

check_names() {
  local app="${MA_NAMES_APP:-$ROOT/app}"
  if [ "$(uname -s)" != "Darwin" ]; then DETAIL="skipped: not on macOS"; return 2; fi
  if [ ! -f "$app/Package.swift" ]; then DETAIL="skipped: no app/Package.swift"; return 2; fi
  if ! command -v swift >/dev/null 2>&1; then DETAIL="skipped: swift is not installed"; return 2; fi
  local bin
  if ! ( cd "$app" && env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
          swift build --disable-keychain --product AgentRunner ) >"$TMP/names-build.out" 2>&1; then
    grep -a -E ': error: ' "$TMP/names-build.out" | cut -c1-300 | awk '!seen[$0]++' | head -10 >"$OUT"
    [ -s "$OUT" ] || tail -n 10 "$TMP/names-build.out" | cut -c1-300 >"$OUT"
    DETAIL="could not build agent-runner"
    return 1
  fi
  bin="$(cd "$app" && swift build --disable-keychain --show-bin-path 2>/dev/null)/AgentRunner"
  if [ ! -x "$bin" ]; then DETAIL="agent-runner was not built"; return 1; fi
  if "$bin" --probe-names >"$TMP/names.out" 2>&1; then
    DETAIL="$(tail -n 1 "$TMP/names.out")"
    return 0
  fi
  grep -a '^FAIL' "$TMP/names.out" >"$OUT"
  tail -n 1 "$TMP/names.out" >>"$OUT"
  DETAIL="a name is not in title style"
  return 1
}

# Every table whose rows open to other rows is an `OutlineTable`
# (app/Sources/UIComponents/OutlineTable): SwiftUI's hierarchical controls make
# AppKit log "reentrant operation in its NSTableView delegate" on open-all and
# on an in-place re-sort. This check runs the headless probes for that
# (scripts/outline-probe.sh check: open all and re-sort, text and hosted cells,
# each in a fresh process, counting the warning), so a change to the component
# that makes it warn fails here.
#
# The second half refuses the SwiftUI controls in app/Sources. It is OFF
# (`OUTLINE_REFUSE_SWIFTUI_HIERARCHY=0`) because every existing screen still uses
# them; the LAST migration step, when the last screen has moved, sets it to 1.
OUTLINE_REFUSE_SWIFTUI_HIERARCHY=0
check_outline() {
  if [ "$(uname -s)" != "Darwin" ]; then DETAIL="skipped: not on macOS"; return 2; fi
  if [ ! -x scripts/outline-probe.sh ]; then DETAIL="skipped: no scripts/outline-probe.sh"; return 2; fi
  if ! command -v swift >/dev/null 2>&1; then DETAIL="skipped: swift is not installed"; return 2; fi
  if ! scripts/outline-probe.sh check >"$TMP/outline.out" 2>&1; then
    tail -n 25 "$TMP/outline.out" | cut -c1-300 >"$OUT"
    DETAIL="the outline probe failed or counted a reentrancy warning"
    return 1
  fi
  DETAIL="$(tail -n 1 "$TMP/outline.out")"
  if [ "$OUTLINE_REFUSE_SWIFTUI_HIERARCHY" = "1" ]; then
    local marker='// one disclosed block, not rows'
    # whole words only (OutlineTable( is not Table( ), outside the component, and never a comment line
    local comment='^[^:]+:[0-9]+:[[:space:]]*//'
    {
      grep -rnE '(^|[^A-Za-z])(DisclosureTableRow|OutlineGroup)([^A-Za-z]|$)|Section\(isExpanded:' --include='*.swift' app/Sources \
        | grep -v '^app/Sources/UIComponents/OutlineTable/' | grep -vE "$comment"
      grep -rnE '(^|[^A-Za-z])Table\(.*children:' --include='*.swift' app/Sources \
        | grep -v '^app/Sources/UIComponents/OutlineTable/' | grep -vE "$comment"
      grep -rn -B1 'DisclosureGroup' --include='*.swift' app/Sources \
        | grep -vE "$comment" \
        | awk -v marker="$marker" '
            /DisclosureGroup/ && !/^--$/ { line = $0; if (index(line, marker) == 0 && index(prev, marker) == 0) print line }
            { prev = $0 }'
    } >"$OUT" 2>/dev/null
    if [ -s "$OUT" ]; then
      DETAIL="SwiftUI hierarchical controls in app/Sources — use OutlineTable (a DisclosureGroup around ONE block of content carries: $marker)"
      return 1
    fi
    DETAIL="$DETAIL; no SwiftUI hierarchical control in app/Sources"
  else
    DETAIL="$DETAIL; the grep for SwiftUI hierarchical controls is off until the last migration step"
  fi
  return 0
}

check_app() {
  if [ "$(uname -s)" != "Darwin" ]; then DETAIL="skipped: not on macOS"; return 2; fi
  if [ ! -f app/Package.swift ]; then DETAIL="skipped: no app/Package.swift"; return 2; fi
  if ! command -v swift >/dev/null 2>&1; then
    DETAIL="swift is not installed"
    echo "install the Xcode command line tools:  xcode-select --install" >"$OUT"
    return 1
  fi
  local started=$SECONDS rc
  # --disable-keychain + an empty git credential helper: SwiftPM and git must
  # never ask the macOS keychain for a login (see app/build.sh).
  ( cd app && env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
      swift build --disable-keychain ) >"$TMP/app.out" 2>&1
  rc=$?
  # drop colour and terminal-hyperlink escapes so the output reads as text
  if command -v perl >/dev/null 2>&1; then
    perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\e]*\e\\//g' "$TMP/app.out" >"$TMP/app.txt"
  else
    cp "$TMP/app.out" "$TMP/app.txt"
  fi
  if [ "$rc" -ne 0 ]; then
    # compiler errors only, one per line, cut short (the failed-command dump is huge)
    grep -a -E '^[^ ].*: error: ' "$TMP/app.txt" | cut -c1-300 | awk '!seen[$0]++' | head -20 >"$OUT"
    [ -s "$OUT" ] || tail -n 15 "$TMP/app.txt" | cut -c1-300 >"$OUT"
    DETAIL="swift build failed (exit $rc)"
    return 1
  fi
  # A build that succeeds while printing a warning is not clean. The package
  # turns warnings into errors, but some diagnostics are not upgraded (found
  # 2026-11-11: "cannot use generic struct … was not imported by this file"
  # printed as a warning, exit 0). Any warning line fails the check. Only
  # files compiled in this run can warn, so a change is always covered.
  if grep -a -E '^[^ ].*: warning: ' "$TMP/app.txt" | cut -c1-300 | awk '!seen[$0]++' | head -20 >"$OUT" && [ -s "$OUT" ]; then
    DETAIL="swift build printed $(wc -l <"$OUT" | tr -d ' ') warning(s) — warnings are defects"
    return 1
  fi
  : >"$OUT"
  DETAIL="swift build ok, no warnings ($((SECONDS - started))s)"
  return 0
}

# ── argument parsing ────────────────────────────────────────────────────────
names=""
range=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --list)
      for n in $ALL; do printf '%-10s %s\n' "$n" "$(describe "$n")"; done
      exit 0 ;;
    --changed)
      [ $# -ge 2 ] || { echo "check.sh: --changed needs a range, e.g. origin/development..HEAD" >&2; exit 2; }
      range="$2"; shift ;;
    --changed=*) range="${1#--changed=}" ;;
    -*) echo "check.sh: unknown option $1 (see --help)" >&2; exit 2 ;;
    *)
      case " $ALL " in
        *" $1 "*) names="$names $1" ;;
        *) echo "check.sh: unknown check '$1' (see --list)" >&2; exit 2 ;;
      esac ;;
  esac
  shift
done
# ── selection ───────────────────────────────────────────────────────────────
# Names say WHICH checks belong to this run; --changed then keeps, of those,
# the ones whose inputs changed. A check outside the named set is not part of
# the run at all; one inside it that --changed left out is printed as not run.
scope="$ALL"
[ -n "$names" ] && scope="$names"
selected="$scope"
reason_unselected=""
if [ -n "$range" ]; then
  if git diff --name-only "$range" >"$TMP/changed" 2>"$TMP/changed.err"; then
    want_script=0; want_changelog=0; want_app=0
    while IFS= read -r f; do
      case "$f" in
        *.sh|*.command|scripts/*|.github/*|tests/*|*/tests/*) want_script=1 ;;
      esac
      case "$f" in CHANGELOG.md|VERSION) want_changelog=1 ;; esac
      case "$f" in app/*|scripts/outline-probe.sh) want_app=1 ;; esac
    done <"$TMP/changed"
    selected=""
    for n in $scope; do
      case "$n" in
        syntax|lint|tests|workflows) [ "$want_script" -eq 1 ] && selected="$selected $n" ;;
        changelog) [ "$want_changelog" -eq 1 ] && selected="$selected $n" ;;
        app|spi|env|snapshot|names|probes|outline) [ "$want_app" -eq 1 ] && selected="$selected $n" ;;
        secrets|strays) selected="$selected $n" ;;
      esac
    done
    echo "range $range: $(wc -l <"$TMP/changed" | tr -d ' ') file(s) changed"
    reason_unselected="nothing it checks changed in this range"
  else
    echo "check.sh: cannot read range '$range' ($(tr '\n' ' ' <"$TMP/changed.err")) — running every check instead" >&2
  fi
fi

# ── run ─────────────────────────────────────────────────────────────────────
passed=0; failed=0; skipped=0; failed_names=""
for n in $ALL; do
  # a check you did not ask for by name is not part of this run at all
  case " $scope " in *" $n "*) ;; *) continue ;; esac
  case " $selected " in
    *" $n "*) ;;
    *)
      printf '– %s — not run: %s\n' "$n" "$reason_unselected"
      skipped=$((skipped + 1))
      continue ;;
  esac
  : >"$OUT"
  DETAIL=""
  "check_$n"
  rc=$?
  case "$rc" in
    0) printf '✓ %s — %s\n' "$n" "$DETAIL"; passed=$((passed + 1)) ;;
    2) printf '– %s — %s\n' "$n" "$DETAIL"; skipped=$((skipped + 1)) ;;
    *) printf '✗ %s — %s\n' "$n" "$DETAIL"; failed=$((failed + 1)); failed_names="$failed_names $n" ;;
  esac
  if [ "$rc" -ne 2 ] && [ -s "$OUT" ]; then sed 's/^/    /' "$OUT"; fi
done

echo
if [ "$failed" -gt 0 ]; then
  echo "checks: FAILED —$failed_names ($passed passed, $skipped not run)"
  exit 1
fi
echo "checks: $passed passed, $skipped not run, 0 failed"
exit 0
