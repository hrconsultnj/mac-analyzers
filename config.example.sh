# shellcheck shell=bash
# mac-analyzers — local configuration
# ---------------------------------------------------------------------------
# Copy to config.local.sh (same directory, gitignored) and edit. Every value
# is optional — the suite runs with safe neutral defaults without it.
# All scripts source config.local.sh from the repo root if present.
# ---------------------------------------------------------------------------

# Extra never-kill processes (regex alternatives appended to the guard/reaper/
# reclaim protect list). Put YOUR meeting apps, recorders, home-automation
# daemons, anything that must survive every sweep.
#ANALYZERS_PROTECT_EXTRA='my-home-automation-daemon|obs'

# Apps memory-reclaim.sh quits gracefully with --apps (comma-separated).
#ANALYZERS_RECLAIM_APPS='Opera,Google Chrome,Visual Studio Code,ChatGPT,Docker'

# Extra regex identifying YOUR MCP/agent-server processes beyond the generic
# [Mm]cp match (e.g. a plugin directory that hosts stdio servers).
#ANALYZERS_MCP_EXTRA_RE='\.my-plugin-dir/servers'

# Apps you consider abandoned — cleanup.sh --stale-apps offers to remove each
# (bundle + all its data), asking per app. Names as they appear in /Applications
# without ".app".
#ANALYZERS_STALE_APPS=( "Some Old App" "Another One" )

# Leftover FILE/DIR paths of apps you already deleted — cleanup.sh reclaims
# these in its main pass (App Support dirs, caches, prefs of uninstalled apps).
#ANALYZERS_DEPRECATED_PATHS=( "$HOME/Library/Application Support/DeadApp" )

# Directory holding dated recording folders (dictation audio etc.) —
# cleanup.sh --recordings-older-than N prunes subfolders older than N days.
# Empty/unset disables the feature.
#ANALYZERS_RECORDINGS_DIR="$HOME/my-dictation-app/recordings"

# Extra cache directory GLOBS for the scheduled storage auto-clean (removed
# only when not written for >7 days). For app-generated per-project caches.
#ANALYZERS_EXTRA_CACHE_GLOBS=( "$HOME/.someapp/cache/.next-*" )

# Roots spotlight-audit.sh scans for dev directories (node_modules, .next,
# build trees) that Spotlight wastefully indexes. Space-separated.
#ANALYZERS_SPOTLIGHT_ROOTS="$HOME/Projects $HOME/Work"

# Tool-cache expansion pack (storage-auto-clean): comma list of opt-in ids.
# Available: brew,pip,uv,cargo,gradle,deriveddata — all redownloadable cache.
# ANALYZERS_TOOL_CACHES="brew,uv,deriveddata"

# Downloads janitor (storage-analyzer/downloads-janitor.sh). Everything it
# moves goes to the Trash, never deleted, and is listed for review first.
# JANITOR_DOWNLOADS_AGE_DAYS=30      # top-level ~/Downloads items untouched this long
# JANITOR_SCREENSHOTS_AGE_DAYS=14    # screenshot FILES older than this (folders never move)
# JANITOR_KEEP_PATTERNS="*.dmg:Tax *"  # colon-separated globs that are never touched
