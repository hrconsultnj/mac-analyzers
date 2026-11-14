#!/usr/bin/env bash
# tree-hash.sh <repo> — "clean" when the working tree has nothing uncommitted, else a SHA-256 of what is
# uncommitted: the diff against HEAD, then every untracked file as <name> NUL <size> NUL <bytes>.
# Exits non-zero (and prints nothing) when git cannot answer or the clone cannot be read safely: a failure
# is never "clean", and `app/build.sh` then stamps "unknown".
#
# app/build.sh stamps this into the app (MABuildTreeHash) and the app recomputes the same value from the
# clone (SourceClone.fingerprint), so "This Copy" can tell a build made from exactly this working tree from
# one that is not, including an edit to a new file that is not added to git yet. The two MUST stay
# byte-identical: `agent-runner --probe-channels` compares them on awkward cases.
#
# Reading a repository must not run what the repository names, so git is called exactly as the app calls it
# (SourceClone: safeArguments, fixedSettings, environment): fsmonitor, hooks and attributes switched off, the
# empty tree as the attribute source, no external diff or text filter, no lazy fetch, the person's global
# and system configuration not read, a minimal environment, and every filter and diff driver the clone
# defines emptied. The settings go through GIT_CONFIG_COUNT/KEY/VALUE (a driver name may contain "=", which
# `-c` cannot carry). Submodules are never entered (`--ignore-submodules=dirty`), and a clone with a submodule
# (dirty or not), or a non-empty `info/attributes` (the one place left that can pick a driver), is
# unknown. The diff is pinned so no setting changes its bytes.
set -euo pipefail
cd "${1:?usage: tree-hash.sh <repo>}"

# base <settings as KEY=VALUE lines on stdin-less args...> : git with the settings given as separate pairs
run_git() {
  local settings="$1"; shift
  local env_pairs=(PATH=/usr/bin:/bin HOME="$HOME" LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    GIT_ATTR_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_NO_LAZY_FETCH=1)
  local count=0 line key value
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%$'\t'*}"; value="${line#*$'\t'}"
    env_pairs+=("GIT_CONFIG_KEY_$count=$key" "GIT_CONFIG_VALUE_$count=$value")
    count=$((count + 1))
  done <<<"$settings"
  env -i "${env_pairs[@]}" "GIT_CONFIG_COUNT=$count" /usr/bin/git \
    --no-optional-locks --no-pager --attr-source=4b825dc642cb6eb9a060e54bf8d69288fbee4904 "$@"
}

fixed=$'core.fsmonitor\tfalse\ncore.useBuiltinFSMonitor\tfalse\ncore.hooksPath\t/dev/null\ncore.attributesFile\t/dev/null\ncore.quotepath\toff'

# the only attribute source left once --attr-source, core.attributesFile and GIT_ATTR_NOSYSTEM are set
attributes="$(run_git "$fixed" rev-parse --path-format=absolute --git-path info/attributes)"
if [[ -s "$attributes" ]]; then exit 1; fi
# a gitlink (a submodule), dirty or not: git is never run inside one, so work inside it cannot be seen
staged="$(run_git "$fixed" ls-files --stage -z | tr '\0' '\n')"
if grep -q '^160000 ' <<<"$staged"; then exit 1; fi

# belt and braces: every driver the clone's configuration defines is emptied too
settings="$fixed"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  case "$key" in
    *.required) settings+=$'\n'"$key"$'\tfalse' ;;
    *) settings+=$'\n'"$key"$'\t' ;;
  esac
done < <(run_git "$fixed" config --name-only --get-regexp '^(filter|diff)\..*\.(clean|smudge|process|textconv|command|required)$' || true)
g() { run_git "$settings" "$@"; }

# --untracked-files=normal: a setting that hides new files cannot hide work; --ignore-submodules=dirty: git
# never runs inside a submodule
status="$(g status --porcelain=v1 -z --untracked-files=normal --ignore-submodules=dirty | wc -c | tr -d ' ')"
if [[ "$status" == "0" ]]; then
  echo clean
  exit 0
fi
# The hash is taken first and printed only if every part succeeded: a failure prints nothing. (A command
# substitution does not stop at a failing command by itself, so each part says `|| exit 1`.)
hash="$({
  g diff HEAD --no-ext-diff --no-textconv --no-color --no-renames --ignore-submodules=dirty \
    --diff-algorithm=myers --no-indent-heuristic --src-prefix=a/ --dst-prefix=b/ --unified=3 || exit 1
  g ls-files -z --others --exclude-standard | while IFS= read -r -d '' name; do
    size=0
    if [[ -f "$name" ]]; then size="$(wc -c < "$name" | tr -d ' ')"; fi
    printf '%s\0%s\0' "$name" "$size"
    if [[ -f "$name" ]]; then cat -- "$name"; fi
  done || exit 1
} | shasum -a 256 | cut -d' ' -f1)"
echo "$hash"
