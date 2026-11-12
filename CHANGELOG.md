# What's New

Every release of Mac Analyzers, newest first, written for the people who use
it. This file is the single source for release notes: the app's Update screen
shows it, and each GitHub release publishes its entry. A release cannot ship
without an entry here — see `scripts/cut-release.sh`.

## Next

- Caches & Builds, Downloads and Temp & Agents are rebuilt. Each is one screen:
  Preview in the toolbar, then what it found as tabs for the kinds of thing
  (Projects, App Caches and Developer Tools; documents, images and
  screenshots; temporary files and your coding agents' folders), grouped under
  the project, app or agent they belong to, with a count and a total on every
  group. Tick what to clear, then Apply. The banner and the list of log lines
  are gone, and every earlier run is one click away under History.
- A cleanup's setting now belongs to its preview. When you come back to a
  Deep Caches & Builds preview, or a Temp & Agents preview made with Delete
  Permanently, the screen shows that setting, asks the matching question
  and applies exactly that; changing the menu puts the preview away. Deleting
  Time Machine's local snapshots is now a row you can see and untick, instead
  of something a Deep Apply did on its own. Every screen also says, first in
  its subtitle, whether what is cleared goes to the Trash or is deleted for good.
- A finished Caches & Builds cleanup says what each package cleanup, Docker
  and the snapshot deletion did: ran, skipped because it wasn't ticked, or
  couldn't run.
- Temp & Agents names what it finds ("codemod", "Session Transcripts") and says
  why anything is left alone: "Left for Its Owner", "Conversation History",
  "On Your Keep List". It also says what is not on your disk (files inside
  mounted disk images) and which coding agents are running.
- Files that exist only in iCloud (a screenshot or document that macOS keeps in
  the cloud and has not downloaded to this Mac) are no longer shown as empty
  files under "Nothing to Free", and no cleanup moves them any more, not even
  the scheduled one. Moving one to the Trash frees nothing on this Mac, and
  once the Trash is emptied it is gone from iCloud and from your other
  devices. They are listed under "Only in iCloud" with their real size, and the
  run's summary says how many were left.
- Time Machine is a screen of its own under Storage. It lists the local
  snapshots on this Mac by day, which hold space you have freed, and "Delete
  Snapshots…" deletes them after you confirm, which releases that space. The
  confirmation says they can't be brought back and whether your backup disk is
  connected right now, because while it is away they can be the only copies of
  your latest changes. Backups on the Time Machine disk are never touched, and a
  new backup can start afterwards. Deleting snapshots needs a one-time
  permission for exactly one command; the screen offers "Allow…", which shows the
  standard macOS administrator prompt and says that afterwards any program on
  your account can do that without asking. "Remove Permission…" in the Options
  menu takes it away again; each account on the Mac has its own permission.
  In Terminal, `tm-reclaim.sh` now looks first and only acts with `--apply`.
- Two new screens under Storage. Unused Apps finds the apps you have not
  opened for six months or more, grouped by how long ago, each with what goes
  with it: its Application Support, caches and preferences. Tick the apps to
  remove and they go to the Trash with their files, so Undo can bring them
  back; each app opens to every file that goes with it, with its size, and the
  confirmation names every app. Only files that belong to the app by its own
  identity are taken: a folder that merely carries its name (Electron) or a
  group container another app shares is shown and left in place. An app that
  macOS has no record of, that runs in the background (a login item, launch
  agent, helper or system extension, a menu-bar tool, or something started
  through `open`), that is running, that has other apps inside it, or that
  you cannot move without an administrator is listed but never offered. Which
  apps open at login is read from the Login & Startup Items check, so it must
  have run today; if the app cannot be moved, none of its files are touched. In Terminal, `cleanup.sh --stale-apps
  --execute` only removes a list you wrote yourself; apps found by their date
  are removed only from a review in the app. Old Recordings lists recording
  folders older than 90 days by the month they were made; they go to the Trash
  too, so Undo can bring them back.
- Spotlight lists your developer folders by project with a checkbox to fence
  or unfence each one, and Fence and Unfence for a whole selection. Fence All
  names the folders it will fence and fences exactly those, not whatever a new
  scan would find. A fence is one empty file, and nothing else is changed.
- Disk shows your capacity, how long the free space will last at the rate it
  has been falling, and what each cleanup could free and how old that figure
  is. The "full in" forecast never appeared before; it now reads every
  Caches & Builds run's figure, not only the newest few. When there is no
  forecast it says why, and after a sharp fall in free space it says what
  happened instead of predicting. A nearly full disk is shown in red.
- A finished cleanup's own screen shows what it did in the same tabs and groups
  as the screen it came from.
- When a memory cleanup refuses to run because part of Mac Analyzers is
  missing, the app now says so and tells you to update or reinstall. It used
  to tell you to check your protected-apps list, which had nothing to do
  with it.
- Buttons, filters and the search field on the screens that were not already
  being rebuilt now have the standard Mac size and spacing.
- The version at the bottom of the sidebar looks the same whether you are up
  to date, on a development build or have an update waiting.
- Activity's tabs (All, Running, Needs Review, Failed) show an icon beside
  each name and a count, and you can choose them with Command-1 to Command-4.
  The Go menu's jumps to Overview, Activity, Monitor and Disk are now
  Control-Command-1 to Control-Command-4.
- On Activity, the search field shrinks to its icon when the window gets
  narrow instead of being cut off, and clicking a run or a tab lets go of it.
  While another screen is showing, a job that has just finished appears in the
  toolbar as the task's name with a tick or a warning; hover over it for the
  full sentence.
- A run's raw output now opens inside the app, starting at the newest line,
  with search and Copy. A finished run's screen groups its results under tabs
  (what was freed, what was found) and, inside each, under the project they
  belong to, instead of one long list.
- Overview is now a grid of boxes: Memory, Storage, Memory Guard, Schedule,
  Recent Events and This Week. Each row opens the screen behind it (an app or
  tool opens Monitor with that row selected), and a Needs Attention list at
  the top appears only when something needs you.
- Trends has two tabs, Memory and Storage, and a period menu in the toolbar.
  Storage now adds up everything the cleanups removed in the period, under
  "Removed by Cleanups", instead of reading 0 KB, and each number opens a
  table of what is behind it.
- Undo is grouped by day and by cleanup. Restore puts an item back only when
  it is still the one that was moved to the Trash, and says why when it
  cannot. A second tab lists the dev servers the guard stopped.
- Putting items back from Undo now shows up in Activity as its own entry,
  "Restored 3 Items", started by you, with the list of what came back. It no
  longer gets mixed into the cleanup it came from, so that cleanup's numbers,
  and a preview that is waiting for your review, stay exactly as they were.
- The menu-bar panel uses standard controls, so nothing is cut off, and its
  process list matches Monitor. Its Quit and Stop follow the same rules as
  Monitor, and a program that does not stop is never forced from the panel: it
  offers to open Monitor on that program instead.
- Login & Startup Items, Network and Reports have been rebuilt as screens you
  can read at a glance instead of lists of lines.
- Login & Startup Items has a tab for Apps that open when you log in,
  Background Items that work for them, Leftovers from apps you removed, and
  Changes (what was added to startup, day by day). Each app or developer is one row that opens to its
  items, with whether they are running and what the audit found. Select one to
  see where it lives, what it runs and why it was flagged. A leftover in your
  own folders, or an app set to open at login whose app is gone, can be
  removed from here; the ones that need an administrator show the exact
  command to copy. An item whose program is on a drive that is
  not connected is no longer called a leftover.
- Network shows the newest snapshot with each app's programs gathered into one
  row that opens, and keeps your recent snapshots (the last 60) in a History tab you can
  open.
- Reports has a tab for memory reports and one for storage reports, each
  listing the reports by month. A report opens as a document, divided into
  sections you can fold, instead of one long block of text. You can write a
  new report, stop it, export a copy, or see its text exactly as written.
- Monitor is now one table that fills the window: every app and tool with its
  memory and processor use, the parts of each app, and a details panel. Open a
  command-line tool such as Node.js and you see each separate program in its
  own row, labelled by the project it runs in. Stopping a tool now stops only
  the programs you choose, in a list you confirm, and never a live coding-agent
  session or a program that has changed since you looked at it.
- Memory Guard reads as a history: a section for each day, and a row for each
  thing the guard stopped or flagged, named for the app or tool ("Stopped Vite
  dev server", "9 processor alerts for Media Analysis") with what the guard did
  about it. Repeats are folded into one row. Click a row to see what happened,
  what the program was, and why the guard acts — and for a memory crisis, which
  apps were using the memory.
- Memory Cleanup is a screen of its own. Preview shows what a cleanup would
  close in tabs (dev servers, orphaned tools, emulators and browsers, and the
  helpers of coding sessions), grouped by the program they belong to, and you
  tick what to close. Apps on your list to quit are shown as "will quit"
  before you apply, and a cleanup closes only the programs you saw, as they
  were when you looked: a program that has been replaced since is left alone.
- Stop now asks a program politely first. If it does not stop, you are
  offered a separate Force Stop, and nothing is forced until you confirm it.
- The Stop button in a notification now checks that it is still the same
  program before it does anything. If the program has changed, or is part of a
  live coding session, Monitor opens on it instead and nothing is stopped.
- An app that hosts a live coding session, such as a terminal with Claude
  running in it, is never quit by Everything Now, and Quit on such an app
  tells you which sessions would end with it.
- If the list of coding agents cannot be read, Mac Analyzers offers no Stop at
  all and says why, rather than guessing which programs are sessions.
- If Mac Analyzers cannot yet tell what a program really is, because its
  command line cannot be read or still shows the program that started it, Stop
  does nothing and says "could not tell, so nothing was stopped"; try again in
  a moment. Quit says so in its confirmation; if you confirm, the app is
  asked to quit as usual.

## v2.69.2 — Process rows no longer show a program's environment

- A process row could show part of a program's environment after its name,
  and an environment can hold a password or an API key. It happened for
  programs that rename themselves while they run, such as a Next.js
  development server, on Overview's "Biggest Processes Right Now", in Monitor
  and in the menu-bar panel. Rows now read a program's arguments the way
  Terminal's `ps` does. This was text on your own screen: the app did not
  save it to a log or send it anywhere. If a key of yours was on screen while
  someone else could see it, or in a screenshot you shared, replace that key.
- Anything on a row written as `NAME=value` now shows its name only, never
  its value. That also covers the one case where macOS itself hands back
  environment entries as arguments (a program that gives itself a very long
  name), where the names can still appear.
- A row also hides the value of an argument that is plainly a credential,
  such as `--token abc` or a password inside a web address. It cannot
  recognise every way a secret may be passed to a program, so a command line
  is still not a safe place for one.
- Programs that rename themselves are now named and grouped by that name
  alone.

## v2.69.1 — Large Downloads reviews can be applied again

- Reviews of very large cleanups can be applied again. If your Downloads
  folder holds thousands of old files, the review used to say it couldn't find
  the results of its own preview and refused to apply; it now reads the whole
  preview, so you can untick what you want to keep and clear the rest.
- A cleanup now touches only the items that were in the review you approved,
  even if new ones appeared since. A review can also be applied only once.
- The package-manager and tool cleanups in a deep Caches & Builds cleanup
  (pnpm, npm, Homebrew, simulators, Docker) are now part of what you review,
  and they run only when you approved them.
- Memory Cleanup's count now matches what Apply closes.
- The Caches & Builds review says which package-manager and Docker cleanups run
  with it, and that they are skipped as soon as you untick a row; the log
  screen lists them too.
- Cleaning thousands of files no longer slows down when you untick some of
  them, and a file in Downloads whose name contains a line break no longer
  stops a cleanup: it is left alone and the cleanup says so.
- Two files with the same name cleaned up at the same moment are both kept in
  the Trash. Before, the second could replace the first.
- Activity no longer loses a log for a while when its recent part happens to
  start in the middle of an accented character.

## v2.69.0 — A new main window, and cleanups you can watch, stop and look back on

Mac Analyzers has a new main window. The sidebar is organised by what you
want to look at — Memory, Storage, System, History — and can be hidden. Back
and Forward remember everywhere you have been, across sections (Command-[ and
Command-]), a Go menu jumps straight to Overview, Activity, Monitor and Disk,
and the window reopens where you left it. Each cleanup now lives with the
thing it cleans: Caches & Builds, Downloads, Temp & Agents and Memory Cleanup
each have their own review.

Cleanups and checks now run in the background with live progress. You can
close the window, watch them from the menu bar and stop them at any time.
The new Activity screen lists everything that ran, day by day, whether you or
the schedule started it, with what each run freed or found; click a run to
open a page that says what it did. A preview you can still apply is marked as
waiting for your review, and older previews stay in the list as what they
found, with a button to preview again.

- When a cleanup or check finishes while the window is closed or not in
  front, a notification tells you how it went and opens that run.
- A cleanup that cannot record which items you approved now stops instead of
  acting on everything. A review you left open for more than fifteen minutes,
  or discarded, can no longer be applied; you are asked to preview again.
- If you quit Mac Analyzers while a cleanup or check is running, it asks
  whether to stop it or let it finish in the background. Restarting or
  logging out with something running simply stops it, and installing an
  update waits until it is done.
- Names and capitalization are consistent everywhere: the sidebar, Activity,
  the menu-bar panel, buttons, headings and notifications call each thing by
  the same Mac-style name, and the version you are running is back at the
  foot of the sidebar, with whether an update is waiting.
- What's New is easier to read, and older releases can be opened as well as
  the newest. A copy built between releases says so — it is marked as a Dev
  Build, and What's New opens with what is in it and not yet released.
- Mac Analyzers keeps all of its records in your mac-analyzers folder, so
  nothing is lost when the app updates. Cleanups started from the app now
  find the same developer tools your scheduled cleanups use.
- Building the app from source no longer asks for access to your keychain,
  and an update no longer fills the Terminal window with build output.

Fixed: updating Mac Analyzers could fail to restart the memory guard and show
"Bootstrap failed: 5: Input/output error", leaving the guard switched off, or
running its previous settings, until you next logged in. Updating and Setup
now wait for the old copy to stop before starting the new one, and say
plainly if a background job could not be started.

Fixed: changing a schedule could fail to take effect until you next logged
in. Apply Schedule now waits for the old schedule to stop, no longer freezes
the window while it works, and says which background job could not be
changed, and why.

Fixed: reinstalling or upgrading the app left behind files that newer
versions no longer include, which could stop macOS from verifying the
installed copy. Installing now replaces the app cleanly.

Fixed: when a cleanup moved several items with the same name to the Trash in
the same second, a later one could take the place of an earlier one. Each now
gets its own name.

Fixed: web-page processes belonging to Safari and other apps were listed
under the name "com" in the menu-bar process list.

## v2.68.1 — Memory cleanup works on every Mac again

This release fixes two problems in version 2.68.0 that stopped cleanups
from running. Nothing else changes.

- Fixed: Memory Cleanup's "See what would be cleaned" button failed on every
  Mac, and the scheduled memory cleanup stopped before doing anything on
  Macs that only have the version of bash that comes with macOS — which is
  every Mac without Homebrew. Both now run everywhere. The checks for idle
  developer tools need a newer bash and say so when one is not installed.
- Fixed: a cleanup or audit started from the app could wait forever when it
  had a lot to report — most often the Temp & Agents audit and the deep
  storage preview on a Mac with many projects. They now finish however much
  they find.

## v2.68.0 — See where all of your memory goes

The Monitor screen now accounts for every running process instead of only
the biggest few. Open it to see how much memory is in use and what that
figure is made of: app memory, memory macOS reserves for itself, compressed
memory, and cached files that are handed back the moment an app needs room.

Underneath, every process is grouped under the app or service it belongs to,
with a total per group. A browser and its dozens of helper processes read as
one line; so do the hundreds of small macOS services that are easy to miss
one by one but add up to gigabytes together. Filter by Apps, Command-line
and developer tools, or macOS, and search by name.

Each app is one line you can act on. It says what the app is made of —
"8 tabs and pages, 2 extensions, 3 for graphics" — and has a single Quit
that closes the app together with every helper it started, after asking
first. Open the line to see those parts with a total for each, and open a
part to reach the individual processes.

- Web views, graphics helpers and Open/Save dialogs are filed under the app
  that is using them, the way Activity Monitor does it.
- Common macOS services say in plain words what they are for.
- Sizes under a gigabyte are shown in megabytes instead of rounding to zero.
- Quit is no longer offered for macOS's own processes, where it could log
  you out or do nothing at all.

Fixed: the Monitor, the menu-bar process list and the Energy and Disk
activity views were only looking at about a quarter of the running
processes on a busy Mac. They now see all of them.

## v2.67.0 — Idle developer tools give their memory back on their own

Mac Analyzers can now free memory held by developer tools nobody is using:
emulators and simulators that are not being driven, build daemons while no
build is running, leftovers of failed builds, and development servers with
nothing connected to them. Anything still in use is left alone, and running
AI coding sessions keep their protection.

Two further clean-ups are available, both off until you turn them on:

- Local Docker and Supabase stacks are stopped when nobody is working in
  their project — no coding session and no open terminal there. They are
  only stopped, never removed, and your data stays where it is.
- Git worktrees that have sat idle are removed by the deep storage clean.
  Committed work stays on its branch, and unfinished changes are saved
  first, with the exact command to bring them back written to the log.

Fixed: a development server that had gone idle could be reported as closed
while it was still running. "Free my memory now" could stop tools belonging
to an active Claude Code session. Clearing old recordings also cleared
build caches that running projects were still using.

## v2.66.0 — See what really fills /tmp, /var and your AI tools' folders, and clear it safely

A new Temp & Agents screen (Logs › Temp & Agents, or the menu bar's Storage
tab) shows what your temporary folders and AI coding tools are holding.
Disk images mounted inside /tmp are told apart from real disk use — they
can make a plain size check report twice the truth — and each one can be
ejected right there. Every item says why it is ready to clear, or why it is
left alone: open right now, changed recently, part of a live Claude Code
session, or someone else's.

Clearing goes through Actions › Temp & Agents, like every other cleaner:
preview, untick anything you want kept, then move it to the Trash —
restorable from Undo — or, if you choose, delete it permanently after a
second confirmation. A file that backs a mounted disk image ejects that
image first, and is left alone if it can't. Claude Code, Codex, Claude app
and npx-launched tool leftovers are offered only where those tools don't
already clean up after themselves; conversation history, settings and
credentials are sized, never touched.

Storage auto-clean reaches further, every addition opt-in and configurable
from Settings › Storage: a size cap for Turborepo caches, an idle
node_modules rule that skips anything still in use, more re-downloadable
caches (app caches, Go modules, Bun, simulators, Android emulator
quick-boot snapshots, aerial wallpapers), and removal of finished git
worktrees that keeps any worktree holding files that exist nowhere else.
A reviewed clean in Actions now runs only what you left ticked — whole-cache
commands wait for a full run.

The storage report's temp section shows real sizes without asking for a
password, and a new section covers space used outside your home folder.

## v2.65.0 — Spotlight audit in the app: run it, fence and unfence per directory

The Spotlight audit finally has a face. A new pane (Settings → Logs →
Spotlight Audit, or the menu-bar Storage tab) shows the indexer's status,
the stuck-or-progressing verdict with its copyable deep-check command, and
every dev directory the index is wasting time on — sized, grouped by
project, and filterable.

And it acts: Run audit does a fresh dry-run pass from the pane, Apply
fences (behind a confirmation) fences everything unfenced, and each row
gets its own Fence/Unfence button — unfencing deletes the reversible
.metadata_never_index marker, which is how you re-index a directory.
Row states read the marker live from disk, so they are right the moment
you toggle, not whenever the last log run happened. The full-index
rebuild command stays copy-only, exactly as the script intends.

Under the hood, the shared run splitter learned that a ====-wrapped
closing summary belongs to the run above it — so the Login Items and
Storage Clean panes stop occasionally showing an almost-empty "latest
run" that was really just the previous run's DONE trailer.

## v2.64.1 — Stop and Details stay visible in the Monitor list

The new process table put Stop/Quit and Details behind a right-click. That
is fine if you already know to try it and invisible if you don't, so both
are back as buttons on every row. Right-click still works as a shortcut.

## v2.64.0 — Readable by everyone, and the reports finally have a home

New Reports screen. The two read-only analyzers — "where is my memory
going", "what is using my disk" — could only be run from a terminal until
now. Run either from the app and read the result in place. Neither changes
anything; they only write a document.

Accessibility: every icon-only button now announces what it does to
VoiceOver, decorative icons are skipped rather than read aloud, and status
that was only ever shown as a colour now also changes shape or carries a
number, so it survives a colourblind reader or a screen reader. Faint text
that was carrying real information has been darkened.

Plainer language throughout. "Preview (dry run)" is now "See what would be
cleaned"; jargon like resident RAM, orphaned helpers, SIGTERM and launchd
is explained in ordinary words first, with the precise term after it. The
sidebar sections are named for what you do there.

The Downloads janitor's settings are in the app: how old a download or a
screenshot must be, and a list of things it must never touch. That last one
was already promised on screen but could only be set by editing a file.

Monitor lists standalone processes in a sortable table, with search in the
toolbar. Apps with helper processes keep their expandable grouping.

## v2.63.0 — Untick anything you do not want touched

Every item in a cleaner's preview now has a checkbox, with Select all and
Select none, and a running count. Untick a row and it is genuinely left
alone: the app hands the approved list to the analyzer, and the analyzer
enforces it — it still works out its own findings from scratch and then
keeps only what overlaps your list, so the set can shrink but never grow.
Anything you unticked is written to the log as skipped, so the receipt
shows it was left alone on purpose.

Apply is now unavailable when nothing is selected, rather than when nothing
was found.

## v2.62.1 — Personal settings were being ignored by the analyzers

A change in v2.61.0 broke the line that loads config.local.sh, so the
analyzers fell back to their built-in defaults: a custom memory limit, a
custom schedule and — most importantly — a personal list of protected apps
were all ignored. Anyone on v2.61.0 or v2.62.0 should update.

The protected-app list is a safety rule, so this is worth stating plainly:
during that window the built-in protections still applied (Finder, system
processes, anything with unsaved work, live AI sessions), but apps added by
hand were not being read from the settings file. Settings are loaded again,
verified against a real settings file in both the bundled and source
layouts.

## v2.62.0 — A Support screen that is actually reachable

The sidebar gained a Support entry. It opens a real screen that lists what
Mac Analyzers gives you for nothing — continuous memory watching with the
reasoning written down, previewable cleanups, full reports, an undo trail —
and the three ways to help that cost nothing either. Previously that
sidebar entry existed in the router but had no row, so it could only be
reached by accident, and it showed the About screen a second time.

## v2.61.0 — Setup screen, and the analyzers now ship inside the app

New Setup screen, first in the sidebar. It checks nine things about this
particular Mac — are the background jobs actually loaded, are alerts
allowed, does the app open at login, is the memory limit sensible for the
amount of RAM you have, can it see every folder — and reports what it
found rather than what it assumes. Anything that is not working gets a
button that fixes it, and the screen stays in the sidebar afterwards,
because permissions can be withdrawn later without telling you.

The analyzer scripts are now included inside the app, so a copy of Mac
Analyzers works on its own. Your settings and reports stay in your own
folder and survive every update. If you run from a source checkout, that
copy is still the one used.

Also: the app no longer asks for notification permission in its first
second. It asks on the Setup screen, where the reason is on screen, or
the first time it genuinely has something to tell you.

## v2.59 — Fewer screens, each doing one job

Activity and Memory Guard were two sidebar rows reading the same log with
the same parser — one of them just showed less. They are now one screen
with a 7-day / 90-day switch, so the two can never disagree, and forensics
reports open from either range instead of being a dead end in one of them.
Network Snapshots likewise stopped appearing twice.

Also fixed: choosing a cleaner from the menu could leave that choice stuck,
so a later visit to Actions opened something you had not asked for; the
sidebar had two different mechanisms deciding what "selected" meant; and a
mistyped internal link now leaves a trace instead of silently doing
nothing.

The per-app dossier — the screen that collects everything known about one
process — is now reachable by clicking a row, not only by right-clicking
some of them.

## v2.58 — One shared visual vocabulary

The app had grown twenty-odd screens, each picking its own colours and
spacing, so the same meaning could look different depending on where you
saw it. There is now a single set of design tokens — one colour per
outcome (stopped, recoverable, protected, preview-only, report), one
spacing and corner scale, one type ramp — and the shared components draw
from it.

This also fixes panels that looked washed out: several surfaces were being
faded twice over, which flattened stat tiles and inline code blocks.

Behaviour is unchanged; screens now spend tokens instead of inventing
values, so panes added later cannot drift from the ones written before.

## v2.57 — Say what can be undone, and let you turn it off

Storage Clean deletes files outright while an Undo screen sits three rows
away — so the app now labels each cleaner PERMANENT or GOES TO TRASH on the
review itself, and the confirmation opens by telling you which one you are
about to do instead of burying it after "everything is logged".

There is also finally a way to switch it off: About now leads to a screen
with three levels — pause, turn off background protection, or remove from
this Mac — each of which re-checks the system afterwards and reports what
actually happened rather than assuming. Nothing you own is ever deleted by
it; the last level opens Finder and leaves the decision to you.

When a cleaner fails, the app now says why in a sentence (missing tools,
blocked by macOS, bad options) with the script's own output behind a
Details disclosure and a Copy diagnostics button, instead of showing a
number.

## v2.56 — The app checks whether it is actually protecting you

Guard status was inferred from whether a pause file existed — which meant a
Mac with nothing installed still showed a green, healthy shield. The app now
asks the system directly: are the background jobs loaded, is the guard
process alive, is it paused. The Overview tile and menu headline report what
comes back, including "not set up yet" and "loaded but not running".

Pausing is also verified rather than assumed: the marker is written, read
back, and compared before the app claims anything changed — previously the
button could flip to Paused while the guard kept working — and any failure
now appears as a plain message instead of silently doing nothing.

## v2.55 — Say only what the engine actually does

An audit compared every sentence in the app against the scripts that back
it. Where they disagreed, the app was wrong. Corrections:

- schedules are now read from your installed agents instead of being
  printed from memory, so a job you never installed says "Not scheduled"
  rather than inventing a time
- Actions no longer claims per-item approval it cannot enforce today: the
  cleaner re-checks everything at apply time, and the copy now says so
- the cleaners describe what they really do — Memory Clean's actual rule,
  Reclaim's much wider net, and deep mode's full scope including npm's
  entire cache and removing all unused container images
- Monitor, the menu, the guard log and Activity state their real limits
  instead of "every process" and "everything"; Activity now genuinely
  shows every event in its seven days
- container maintenance follows whichever runtime backs the docker command
  on your Mac (OrbStack or Docker Desktop) rather than assuming one
- stopped-process commands are recorded in full, and a command captured
  before that change is flagged as shortened
- the log-viewer preference is now honoured by the in-app buttons too;
  a notification-sound setting that nothing read was removed
- documented the Downloads janitor's age and keep-pattern settings

## v2.54 — Safety fixes in cleaning and protection

- the Downloads janitor now runs one instance at a time, and a failure while
  measuring a file can no longer abort a sweep midway — the case that could
  leave files in the Trash without the receipts needed to undo them
- an app name containing a bracket or other symbol in your protected list
  used to break the guard's matching silently, leaving nothing protected
  while everything looked healthy. Those names are now escaped, and the
  guard refuses to start (and tells you) if the list is unusable
- added the permission descriptions macOS requires before it will let the
  app quit an app politely or read your Downloads and Screenshots folders —
  without them those actions failed with no prompt and no explanation
- clearer wording about what the scheduled cleans touch, and that the
  Downloads janitor is separate, reviewed, and undoable

## v2.53 — Fix a restore that could move the wrong file

The janitor's receipt recorded only where a file came FROM. When the Trash
already held a file of the same name, the janitor's copy was renamed on
the way in — so reconstructing the Trash path from the name could point at
a different file the user had trashed themselves, and Restore would move
that file over the original path while reporting success.

Receipts now record the exact destination, and restore uses only that
recorded path — never a guess. Entries written before this change are
shown as "restore manually" rather than acted on.

Also: minor licence-screen wording fixes.

## v2.51 — The process table without forking anything

Reading the process list used to fork /bin/ps — three times per guard-store
reload, since three separate helpers each re-read the whole table. The
kernel answers those questions directly, so it does now: pids and memory
come from proc_listallpids + proc_pid_rusage, and the expensive full
command line is fetched only for processes that already passed the memory
floor (a few dozen, not several hundred). Ancestors below the floor are
pulled in with a cheap lookup so an app's slim launcher still owns its
heavy helpers and families stay intact.

## v2.50 — Navigation timing instrumentation

Sidebar switches now log their main-thread turnaround so responsiveness
can be measured from a real session instead of inferred:
log show --predicate 'category == "nav"' --last 15m

## v2.49 — A dedicated screen for supporters

The sidebar-foot badge is now full width and opens its own screen instead
of hiding details inside About — which is where they belonged: About
documents the app, that screen carries everything tied to a supporter's
licence. Free builds are unchanged: the pane and badge exist only when
the optional overlay module is present.

## v2.48 — A real query layer — navigation stops stacking work

Panes were each firing an unbounded background job on every appear, and
Monitor plus the menu re-ran the heaviest one every two seconds. Rapid
navigation therefore stacked concurrent process-table sweeps and log
parses, and the window stopped answering clicks until they drained.

All pane loads now go through one shared coordinator: work is serialized
(one producer at a time instead of N), deduplicated and cached per call
site with a short TTL (re-entering a pane or a refresh tick is free), and
the heaviest read — the guard store's reload — refuses to start a second
copy while one is running. Live-refresh intervals start at 5 s.

REVIEW section reordered to Actions, Trends, Undo.

## v2.47 — QA polish pass — icons, Finder reveal, search, scannable About

From the per-screen audit's remaining list:
- login-items rows show the real vendor icon when the target still exists
- storage auto-clean rows gain the inline Show in Finder button the
  Actions screen already had
- the guard log gains a process/pid filter field alongside its chips
- About's prose sections collapse into disclosure groups (first open)

## v2.46 — Build reliability for local package overlays

build.sh now folds the overlay package's newest source timestamp into its
build-mode key, so adding a file to a local overlay forces a clean resolve
instead of failing against SPM's cached target file list. Local artifacts
that are never part of the repo are ignored explicitly.

## v2.45 — Mac Health Report — a shareable one-page summary

Export a self-contained HTML report from About or Overview: the last 30
days of runaways stopped, spikes caught, memory freed and disk reclaimed;
current storage with its runway forecast; the repeat offenders table;
startup-item audit count and thermal throttling events. Light and dark
aware, no external assets, generated entirely from local logs — nothing
leaves the machine to produce it.

## v2.44 — Disk runway forecast + baseline collection begins

- Overview's disk tile now reads the trend from your own storage-clean
  history: a least-squares line through the logged free-space series
  yields "runway ~N weeks at current pace" — shown only when at least
  five points span a week and the trend is genuinely downward; under 30
  days it escalates to a Needs Attention card pointing at the cleaner
- the app now records one memory-use baseline per day (running daily
  mean) so future "this isn't normal for your Mac" intelligence starts
  with history instead of a cold start

## v2.43 — Persistence watcher — know when something installs itself at login

The app now baselines every LaunchAgent/LaunchDaemon plist (user and
system) and, on launch plus every six hours, notifies when something NEW
appears — "X just installed a login/startup item", click to review.
Additions only (no alarm noise from edits or removals), first run seeds
silently, receipts land in reports/persistence.log with its own screen
under Logs > Persistence Changes. Observation only; nothing is blocked.

## v2.42 — Undo — the ledger of reversibility

New REVIEW > Undo screen. Janitor items come back from the Trash with one
click — restore only offers itself when the Trash copy still exists and
the original path is free, and every restore writes its own [RESTORED]
receipt to the janitor log (the parser understands it everywhere). Guard-
stopped dev servers list their logged command with a copy button, labeled
honestly as the recorded prefix. A cleaner people trust is one that can
put things back.

## v2.41 — Per-app dossier — one screen, everything known about a process

Right-click any Monitor row (family headers included) > Dossier: live
footprint (resident memory, energy and disk I/O since launch), the
protection verdict (protected list / guard auto-stop scope / regular app),
90 days of guard history for that process, and its traffic from the latest
network snapshot — every section composed from parsers the app already
had. Dossier pushes ride the shell's back/forward history like every
other drill-down.

## v2.40 — What's New — the release notes live in the app

build.sh bundles a changelog generated from the release-note commits
(newest 20) into the app; the Update pane renders it as What's New —
one entry per release, newest expanded, fully selectable. The releases
were always documented; now the documentation ships with the product.

## v2.39 — Screen-QA fixes — forensics browser, Activity chips, network dedupe

Per-screen QA found two wiring defects and one stale sibling:
- Logs > Forensics now opens a proper browser (every crisis report,
  newest first, pushing the structured detail screen) — the generic
  run-list parser had been garbling forensics files, which are not
  run-shaped
- Logs > Network Snapshots routes to the rich Network pane instead of
  rendering the same data as raw lines
- Activity gets the full treatment its sibling guard-log pane already
  had: counted filter chips, card rows, liveness chips — same data,
  same anatomy, no more plain text rows

## v2.38 — Disk I/O lens — who is wearing out the SSD

Monitor gains a third lens: per-process disk bytes read/written since
launch, from the same kernel accounting call as the energy lens — writes
ranked first because writes are what age the drive. Real app icons,
search-aware, async. build.sh now detects overlay/plain build-mode
switches and resets build state, which otherwise poisons incremental
linking with stale module references.

## v2.37 — Optional local package overlay

Package.swift accepts a local overlay package via the MA_PRO_PATH
environment variable (build.sh --pro sets it and busts the manifest
cache); SettingsFeature gains the overlay module when present. Two small
conditional slots — sidebar foot and About — render only when the overlay
module is available. Default builds are byte-for-byte the public graph:
no overlay, no extra code, nothing new to audit.

## v2.36 — Janitor gets the structured pane; Logs landing gets category pills

- the Downloads Janitor log now renders in the storage-shaped structured
  pane (grouped by folder, TRASHED/DRY badges, dry-run banner) instead of
  the generic line list — one parameterized pane serves both storage logs
- the Logs landing screen gains category pills (All | Memory | Storage |
  Downloads | Network | System); picking a category switches the list to
  big review cards with each log's latest-run summary in its own words,
  parsed off-main

## v2.35 — Actions get history, real icons, sorting, and Finder reveal

- Previous runs: every cleaner's past runs are now first-class inside
  Actions — expandable entries parsed into the same cards as a live
  review, backfilled entirely from the logs that were already there
- storage/janitor review rows carry the real file/folder icon and a
  Show in Finder button when the path still exists
- Size | Name sort control on storage-shaped reviews

## v2.34 — Menu-bar parity — helper families and reviewed cleans in the menu

The menu's Monitor tab now shows the same one-row-per-family view as the
Monitor pane: helpers rolled under their parent app with real icons and
totals, expandable in place. The Storage tab gains a REVIEW & CLEAN row
linking straight into the Actions screen with the right cleaner
preselected (new deep-link form: actions:<cleaner>), alongside the
existing scheduled-clean kickstarts. Menu data loads stay fully async.

## v2.33 — Pane switches never block — all loads moved off the main thread

Every settings pane (and the menu-bar store behind Overview and the menu)
was doing its data work synchronously on the main thread — process-table
shell-outs, full log parses, forensics reads — which made sidebar clicks
feel frozen. All of it now follows one pattern: cached values stay painted,
fresh data is computed on a background task, and results are applied
atomically on the main actor. Panes paint instantly and fill in place;
the guard store's reload is fully asynchronous with an atomic payload
apply. No behavior changes — only when work happens.

## v2.32 — IPhone/iPad backup finder

Settings > Storage now reports local MobileSync backups — device name,
last-backup date, and true on-disk size (often multi-GB and forgotten) —
with Show in Finder per row. Strictly report-only: deleting a backup stays
a deliberate manual act in Finder; the app will never do it.

## v2.31 — Energy lens — kernel-accounted battery blame

Monitor gains a Memory | Energy switch. The Energy lens reads the kernel's
own per-process energy accounting (proc_pid_rusage, no sudo, no
powermetrics) and ranks live processes by energy consumed since launch —
who actually drained the battery, not who merely looks busy. Real app
icons, mWh/Wh formatting, name resolution through the kernel for CLI
processes. Ships with a small C bridge target (CLibProc) exposing libproc
to Swift; the engine remains untouched.

## v2.30 — Tool-cache expansion pack

storage-auto-clean gains an opt-in expansion pack: Homebrew downloads, pip,
uv, Cargo registry cache, Gradle caches, and Xcode DerivedData as
first-class categories — each size-reported in every dry run and cleaned
with the tool's own prune command (or plain removal of redownloadable
cache) on apply. Enabled per tool via ANALYZERS_TOOL_CACHES, written by new
toggles in Settings > Storage through the managed config block. Sources
and state are never in scope; disabled tools still cost nothing.

## v2.29 — Thermal monitor — throttle receipts and alerts

The app now watches the OS thermal state for the whole session. When macOS
starts throttling the CPU (the silent "my Mac got slow" moment), it posts a
notification naming the busiest processes at that instant, writes a receipt
to reports/thermal.log (elevation AND recovery), shows a THROTTLING badge
in Monitor's header, and raises a Needs Attention card on the Overview
dashboard. Warm-but-not-throttling shows as a quiet WARM badge. One watcher
instance serves every surface; notifications fire once per episode.

## v2.28 — Downloads Janitor — age-based tidy that only ever uses the Trash

New engine cleaner (bash, dry-run by default): downloads-janitor.sh sweeps
top-level ~/Downloads items untouched for 30+ days and screenshot FILES
older than 14 days (never folders wholesale — a parent's mtime can lie
about fresh children), honors keep-patterns from config.local.sh, and on
--apply moves everything to the Trash — recoverable by design, nothing is
ever deleted permanently. Fully integrated as the fourth Actions tab
(preview → review as sized cards grouped by folder → confirm), with its
own log under Logs. TRASHED status joins the storage parser.

## v2.27 — Network analyzer — the phoning-home ledger

New engine analyzer (bash, read-only, no sudo): network-snapshot.sh takes a
per-process traffic snapshot via nettop — cumulative bytes in/out since
each process launched — and logs top talkers to reports/network/. New
OBSERVE > Network pane: on-demand snapshots, downloaded/uploaded totals,
per-process rows with real app icons, live ACTIVE/ENDED state, and names
resolved through the kernel when tools truncate them. Also appears under
Logs as Network Snapshots. Observation only — nothing is ever blocked.

## v2.26 — Memory sparkline in the menu bar

The menu-bar chip now carries the last 30 minutes of memory-in-use as a
tiny template sparkline (one sample every 30 s from mach host statistics —
active + wired + compressed over physical RAM, fixed 0-100% scale so quiet
periods draw calm and pressure draws high). Chip and sparkline compose into
a single template image so the status item renders reliably and tints with
the menu bar. Toggle lives in Settings > Notifications; kill-count badge
unchanged.

## v2.25 — Monitor groups helpers under their parent app

The Monitor pane now shows one row per FAMILY: helper processes roll up
under their parent (real app icon, helper count, rolled-up total) and
expand on disclosure — the view Activity Monitor never gives you. Ancestry
is resolved from the live process table with a shell/terminal boundary, so
a dev server started from a terminal stays its own row instead of being
blamed on the terminal. Search matches parents and helpers; a helper match
trims the family to the matching helpers. Singletons render flat.

## v2.24 — In-app Actions — dry-run, review, apply

New REVIEW > Actions screen: pick a cleaner (Memory Clean, Memory Reclaim,
Storage Clean), run the engine's dry run from the app, and review every
would-be change as native cards — the same parsers and anatomy as the log
panes, with protected-session banners intact. Apply sits behind an explicit
confirmation, runs the script with --apply, and reports what actually
happened with receipts in the log. Storage offers the engine's deep mode
(stale node_modules + Time Machine report) as a toggle. The engine remains
the only actor: the app never deletes or kills anything itself, and nothing
is ever applied unreviewed.

Also: `open -a "Mac Analyzers" --args --pane <screen>` deep-links straight
to any settings screen — scripting hook and testing door.

## v2.23.2 — Brand card reads as a button at rest

Persistent glass container with a hairline border around the sidebar brand
card — discoverable without hovering; hover brightens, click opens the
Overview dashboard.

## v2.23.1 — Guaranteed back navigation, glass-hover brand card

- back chevron is now unconditional for drilled screens: history-first,
  and if no history stop exists it pops the on-screen stack directly —
  a drilled Trends/Logs screen can always navigate back
- same-row sidebar re-click reset moved to a row tap gesture: AppKit
  never fires the selection binding when the clicked row is already
  selected, so the binding-based reset could not trigger on real clicks
- sidebar brand card gets a liquid-glass hover treatment so its role as
  the Overview button is discoverable
- router os_log breadcrumbs (category "router") for navigation diagnosis

## v2.23 — Overview dashboard, Trends drill-downs, router audit fixes

- Overview: Settings now opens on a dashboard — status tiles (memory
  pressure, guard state + stops today, disk), a Needs Attention section
  that renders only when something is true (elevated pressure, paused
  guard with inline Resume, update available, >1 GB reclaimable), the
  biggest processes right now with working Stop buttons, recent events
  with liveness chips, and the 7-day headline as a Trends teaser. The
  sidebar brand card is the Home button; every element routes through
  the shared router so history chevrons track dashboard drill-ins.
- Trends drill-downs: every stat tile and repeat-offender row pushes a
  receipt-level screen scoped to the selected range — kill/spike/
  pressure/CPU event lists, per-process memory-freed breakdown, deleted
  storage grouped by project, the current reclaimable set, and a
  per-process timeline with peak-resident stats.
- Router audit fixes: re-entering the already-selected log (sidebar
  re-click or deep link) now resets its stack instead of leaving a stale
  drilled screen; Logs landing rows route through pane selection so the
  sidebar highlight always matches the screen.

## v2.22 — Logs always lands on the list; REVIEW section; Trends range menu

- sidebar "Logs" now always opens the logs LIST — including re-clicking it
  while drilled into a log — with drilled states still one chevron away in
  the navigation history; stack navigation (list -> log -> run/forensics)
  verified across every log
- new REVIEW sidebar section (verb voice of CONFIGURE/OBSERVE) housing
  Trends now and the upcoming Actions surface later
- Trends ranges: 3/7/30-day tabs fill the bar; a fixed-width ellipsis menu
  carries 24 Hours / 14 / 90 Days / All Time, highlighting when active

## v2.21.1 — Full-height toolbar strip

unifiedCompact read cramped next to System Settings — the strip is now the
standard unified height, same single row: chevron pair leading, title
beside, content given room to breathe underneath.

## v2.21 — Browser-style back/forward history, System-Settings toolbar anatomy

The settings window now navigates exactly like System Settings: a permanent
back/forward chevron pair leads the toolbar strip with the pane title on
the same row, and the pair walks a real navigation history — every sidebar
switch and every drill-in (log -> run -> forensics) is a stop you can go
back to and forward from again. History is snapshot-based at the shell
(typed [LogRoute] paths made restorable), coalesced one entry per settled
navigation.

Getting the single-row strip required hosting settings in a regular Window
scene: the Settings scene ignores windowToolbarStyle and stacks a centered
title above the buttons. Cmd-comma and the app-menu item are preserved;
all open paths (menu button, Dock reopen, notification deep links) now
route through openWindow.

## v2.20 — Shell-level navigation + Dock-click fix, both log-verified

Navigation now follows the System Settings anatomy: the window shell owns
the back chevron (a semibold toolbar item in the title strip, shown only
when a screen is pushed) and screens contribute only their titles — the
nested stack's own floating back bubble is suppressed at the destination
level, and the in-content Back/All-Logs/All-Runs buttons are gone. Pane
headers scaled up to match (larger tile, bolder title).

Dock-click bug root-caused with os_log instead of guesswork: the hidden
1x1 anchor window that bridged reopen events to openSettings() gets its
publisher suspended while occluded, so the signal died silently — and
showSettingsWindow: has no responder on macOS 26. The open-settings
receiver now ALSO lives in the menu-bar label, the one render tree that
is alive and visible for the app's whole lifetime. Verified: reopen ->
"handled by menu-bar-label" -> settings visible: true.

## v2.19 — Trends pane — the suite's receipts, aggregated

New OBSERVE > Trends screen answering "what has this actually done for me":
a headline sentence per window (7 days / 30 days / all) — runaways stopped,
spikes caught, memory freed, disk reclaimed — over Defended and Recovered
stat tiles, a stacked events-per-day chart (Swift Charts), and the repeat-
offender processes with kill counts. Everything is aggregated from the
suite's own local logs by the same parsers the log panes use; nothing
leaves the machine. Deep-linkable as "trends".

## v2.18 — Live ACTIVE/ENDED chip on every process event

Guard events age: a spike from an hour ago may be long resolved. Every
process-bearing row — menu recent events, Activity pane, Memory Guard log —
now carries a liveness chip: green ACTIVE while that exact process is still
running, dimmed ENDED once it is gone. The check verifies identity, not just
pid existence: command name must match and the process must predate the log
line, so recycled pids and zombies read as ENDED. One reusable component
(LiveStateChip) + one kernel-level check (ProcessLiveness, sysctl) shared by
menu and Settings.

## v2.17 — Structured panes for every log, in-app forensics viewer, sidebar brand card

- storage auto-clean pane: reclaimable space grouped by project and sorted
  largest-first (the 26.7 GB entry is no longer buried between 4 KB lines),
  per-chip size totals, cache-kind icons, third-party tool output honestly
  collapsed as raw blocks, Time Machine snapshot card
- memory auto-clean + reclaim share ONE parser and pane: status-filtered
  cards (Would Reap | Killed | Reported | Protected), before/after memory
  cards, live-session exemptions surfaced as a shielded banner, aggregate
  MCP-server lines as stat chips
- forensics reports open IN the app: stat cards for pressure/memory/swap at
  the moment of crisis plus the top-25 process table — pushed from the guard
  pane's Reports rows; missing historical files degrade gracefully
- settings sidebar brand card (app icon · name · version), System-Settings
  style; update badge on the Update row; self-notification when a new
  release is available (click lands on the Update screen)
- diagnostics: os_log instrumentation on the Dock-reopen path
  (subsystem com.mac-analyzers.app) for the open Dock-click investigation

## v2.16 — Structured log panes — guard event chips, login-items verdict cards

- Memory Guard log pane: full-depth structured events through the shared
  guard parser (no more raw text) behind filter chips with live counts
  (All | Spikes | Killed | Reports | Pressure & Cap | CPU Hogs); forensics
  rows open their report, disabled with an explanation when the file is
  gone; distinct empty states for quiet-log vs filtered-to-zero
- guard parser: PRESSURE / PRESSURE-CRITICAL / CAP-EXCEEDED / CPU-HOG /
  FORENSICS lines now parse into typed events with human titles (they were
  previously lumped into a generic warning bucket)
- Login-Items Audit pane: verdict cards (ORPHAN / NEEDS SUDO / LEFTOVER? /
  SKIP / REMOVED) grouped by audit scope, filter chips with counts, and a
  per-row "Copy command" button for every remediation one-liner — no more
  matching numbered orphans to a trailing command block by eye
- shared UI primitives: FilterChipsBar, DataCard, and full-width segmented
  tabs (the native segmented picker won't stretch); Memory's process-list
  tabs now span the full row

## v2.15 — Install to /Applications; tabbed scrollable process lists

- the build now installs the app to /Applications/MacAnalyzers.app (a
  locally built copy carries no quarantine — no DMG involved); the copy
  under app/ is the build artifact and script-only fallback. notify.sh, the
  launchd agent entry points, and upgrade.command all prefer /Applications;
  the login item re-registers there on first launch from the new location
- Memory settings: the two process lists are now segmented tabs
  (Protected | Reclaim), each a taller scrollable list — the reclaim list
  no longer clips at five rows; the searchable Add/Remove picker is
  unchanged
- README install steps updated (build + install, launch from /Applications)

## v2.14 — Menu deep-links into Settings, Team-ID-signed builds

- menu buttons (Guard log / Forensics / Storage log / Login-items audit) and
  event rows now deep-link into the app's OWN Settings screens (pane-target
  signal via SettingsOpener) instead of dumping raw files into TextEdit —
  the app's screens are the actionable surface; TextEdit remains only as
  the in-Settings escape hatch
- first Team-ID-signed release: Apple Development identity (Team T27YF68P43)
  detected and applied automatically by build.sh (WWDR G3 intermediate was
  the missing chain link); stable code identity across rebuilds + completes
  the BTM responsible-code chain pending restart verification
- SettingsOpener moved to AnalyzersKit (menu needs it); openPaneInternal
  deep-link channel; roadmap: grouped-by-default principle, known bugs
  (Dock reopen), in-app Actions idea, environment facts current

## v2.13 — Compiled agent-runner entry point (BTM attribution), identity-aware signing

- agent-runner: tiny compiled binary in the app bundle that execv's the bash
  engine — the launchd plists now enter through IT, because BTM refuses to
  attribute background items whose entry point is a bare script (DTS-
  confirmed; research in tasks-plans/research/login-items-btm-2026-07-31.md).
  Engine stays bash; only the doorway is compiled. Script-only installs
  (no app built) hydrate to the plain script automatically
- build.sh: auto-prefers an "Apple Development" signing identity when one
  exists in the keychain (real Team ID → BTM attribution + stable TCC
  identity across rebuilds); ad-hoc fallback keeps zero-setup builds
- roadmap: platform feasibility verdicts folded in (widgets/App Intents need
  Xcode — incoming on this machine; nettop network bytes + ri_energy_nj
  per-process energy verified unprivileged); monetization note recorded

## v2.12 — App pickers with real icons for the process lists

- AppListEditor replaces blind text fields for the three app/process lists:
  rows show the app's actual icon (NSWorkspace) when installed; "Add…" opens
  a searchable sheet — installed apps (with icons, /Applications +
  /System/Applications + ~/Applications, vendor subfolders) for the reclaim
  and stale-app lists; RUNNING-process suggestions for the protected-
  fragments list (pick from reality, not guesses); custom-entry fallback
  kept for edge cases
- AppCatalog in AnalyzersKit (installed-app scan, running-name suggestions);
  editors live in UIComponents; glob/path lists keep the plain editor

## v2.11 — Schedule pane (editable, upgrade-surviving), Monitor pane, guard-event parser fix

- Schedule pane (new SCHEDULE sidebar group): time pickers for the memory
  and storage daily cleans, interval stepper for the deep clean — written
  into the INSTALLED launchd plists and reloaded; guard shown as always-on.
  Both manage-agents installers now PRESERVE a customized
  StartCalendarInterval/StartInterval when re-hydrating, so schedules set in
  the app survive reinstalls and upgrade.command
- Monitor pane (OBSERVE group): the menu tab's bigger sibling — top 40
  processes ≥128 MB, name filter, pressure + refresh chips, Stop/Quit rows
- ProcessRow + BadgeCapsule promoted to UIComponents (now depends on
  AnalyzersKit) — shared by menu and settings
- parser fix from the log-format survey: PRESSURE / CAP-EXCEEDED / CPU-HOG
  guard lines were silently dropped by the token switch — now surfaced as
  warning events in Activity and the menu

## v2.10 — Sidebar-child stacks re-rooted (no path surgery), in-app update checker

- child-switch fixed at the architecture level: a sidebar-selected log gets
  its OWN NavigationStack rooted at that log's pane (.id(kind)) — zero
  programmatic path manipulation, which was dropping pushes mid-animation
  and landing users on the landing screen; the Logs row keeps the pushable
  landing-screen stack
- in-app updates: VERSION injected into Info.plist at build time
  (PlistBuddy); UpdateChecker compares against the latest GitHub release
  (6 h cache, one public GET, nothing sent); menu footer shows "v2.10.0" —
  or an "Upgrade to vX" button when the repo is ahead; new Update pane under
  About (installed vs latest, Check Now, Install Update → upgrade.command
  in Terminal)

## v2.9 — Nested run screens per log; fix sidebar child-switch kickback

- child-switch bug: the path→sidebar watcher misread SwiftUI's transient
  empty path during child-swap animation as "user pressed back" and bounced
  to the Logs landing screen. Removed — back-intent is now an explicit
  signal (logsHomeSignal from the All Logs button → landing screen + sidebar
  highlight), never inferred from path state
- nested runs: each log pane is now a RUNS LIST (badge + header + summary +
  line count per row); a run pushes RunDetailView — the run's lines parsed
  into sections (### markers) with badge-capsule rows (DELETED/DRY/EXEMPT/
  KILLED/…), text-selectable, "All Runs" back affordance — screens, not dumps
- LogParsing.swift extracted (LogRun/RunRoute models + shared line
  classification); logsPath is a NavigationPath for the mixed-type pushes

## v2.8 — Dock-reopen fix, upgrade.command for cloned users, contributor docs

- SettingsOpener: every open-Settings entry point (Dock click, notification
  tap, menu button) runs the same belt-and-braces sequence — SwiftUI route
  via the anchor window plus a delayed AppKit showSettingsWindow: fallback
  for when the anchor window no longer exists (the Dock-click-did-nothing
  failure)
- upgrade.command (root, Finder double-clickable): git pull --ff-only →
  rebuild app → refresh agents → relaunch; config.local.sh never touched —
  the upgrade path for already-cloned users
- docs: README "Staying up to date" (upgrade.command first, tarball
  alternative) + Dock/launch pointers + feature text refreshed to current
  app; PORT step 11 (upgrades survive calibration); CLAUDE/AGENTS gain
  "Building features in the app" (SPM target map, PaneScaffold/
  MenuComponents conventions, v2.7.1 lesson) and the release/upgrade flow;
  CONTRIBUTING documents fork → branch from development → PR to development
  (never main — main-commits ship), screenshots + green swift build for
  app/UI PRs

## v2.7.2 — Fix light-band regression — header back inside the Form, no hard scroll edge

The v2.7.1 header hoist put the pane header into the toolbar's backdrop
region: rendered as a light band with a doubled title in dark mode. Header
returns inside the Form (clear row, centered with spacers) and the
.scrollEdgeEffectStyle(.hard) opaque backdrop is dropped. Navigation fixes
from v2.7.1 (logs path state, hidden floating chevron) are unaffected.

## v2.7.1 — Fix logs child navigation, remove floating glass chevron, center all pane headers

- logs navigation: real @State path replacing the computed binding that
  fought SwiftUI's transitions (sidebar children bounced back to the landing
  screen); sidebar↔stack sync both directions (child click pushes its log,
  popping moves the highlight back to Logs)
