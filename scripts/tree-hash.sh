#!/usr/bin/env bash
# tree-hash.sh <repo> — "clean" when the working tree has nothing uncommitted, else a SHA-256 of what is
# uncommitted: the diff against HEAD, then every untracked file as <name> NUL <size> NUL <bytes>.
# Exits non-zero (and prints nothing) when git cannot answer: a failure is never "clean".
#
# app/build.sh stamps this into the app (MABuildTreeHash) and the app recomputes the same value from the
# clone (SourceClone.fingerprint), so "This Copy" can tell a build made from exactly this working tree from
# one that is not, including an edit to a new file that is not added to git yet. The two MUST stay
# byte-identical: `agent-runner --probe-channels` compares them on awkward cases.
#
# Reading a repository must not run what the repository names, so git is called exactly as the app calls it
# (SourceClone.safeArguments / .environment): fsmonitor, hooks and attributes switched off, the empty tree as
# the attribute source, no external diff or text filter, the person's global and system configuration not
# read, and a minimal environment. The diff is pinned so no setting changes its bytes.
set -euo pipefail
cd "${1:?usage: tree-hash.sh <repo>}"

base() {
  env -i PATH=/usr/bin:/bin HOME="$HOME" LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_ATTR_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 /usr/bin/git \
    --no-optional-locks --no-pager --attr-source=4b825dc642cb6eb9a060e54bf8d69288fbee4904 \
    -c core.fsmonitor=false -c core.useBuiltinFSMonitor=false -c core.hooksPath=/dev/null \
    -c core.attributesFile=/dev/null "$@"
}
# every filter and diff driver the clone defines is emptied (`.git/info/attributes` can still pick one): see
# SourceClone.driverOverrides
overrides=()
while IFS= read -r key; do
  case "$key" in
    *.required) overrides+=(-c "$key=false") ;;
    *) overrides+=(-c "$key=") ;;
  esac
done < <(base config --name-only --get-regexp '^(filter|diff)\..*\.(clean|smudge|process|textconv|command|required)$' || true)
g() { base ${overrides[@]+"${overrides[@]}"} "$@"; }

# --untracked-files=normal --ignore-submodules=none: a setting that hides new files or submodules cannot hide work
status="$(g status --porcelain=v1 -z --untracked-files=normal --ignore-submodules=none | wc -c | tr -d ' ')"
if [[ "$status" == "0" ]]; then
  echo clean
  exit 0
fi
{
  g -c core.quotepath=off diff HEAD --no-ext-diff --no-textconv --no-color --no-renames \
    --diff-algorithm=myers --no-indent-heuristic --src-prefix=a/ --dst-prefix=b/ --unified=3
  g ls-files -z --others --exclude-standard | while IFS= read -r -d '' name; do
    size=0
    if [[ -f "$name" ]]; then size="$(wc -c < "$name" | tr -d ' ')"; fi
    printf '%s\0%s\0' "$name" "$size"
    if [[ -f "$name" ]]; then cat -- "$name"; fi
  done
} | shasum -a 256 | cut -d' ' -f1
