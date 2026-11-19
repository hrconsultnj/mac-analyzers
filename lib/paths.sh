# shellcheck shell=bash
# Data root and engine root for the suite. Sourced, never executed.
# An existing ~/mac-analyzers checkout is left where it is. Nothing here moves or deletes it.
#
# Data root, first match:
#   $SPAREHOLD_DATA_DIR, else $SPAREHOLD_DIR, else $MAC_ANALYZERS_DIR,
#   else ~/sparehold when it holds config.local.sh, reports/ or .git,
#   else ~/mac-analyzers when it holds one of those,
#   else ~/Library/Application Support/Sparehold.
# Engine root: $SPAREHOLD_SUITE_DIR, else ~/sparehold when the engine scripts
# are there, else ~/mac-analyzers when they are, else empty (the caller uses
# the bundle).

sparehold_has_data() {
  local dir="$1"
  [[ -f "$dir/config.local.sh" || -d "$dir/reports" || -e "$dir/.git" ]]
}

sparehold_has_engine() {
  local dir="$1"
  [[ -x "$dir/memory-analyzer/memory-guard.sh" ]]
}

sparehold_user_root() {
  if [[ -n "${SPAREHOLD_DATA_DIR:-}" ]]; then
    printf '%s\n' "$SPAREHOLD_DATA_DIR"
    return 0
  fi
  if [[ -n "${SPAREHOLD_DIR:-}" ]]; then
    printf '%s\n' "$SPAREHOLD_DIR"
    return 0
  fi
  if [[ -n "${MAC_ANALYZERS_DIR:-}" ]]; then
    printf '%s\n' "$MAC_ANALYZERS_DIR"
    return 0
  fi
  local home="${HOME}"
  if sparehold_has_data "$home/sparehold"; then
    printf '%s\n' "$home/sparehold"
    return 0
  fi
  if sparehold_has_data "$home/mac-analyzers"; then
    printf '%s\n' "$home/mac-analyzers"
    return 0
  fi
  printf '%s\n' "$home/Library/Application Support/Sparehold"
}

# Prints the engine root, or nothing when only the app bundle has the scripts.
sparehold_suite_root() {
  if [[ -n "${SPAREHOLD_SUITE_DIR:-}" ]]; then
    printf '%s\n' "$SPAREHOLD_SUITE_DIR"
    return 0
  fi
  local home="${HOME}"
  if sparehold_has_engine "$home/sparehold"; then
    printf '%s\n' "$home/sparehold"
    return 0
  fi
  if sparehold_has_engine "$home/mac-analyzers"; then
    printf '%s\n' "$home/mac-analyzers"
    return 0
  fi
  return 0
}

# Sets SPAREHOLD_USER_ROOT and sources the user config when it is a different
# file from the suite copy already sourced via ANALYZERS_ROOT.
sparehold_apply_paths() {
  SPAREHOLD_USER_ROOT="$(sparehold_user_root)"
  local cfg="${SPAREHOLD_USER_ROOT}/config.local.sh"
  [[ -f "$cfg" ]] || return 0
  if [[ -n "${ANALYZERS_ROOT:-}" && "${ANALYZERS_ROOT}" == "${SPAREHOLD_USER_ROOT}" ]]; then
    return 0
  fi
  # The path is the data root chosen at runtime, so shellcheck cannot follow it.
  # shellcheck disable=SC1090
  source "$cfg"
}