- native back chevron hidden on log panes (rendered as a floating glass
  circle in the Settings window) — the in-content "All Logs" button is the
  single back affordance
- PaneScaffold: header moved OUTSIDE the Form (macOS draws the section card
  regardless of row background — the boxed/left-aligned header cause) and
  hard-centered with spacers: every pane's header now identical + centered

## v2.7 — MacOS 26 idiom pass — every pane on the scaffold, verified new APIs

- Activity/Logs/About converted to PaneScaffold: ALL panes now share one
  container (grouped form + scrolling un-boxed header) — the Activity pane
  no longer renders differently from its siblings
- research-driven (grounded against the 26 SDK, compiler-verified):
  .toolbar(removing: .sidebarToggle) — System Settings' sidebar has no
  toggle; sidebar tiles sized up to 20pt (Tahoe undersized-icon bug);
  Save is .glassProminent (the one standout action per pane);
  .scrollEdgeEffectStyle(.hard, .top) on dense panes
- .listSectionSpacing rejected by the compiler as iOS-only despite research
  suggesting it — spacing rhythm handled by the compact PaneHeader instead
- log pane back button relabeled "All Logs"; logs render as run Sections
  inside the scaffold (badges kept)

## v2.6 — Unified pane scaffold, nested Logs navigation, dynamic titles, size sweep

