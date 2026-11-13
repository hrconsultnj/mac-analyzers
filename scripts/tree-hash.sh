#!/usr/bin/env bash
# tree-hash.sh <repo> — "clean" when the working tree has nothing uncommitted, else a SHA-256 of what is
# uncommitted: the diff against HEAD, then every untracked file as <name> NUL <size> NUL <bytes>.
#
# app/build.sh stamps this into the app (MABuildTreeHash) and the app recomputes the same value from the
# clone (SourceClone.fingerprint), so "This Copy" can tell a build made from exactly this working tree from
# one that is not, including an edit to a new file that is not added to git yet. The two MUST stay
# byte-identical: `agent-runner --probe-channels` compares them on awkward cases.
#
# The diff is pinned so the person's git configuration cannot change its bytes (an external diff tool, a
# text filter, colour, another algorithm, a path quoting style).
set -euo pipefail
cd "${1:?usage: tree-hash.sh <repo>}"

if [[ -z "$(git --no-optional-locks status --porcelain 2>/dev/null)" ]]; then
  echo clean
  exit 0
fi
{
  git --no-optional-locks -c core.quotepath=off diff HEAD --no-ext-diff --no-textconv --no-color --no-renames \
    --diff-algorithm=myers --no-indent-heuristic --src-prefix=a/ --dst-prefix=b/ --unified=3
  git --no-optional-locks ls-files -z --others --exclude-standard | while IFS= read -r -d '' name; do
    size=0
    [[ -f "$name" ]] && size="$(wc -c < "$name" | tr -d ' ')"
    printf '%s\0%s\0' "$name" "$size"
    [[ -f "$name" ]] && cat -- "$name"
  done
} | shasum -a 256 | cut -d' ' -f1
