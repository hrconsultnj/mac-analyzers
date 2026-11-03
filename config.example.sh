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
# Any run: brew,pip,uv,cargo,gradle,deriveddata,bun,cipd
# Deep only: appcaches (every app's ~/Library/Caches folder, minus macOS's own,
#   the protect list and anything written in the last hour), gomod,
#   simulators (runtimes never booted, installed 7+ days ago), avd (Android
#   emulator quick-boot snapshots), aerials (wallpaper videos unseen 14 days).
# All redownloadable / rebuildable — never sources, never state.
# ANALYZERS_TOOL_CACHES="brew,uv,deriveddata"
#ANALYZERS_APPCACHE_KEEP="SomeApp|com\.vendor\..*"   # extra ~/Library/Caches names to keep (regex alts)

# Code projects (storage-auto-clean, under the roots — default ~/Projects).
#ANALYZERS_NM_AGE_DAYS=14          # node_modules of repos idle this many days (deep)
#ANALYZERS_NM_REQUIRE_CLEAN=1      # 0 = also when the git tree has uncommitted changes
#ANALYZERS_TURBO_CACHE_MAX_GB=2    # per-repo .turbo/cache cap, oldest entries go (every run)
# Finished git worktrees (deep): removed with `git worktree remove` once their
# work is ALREADY MERGED into the current checkout or a base branch (local or
# origin; squash/rebase merges count). The branch stays. Never: unmerged work,
# uncommitted or untracked files, ignored files that aren't build output (.env,
# local databases, keys), locked worktrees, one a terminal/agent session sits
# in. 0 = off.
#ANALYZERS_WORKTREE_IDLE_DAYS=0

# Downloads janitor (storage-analyzer/downloads-janitor.sh). Everything it
# moves goes to the Trash, never deleted, and is listed for review first.
# JANITOR_DOWNLOADS_AGE_DAYS=30      # top-level ~/Downloads items untouched this long
# JANITOR_SCREENSHOTS_AGE_DAYS=14    # screenshot FILES older than this (folders never move)
# JANITOR_KEEP_PATTERNS="*.dmg:Tax *"  # colon-separated globs that are never touched

# Temp & AI-agent cleaner (storage-analyzer/temp-clean.sh). Dry run by default;
# --apply moves to the Trash, --apply --permanent deletes. Nothing open, live,
# recent, or someone else's is ever touched.
# TEMP_CLEAN_MIN_AGE_HOURS=24        # /tmp, $TMPDIR and /var/tmp entries idle this long
# TEMP_CLEAN_AGENT_SCRATCH_DAYS=3    # Claude Code / Codex scratch idle this long
# TEMP_CLEAN_NPX_DAYS=14             # npx-run tools / MCP servers unused this long
# TEMP_CLEAN_KEEP_PATTERNS="*.iso:my-build-*"   # colon-separated globs never touched
# Extra AI-agent folders to SIZE (never cleaned) — e.g. a session archive.
# Colon-separated.
#ANALYZERS_AGENT_DIRS="$HOME/.my-agent/sessions:$HOME/.other-agent/history"

# Dev pass (memory-auto-clean.sh --dev — memory-guard.sh runs it every
# GUARD_DEV_SWEEP_SECS). Stops dev tooling that has gone IDLE: no client
# connected, no CPU activity, no build/test/driver using it. Busy tooling is
# never touched. Started something with nohup that must stay up? Add it to
# ANALYZERS_PROTECT_EXTRA.
#GUARD_DEV_SWEEP_SECS=120              # 0 = the guard never runs the dev pass
#ANALYZERS_DEV_DEVICE_IDLE_MIN=20      # emulators / simulators (x2 for a windowed emulator)
#ANALYZERS_DEV_DAEMON_IDLE_MIN=5       # Gradle / Kotlin daemons, only while no Gradle build runs
#ANALYZERS_DEV_SERVER_IDLE_MIN=30      # dev servers whose project is open in a session or terminal
#ANALYZERS_DEV_ORPHAN_IDLE_MIN=3       # orphaned dev tools, and dev servers of closed projects
#ANALYZERS_DEV_REAP_SESSION_SERVERS=0  # 1 = also idle dev servers an AI session left running
#ANALYZERS_ADB=""                      # adb, if not on PATH or inside the emulator's own SDK

# Dev pass, section 11 — stop the Docker/Supabase stacks of projects you are NOT working on.
# Opt-in: a stack is stopped (`docker stop`, one container at a time; nothing is removed,
# volumes are never touched, Docker itself is never signalled) once its project has had no
# live claude/codex session for ANALYZERS_STACK_IDLE_MIN. A session working in a git worktree
# counts as its repo. Only stacks that map to a project are ever stopped; a stack that maps to
# nothing (OrbStack's own Kubernetes containers included) is reported and kept. Mapping:
# a Supabase stack by its project_id in a repo's supabase/config.toml (repos of live sessions,
# then repos under ANALYZERS_STACK_REPO_ROOTS), a Compose stack by its working_dir, else the
# owner map below. The first sighting of an orphaned stack is remembered in
# reports/memory/.stack-idle-state. Preview with: memory-auto-clean.sh --dev (dry run).
#ANALYZERS_DEV_STOP_IDLE_STACKS=0      # 1 = enable
#ANALYZERS_STACK_IDLE_MIN=30           # minutes a project must have had no live session
#ANALYZERS_STACK_PROTECT="my-project other-*"   # stack ids / project names never stopped (globs; space or comma separated). Always wins.
#ANALYZERS_STACK_OWNER_MAP="scratch-*=my-project"  # glob=project entries for stacks no repo config names; an entry wins over automatic mapping. A project is a repo folder name or its full path.
#ANALYZERS_STACK_REPO_ROOTS="$HOME/Projects"        # where to look for repos of stacks with no live session (searched 3 levels down)