- PaneScaffold: ONE container for every settings pane — un-boxed General-
  style header scrolling with the grouped form; identical top anatomy ends
  the pane-shift when switching; window title is now the pane name
- Logs: sidebar children (truncating) removed — Logs is a landing screen of
  chevron rows (General pattern) pushing each log's pane via NavigationStack,
  with the native back button in the toolbar
- sidebar: ALL-CAPS section headers (CONFIGURE / OBSERVE)
- button sweep: no .controlSize(.small) anywhere in Settings
- decomposition: ProcessRow/EventRow/CapacityBar → MenuComponents.swift
  (MenuContentView 445→307 lines)

## v2.5 — System-Settings sidebar, unified pane anatomy, bigger controls

- Settings window rebuilt as NavigationSplitView: colored-tile sidebar
  (Configure: Memory/Storage/Notifications · Observe: Activity + Logs ·
  About) replacing the top tab bar; Logs is the one genuinely nested item —
  six per-log children in the sidebar (each log its own pane) instead of an
  in-pane dropdown/segmented picker
- unified pane anatomy: every pane opens with a General-style header (large
  tile + title + one-line description); window 780×620 min
- shared UIComponents target (IconTile, PaneHeader) — the System-Settings
  visual language used by both the menu and the settings window
- controls sized up app-wide (regular instead of small; prominent large
  Save) — the small buttons were our doing, not SwiftUI's

