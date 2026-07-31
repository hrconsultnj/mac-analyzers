#!/usr/bin/env bash
# SwiftBar plugin — mac-analyzers at a glance.
# Menu bar: memory-chip icon (+ red kill count when the guard killed today).
# Menu: human-readable recent events (newest first, last 24h, one line per
# process), then compact per-suite sections; logs open in the default text
# editor (open -t), not Console. Refreshes every 5 min; ⌘R to force.
#
# <xbar.title>Mac Analyzers</xbar.title>
# <xbar.desc>Memory-guard kills/spikes + auto-clean runs, click-to-open logs.</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

MEM="$HOME/mac-analyzers/reports/memory"
STO="$HOME/mac-analyzers/reports/storage"
PAUSE_FLAG="$MEM/.guard-paused"

log_row() {  # label, path, [extra params] — click opens in default text editor
  echo "$1 | bash=/usr/bin/open param1=-t param2=\"$2\" terminal=false ${3:-}"
}
mtime() { [[ -e "$1" ]] && date -r "$1" "+%b %-d, %-I:%M %p" || echo "never"; }

today="$(date +%F)"
yesterday="$(date -v-1d +%F)"

# ---------- menu bar title ----------
kills_today=$(grep -c "^${today}.*KILLED" "$MEM/guard.log" 2>/dev/null) || kills_today=0
if [[ "$kills_today" -gt 0 ]]; then
  echo "${kills_today} | sfimage=memorychip sfcolor=red"
else
  echo "| sfimage=memorychip"
fi

echo "---"

# ---------- headline ----------
if [[ -e "$PAUSE_FLAG" ]]; then
  echo "Guard is PAUSED | color=orange size=13"
elif [[ "$kills_today" -gt 0 ]]; then
  echo "${kills_today} process(es) killed today | color=red size=13"
else
  echo "All clear — nothing killed today | size=13"
fi

echo "---"
echo "MEMORY GUARD | size=11 color=gray"

# Human-readable events, last 24h, newest first. One line per process:
# a kill supersedes that pid's spikes; otherwise only the latest spike shows.
events=$(grep -E "^(${today}|${yesterday}) " "$MEM/guard.log" 2>/dev/null \
  | grep -E ' (KILLED|SPIKE|WARNING|CRITICAL) ' | tail -80 \
  | awk '
    function t12(ts,   p, h, ap) { split(ts, p, ":"); h = p[1] + 0
      ap = (h >= 12) ? "PM" : "AM"; h = h % 12; if (h == 0) h = 12
      return h ":" p[2] " " ap }
    function gb(mb) { return sprintf("%.1f GB", mb / 1024) }
    function rest(start,   s, i) { s = ""
      for (i = start; i <= NF; i++) s = s (s == "" ? "" : " ") $i
      return s }
    $3 == "KILLED" {
      # 2026-07-31 16:15:11 KILLED [hard-cap 6144MB] pid=30637 rss=6200MB  name…
      reason = ""; if (match($0, /\[[^\]]*\]/)) reason = substr($0, RSTART + 1, RLENGTH - 2)
      if (reason ~ /^hard-cap/) { cap = reason; sub(/^hard-cap +/, "", cap); sub(/MB$/, "", cap)
        reason = "over the " sprintf("%.0f", cap / 1024) " GB cap" }
      else if (reason ~ /pressure|critical/) reason = "critical memory pressure"
      pid = ""; mb = ""; ns = 0
      for (i = 3; i <= NF; i++) {
        if ($i ~ /^pid=/) pid = substr($i, 5)
        else if ($i ~ /^rss=/) { mb = substr($i, 5); sub(/MB$/, "", mb); ns = i + 1; break } }
      if (pid != "") killed[pid] = 1
      printf "%06d|✕ %s  %s killed — was %s (%s),,red\n", NR, t12($2), rest(ns), gb(mb), reason
      next }
    $3 == "SPIKE" {
      # 2026-07-31 15:48:35 SPIKE pid=30637 +687MB now 5024MB  name…
      pid = substr($4, 5)
      grew = $5; sub(/MB$/, "", grew); sub(/^\+/, "", grew)
      mb = $7; sub(/MB$/, "", mb)
      spike[pid] = sprintf("↑ %s  %s climbing — at %s (+%s),,orange", t12($2), rest(8), gb(mb), gb(grew))
      ord[pid] = NR
      next }
    { printf "%06d|⚠ %s  %s,,orange\n", NR, t12($2), rest(3) }
    END { for (pid in spike) if (!(pid in killed)) printf "%06d|%s\n", ord[pid], spike[pid] }
  ' | sort -t'|' -k1,1rn | head -6 | cut -d'|' -f2-)
if [[ -n "$events" ]]; then
  while IFS= read -r line; do
    color="${line##*,,}"; text="${line%,,*}"
    log_row "${text:0:82}" "$MEM/guard.log" "color=${color} size=12"
  done <<< "$events"
else
  echo "Quiet — no events in the last 24h | color=gray size=12"
fi

echo "Guard details"
echo "-- Open guard log | bash=/usr/bin/open param1=-t param2=\"$MEM/guard.log\" terminal=false"
forensics=$(ls -t "$MEM"/*/guard-critical-*.log 2>/dev/null | head -1)
[[ -n "$forensics" ]] && echo "-- Latest forensics report ($(mtime "$forensics")) | bash=/usr/bin/open param1=-t param2=\"$forensics\" terminal=false"
if [[ -e "$PAUSE_FLAG" ]]; then
  echo "-- Resume guard | bash=/bin/rm param1=\"$PAUSE_FLAG\" terminal=false refresh=true color=orange"
else
  echo "-- Pause guard | bash=/usr/bin/touch param1=\"$PAUSE_FLAG\" terminal=false refresh=true"
fi

echo "---"
echo "AUTO-CLEAN | size=11 color=gray"

echo "Memory — last run $(mtime "$MEM/auto-clean.log")"
echo "-- Open memory auto-clean log | bash=/usr/bin/open param1=-t param2=\"$MEM/auto-clean.log\" terminal=false"
[[ -e "$MEM/reclaim.log" ]] && echo "-- Open reclaim log ($(mtime "$MEM/reclaim.log")) | bash=/usr/bin/open param1=-t param2=\"$MEM/reclaim.log\" terminal=false"

last_free=$(grep -E "DONE — freed" "$STO/auto-clean.log" 2>/dev/null | tail -1 | sed -E 's/^ *DONE — //; s/\.$//')
echo "Storage — ${last_free:-no runs yet}, $(mtime "$STO/auto-clean.log")"
echo "-- Open storage auto-clean log | bash=/usr/bin/open param1=-t param2=\"$STO/auto-clean.log\" terminal=false"
[[ -e "$STO/login-items-audit.log" ]] && echo "-- Open login-items audit | bash=/usr/bin/open param1=-t param2=\"$STO/login-items-audit.log\" terminal=false"

echo "---"
echo "Refresh now | refresh=true"