## v2.4 — Disk now-vs-last-clean, native Logs viewer, real app icons + tiles

- Storage tab: "Storage now" — live boot-volume state (Finder's purgeable-
  aware free-space figure) with a capacity bar (blue→orange→red), plus the
  "at last clean" line parsed from the storage log for now-vs-then at a
  glance; scheduled-clean rows get Settings-style icon tiles
- Logs tab redesign: icon segmented picker (no dropdown); content parsed
  into RUN blocks (report logs) or day groups (guard log), newest run first
  with lines in natural order; badge capsules (KILLED/SPIKE/DRY/DONE/…) and
  section headers instead of a raw text dump; TextEdit stays the escape hatch
- Monitor/Memory rows: REAL app icons via NSRunningApplication for apps and
  helpers; colored tile for headless dev tools — the System-Settings visual
  language

## v2.3 — Actionable notifications, Dock-click Settings, monitor auto-refresh, Logs tab

- notifications: body click now opens the APP (where the actionable buttons
  live) instead of dumping a log; buttons: Open Mac Analyzers · Open Log ·
  Stop Process (on spike/over-cap alerts — pid travels in the payload, the
  stop verifies pid+command-token so a recycled pid is never signalled, and
  a confirmation notification reports the outcome)
- Dock: a kept Dock icon now behaves properly — click launches the app when
  stopped, opens Settings when running (reopen event → activation dance →
  openSettings via the anchor window)
- Monitor tab: Activity-Monitor-style update frequency chips (2s/5s/10s/Off,
  persisted) replacing the manual refresh button
- Settings: new Logs tab — every suite log in one place with a newest-first
  inline viewer (kills/critical red, spikes/warnings orange) + TextEdit
  escape hatch

## v2.2 — Monitor tab with stop actions, guard kill toggles, settings IA overhaul

- Monitor tab (menu): live top-10 processes by resident RAM across ALL types
  — dev tools AND apps/helpers (the OrbStack-at-3.3GB case) — grouped, with
  per-row Stop (SIGTERM, dev) / Quit (graceful NSRunningApplication, apps)
  so nobody needs Activity Monitor for the common case
- guard strategy toggles: GUARD_HARDCAP_KILL / GUARD_PRESSURE_KILL — off =
  notify-only (logged CAP-EXCEEDED / pressure notice), never silent; Settings
  toggles with captions
- settings IA: 0.1 GB cap slider steps; captions under every Memory control;
  Title Case grouped sections (Limits / Alerts / Process Lists); "How the
  guard decides" moved to a new About tab (expanded: rss vs Activity Monitor
  vs VRAM, user-stop vs auto-stop contract); new Activity tab — last 50
  events over 7 days with the same human titles; Settings window 640×620
- menu window 420pt wide (fixes truncated buttons)
