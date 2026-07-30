#!/usr/bin/env bash
# Memory analyzer for macOS — READ-ONLY.
# Explains where physical RAM is going: Activity-Monitor-style breakdown,
# compressor/swap state, per-app aggregation (helpers rolled up), Electron
# census, node/dev-tooling processes, and a heuristic diagnosis.
# This script never kills, restarts, or modifies anything.
#
# Usage: ./analyze.sh [output_dir]
#   default output_dir: ~/memory-reports

set -u

HOME_DIR="${HOME}"
OUT_DIR="${1:-${HOME_DIR}/system-reports/memory}"
DATE_DIR="${OUT_DIR}/$(date +%Y-%m-%d)"
REPORT="${DATE_DIR}/report-$(date +%H%M).md"
LATEST="${OUT_DIR}/latest.md"

mkdir -p "${DATE_DIR}"

PAGE_SIZE=$(sysctl -n vm.pagesize)          # 16384 on Apple Silicon
TOTAL_BYTES=$(sysctl -n hw.memsize)

# Snapshot vm_stat ONCE so every section reads the same instant
VMSTAT="$(vm_stat)"

# ---------- helpers ----------
pages() {  # pages "Pages wired down"
  echo "$VMSTAT" | awk -v key="$1" -F':' '$1==key {gsub(/[^0-9]/,"",$2); print $2; found=1} END{if(!found) print 0}'
}

# pages → GB string (2 decimals)
p2gb() { awk -v p="$1" -v ps="$PAGE_SIZE" 'BEGIN{printf "%.2f", p*ps/1073741824}'; }
# bytes → GB string
b2gb() { awk -v b="$1" 'BEGIN{printf "%.2f", b/1073741824}'; }

section() { echo ""; echo "## $1"; echo ""; }

# run a command with a timeout (macOS ships no `timeout`) — same as storage-analyzer
timed() {
  local secs="$1"; shift
  local tmpf; tmpf="$(mktemp)"
  ( "$@" >"$tmpf" 2>&1 ) & local pid=$!
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1; i=$((i+1))
    if [[ $i -ge $secs ]]; then
      kill -9 "$pid" 2>/dev/null
      echo "(timed out after ${secs}s — skipped)"
      rm -f "$tmpf"; return 124
    fi
  done
  wait "$pid" 2>/dev/null
  cat "$tmpf"; rm -f "$tmpf"
}

# ---------- derive the Activity-Monitor numbers ----------
P_FREE=$(pages "Pages free")
P_ACTIVE=$(pages "Pages active")
P_INACTIVE=$(pages "Pages inactive")
P_SPECULATIVE=$(pages "Pages speculative")
P_WIRED=$(pages "Pages wired down")
P_PURGEABLE=$(pages "Pages purgeable")
P_FILEBACKED=$(pages "File-backed pages")
P_ANON=$(pages "Anonymous pages")
P_COMP_STORED=$(pages "Pages stored in compressor")
P_COMP_OCCUPIED=$(pages "Pages occupied by compressor")

P_APP=$(( P_ANON - P_PURGEABLE ))            # Activity Monitor "App Memory"
P_CACHED=$(( P_FILEBACKED + P_PURGEABLE ))   # Activity Monitor "Cached Files"
P_USED=$(( P_APP + P_WIRED + P_COMP_OCCUPIED ))

SWAP_LINE=$(sysctl -n vm.swapusage)          # total = 4096.00M  used = 3569.94M ...
SWAP_TOTAL_MB=$(echo "$SWAP_LINE" | awk '{gsub(/M/,"",$3); print $3}')
SWAP_USED_MB=$(echo  "$SWAP_LINE" | awk '{gsub(/M/,"",$6); print $6}')
SWAP_PCT=$(awk -v u="$SWAP_USED_MB" -v t="$SWAP_TOTAL_MB" 'BEGIN{if(t>0) printf "%.0f", u*100/t; else print 0}')

COMP_RATIO=$(awk -v s="$P_COMP_STORED" -v o="$P_COMP_OCCUPIED" 'BEGIN{if(o>0) printf "%.1f", s/o; else print "-"}')
COMP_SHARE=$(awk -v c="$P_COMP_OCCUPIED" -v u="$P_USED" 'BEGIN{if(u>0) printf "%.0f", c*100/u; else print 0}')

# total demand = what apps have actually allocated, counted at full size
DEMAND_GB=$(awk -v a="$P_ANON" -v w="$P_WIRED" -v s="$P_COMP_STORED" -v ps="$PAGE_SIZE" -v sw="$SWAP_USED_MB" \
  'BEGIN{printf "%.1f", (a+w+s)*ps/1073741824 + sw/1024}')

# kernel pressure level: 1 = normal, 2 = warning, 4 = critical
PRESSURE_LEVEL=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo "?")
case "$PRESSURE_LEVEL" in
  1) PRESSURE_TXT="NORMAL (green)" ;;
  2) PRESSURE_TXT="WARNING (yellow)" ;;
  4) PRESSURE_TXT="CRITICAL (red)" ;;
  *) PRESSURE_TXT="unknown ($PRESSURE_LEVEL)" ;;
esac
FREE_PCT=$(memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/ {print $2}')

# ---------- begin report ----------
{
  echo "# Memory Analyzer Report"
  echo ""
  echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "**Host:** $(hostname)"
  echo "**User:** ${USER}"
  echo "**Invocation:** analyze.sh${1:+ $1}$( [[ -t 0 ]] && echo " (interactive)" )"
  echo ""
  echo "> Read-only snapshot. No processes were touched."
  echo ""

  # ---------- 1. Headline ----------
  section "1. Headline"
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Physical RAM | $(b2gb "$TOTAL_BYTES") GB |"
  echo "| Memory used (App + Wired + Compressed) | $(p2gb "$P_USED") GB |"
  echo "| Cached files (reclaimable) | $(p2gb "$P_CACHED") GB |"
  echo "| Free | $(p2gb "$P_FREE") GB |"
  echo "| Memory pressure | ${PRESSURE_TXT} |"
  echo "| System-wide free % (incl. reclaimable) | ${FREE_PCT:-?} |"
  echo ""
  echo '```'
  top -l 1 -n 0 2>/dev/null | grep -E "PhysMem|VM:"
  echo '```'
  echo ""
  echo "_\"Used\" being high is not itself a problem — macOS keeps RAM full on purpose._"
  echo "_The signals that matter: **pressure level**, **swap fill**, and **compressor share** (sections 3-4, 10)._"

  # ---------- 2. Activity-Monitor-style breakdown ----------
  section "2. Where the Used RAM Sits (Activity Monitor formula)"
  echo "| GB | Component | Meaning |"
  echo "|----|-----------|---------|"
  echo "| $(p2gb "$P_APP") | App Memory | anonymous pages apps allocated, minus purgeable |"
  echo "| $(p2gb "$P_WIRED") | Wired | kernel + drivers, can never be paged out |"
  echo "| $(p2gb "$P_COMP_OCCUPIED") | Compressed | RAM occupied by the compressor (see §3) |"
  echo "| **$(p2gb "$P_USED")** | **= Memory Used** | the Activity Monitor headline number |"
  echo "| $(p2gb "$P_CACHED") | Cached Files | file cache — dropped instantly if apps need it |"
  echo "| $(p2gb "$P_FREE") | Free | truly unused |"

  # ---------- 3. Compressor ----------
  section "3. Memory Compressor"
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Data held (uncompressed size) | $(p2gb "$P_COMP_STORED") GB |"
  echo "| RAM actually occupied | $(p2gb "$P_COMP_OCCUPIED") GB |"
  echo "| Compression ratio | ${COMP_RATIO}:1 |"
  echo "| Share of \"Memory Used\" | ${COMP_SHARE}% |"
  echo ""
  echo "_The compressor squeezes idle app pages instead of swapping them. A large_"
  echo "_compressor means apps allocated far more than fits — the memory belongs to_"
  echo "_long-idle windows/tabs/helpers, not to what you're actively using._"

  # ---------- 4. Swap ----------
  section "4. Swap"
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Swap file | ${SWAP_TOTAL_MB} MB total, ${SWAP_USED_MB} MB used (${SWAP_PCT}%) |"
  echo "| Lifetime swap-ins / swap-outs | $(top -l 1 -n 0 2>/dev/null | grep "VM:" | awk '{print $7, "in /", $9, "out"}') |"
  echo ""
  echo "_(0) after the swap counters in §1 means no swapping is happening right now —_"
  echo "_a full swapfile records past pressure, not necessarily current trouble._"

  # ---------- 5. Total demand vs physical RAM ----------
  section "5. Total Memory Demand vs Physical RAM"
  echo "| GB | What |"
  echo "|----|------|"
  echo "| $(p2gb "$P_ANON") | Anonymous (app) pages resident |"
  echo "| $(p2gb "$P_WIRED") | Wired |"
  echo "| $(p2gb "$P_COMP_STORED") | Compressed data, at full size |"
  echo "| $(awk -v m="$SWAP_USED_MB" 'BEGIN{printf "%.2f", m/1024}') | Swapped out (at least) |"
  echo "| **${DEMAND_GB}** | **Total demand** vs **$(b2gb "$TOTAL_BYTES") GB physical** |"
  echo ""
  OVERCOMMIT=$(awk -v d="$DEMAND_GB" -v t="$TOTAL_BYTES" 'BEGIN{printf "%.1f", d/(t/1073741824)}')
  echo "_Running apps have allocated **${OVERCOMMIT}×** the machine's physical RAM._"

  # ---------- 6. Top 25 processes by resident memory ----------
  section "6. Top 25 Processes (resident memory)"
  echo "_RSS only — compressed/swapped pages of an idle process do NOT show here,_"
  echo "_which is why these numbers won't sum to §1's Used._"
  echo ""
  echo "| RSS | PID | Uptime | Process |"
  echo "|-----|-----|--------|---------|"
  ps axo rss,pid,etime,comm | sort -rn | head -25 | awk '{
    rss=$1; pid=$2; et=$3; $1=$2=$3=""; sub(/^ +/,"");
    name=$0; n=split(name, parts, "/"); short=parts[n];
    if (n>3 && index(name,".app")>0) { match(name, /[^\/]+\.app/); short=substr(name,RSTART,RLENGTH-4) " · " short }
    printf "| %.0f MB | %s | %s | %s |\n", rss/1024, pid, et, short
  }'

  # ---------- 7. Per-app aggregate ----------
  section "7. Per-App Totals (helper processes rolled up)"
  echo "_Chrome/VS Code/Electron apps split into dozens of helpers — this is the real ranking._"
  echo ""
  echo "| Total RSS | Processes | App |"
  echo "|-----------|-----------|-----|"
  ps axo rss,comm | awk '
    NR>1 {
      rss=$1; $1=""; cmd=$0;
      if (match(cmd, /\/Applications\/[^\/]+\.app/)) app=substr(cmd, RSTART+14, RLENGTH-18);
      else if (match(cmd, /\/System\/Applications\/[^\/]+\.app/)) app=substr(cmd, RSTART+21, RLENGTH-25);
      else { n=split(cmd, parts, "/"); app=parts[n] }
      gsub(/^ +| +$/, "", app);
      mem[app]+=rss; cnt[app]++
    }
    END { for (a in mem) printf "%d\t%d\t%s\n", mem[a], cnt[a], a }
  ' | sort -rn | head -25 | awk -F'\t' '{printf "| %.0f MB | %d | %s |\n", $1/1024, $2, $3}'

  # ---------- 8. Electron / embedded-Chromium census ----------
  section "8. Electron / Embedded-Chromium Apps Running"
  echo "_Each of these ships its own Chromium runtime — every one is a browser in disguise._"
  echo ""
  echo "| Total RSS | Processes | App |"
  echo "|-----------|-----------|-----|"
  ps axo rss,comm | awk '
    /\/Applications\/[^\/]+\.app/ {
      rss=$1; $1=""; cmd=$0;
      match(cmd, /\/Applications\/[^\/]+\.app/); app=substr(cmd, RSTART, RLENGTH);
      mem[app]+=rss; cnt[app]++
    }
    END { for (a in mem) printf "%d\t%d\t%s\n", mem[a], cnt[a], a }
  ' | sort -rn | while IFS=$'\t' read -r rsskb nproc apppath; do
    # Electron/CEF frameworks can be nested (Docker Desktop.app inside Docker.app)
    if find "$apppath" -maxdepth 6 \( -name "Electron Framework.framework" -o -name "Chromium Embedded Framework.framework" \) -print -quit 2>/dev/null | grep -q .; then
      name="${apppath##*/}"; name="${name%.app}"
      awk -v r="$rsskb" -v n="$nproc" -v a="$name" 'BEGIN{printf "| %.0f MB | %d | %s |\n", r/1024, n, a}'
    fi
  done
  echo ""
  echo "_(True browsers like Chrome/Opera/Safari are not Electron and appear only in §7.)_"

  # ---------- 9. node & dev-tooling processes ----------
  section "9. node / Dev-Tooling Processes"
  echo "_Dev servers, MCP servers, language servers. Duplicates across sessions add up;_"
  echo "_a dev server or MCP trio you forgot about is the most common silent RAM holder._"
  echo ""
  echo "| RSS | PID | Uptime | Command |"
  echo "|-----|-----|--------|---------|"
  ps axo rss,pid,etime,args | grep -E "node|bun |deno " | grep -vE "grep|node_exporter" | sort -rn | head -30 | awk '{
    rss=$1; pid=$2; et=$3; $1=$2=$3=""; sub(/^ +/,"");
    cmd=$0; gsub(/\|/,"\\|",cmd);
    if (length(cmd)>95) cmd=substr(cmd,1,92) "...";
    printf "| %.0f MB | %s | %s | `%s` |\n", rss/1024, pid, et, cmd
  }'

  # ---------- 10. Docker ----------
  section "10. Docker"
  if pgrep -qf "com.docker.backend"; then
    DOCKER_KB=$(ps axo rss,comm | awk '/[Dd]ocker/ {s+=$1} END{print s+0}')
    echo "Docker Desktop total footprint: $(awk -v k="$DOCKER_KB" 'BEGIN{printf "%.1f GB", k/1048576}') (VM memory is inside these processes)"
    echo ""
    echo "**Per-container (\`docker stats\`):**"
    echo '```'
    DSTATS=$(timed 12 docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}")
    if [[ -n "${DSTATS//[[:space:]]/}" ]]; then echo "$DSTATS"; else echo "(no running containers)"; fi
    echo '```'
    echo ""
    echo "_Docker's VM reserves its configured memory ceiling regardless of container load —_"
    echo "_check Docker Desktop → Settings → Resources if the footprint looks oversized._"
  else
    echo "_Docker not running._"
  fi

  # ---------- 11. Long-running heavy holders ----------
  section "11. Long-Running Heavy Holders (>150 MB resident, up >1 day)"
  echo "_Restart candidates: long-lived processes accumulate heap they rarely return,_"
  echo "_and their idle pages are what fills the compressor and swap._"
  echo ""
  echo "| RSS | Uptime | Process |"
  echo "|-----|--------|---------|"
  ps axo rss,etime,comm | awk '$1 > 153600 && $2 ~ /-/ {
    rss=$1; et=$2; $1=$2=""; sub(/^ +/,"");
    name=$0; n=split(name, parts, "/"); short=parts[n];
    if (index(name,".app")>0) { match(name, /[^\/]+\.app/); short=substr(name,RSTART,RLENGTH-4) " · " short }
    printf "| %.0f MB | %s | %s |\n", rss/1024, et, short
  }' | sort -t'|' -k2 -rn | head -20

  # ---------- 12. CPU & energy snapshot ----------
  section "12. CPU & Energy Snapshot"
  NCPU=$(sysctl -n hw.ncpu)
  LOAD1=$(sysctl -n vm.loadavg | awk '{print $2}')
  echo "**Load averages:** $(sysctl -n vm.loadavg | tr -d '{}') on ${NCPU} cores  _(sustained 1-min load > cores = CPU-bound)_"
  echo ""
  echo "_Energy impact ≈ CPU over time. Memory pressure itself burns CPU (compressor churn),_"
  echo "_so high energy + high compressed memory usually share one cause. Note: Activity_"
  echo "_Monitor + sysmond + WindowServer graphing can themselves cost >100% CPU while open._"
  echo ""
  echo "**Top 12 by current CPU:**"
  echo ""
  echo "| %CPU | PID | Uptime | Process |"
  echo "|------|-----|--------|---------|"
  ps axo pcpu,pid,etime,comm | sort -rn | head -12 | awk '{
    pc=$1; pid=$2; et=$3; $1=$2=$3=""; sub(/^ +/,"");
    name=$0; n=split(name, parts, "/"); short=parts[n];
    if (n>3 && index(name,".app")>0) { match(name, /[^\/]+\.app/); short=substr(name,RSTART,RLENGTH-4) " · " short }
    printf "| %.1f%% | %s | %s | %s |\n", pc, pid, et, short
  }'
  echo ""
  echo "**Top 10 by cumulative CPU time (energy hogs since launch):**"
  echo ""
  echo "| CPU time | Uptime | Process |"
  echo "|----------|--------|---------|"
  ps axo cputime,etime,comm | sort -t: -k1 -rn | head -10 | awk '{
    ct=$1; et=$2; $1=$2=""; sub(/^ +/,"");
    name=$0; n=split(name, parts, "/"); short=parts[n];
    if (n>3 && index(name,".app")>0) { match(name, /[^\/]+\.app/); short=substr(name,RSTART,RLENGTH-4) " · " short }
    printf "| %s | %s | %s |\n", ct, et, short
  }'

  # ---------- 13. Diagnosis ----------
  section "13. Diagnosis"
  if awk -v l="$LOAD1" -v c="$NCPU" 'BEGIN{exit !(l>c)}'; then
    echo "- ⚠️ **CPU-bound right now**: 1-min load ${LOAD1} exceeds ${NCPU} cores — see §12 for who."
  else
    echo "- ✅ CPU load healthy (${LOAD1} on ${NCPU} cores)."
  fi
  if [[ "$PRESSURE_LEVEL" == "1" ]]; then
    echo "- ✅ **Memory pressure is NORMAL** — the system is coping; high \"used\" is macOS working as designed."
  elif [[ "$PRESSURE_LEVEL" == "2" ]]; then
    echo "- ⚠️ **Memory pressure is at WARNING** — the system is actively compressing/swapping; expect slowdowns."
  elif [[ "$PRESSURE_LEVEL" == "4" ]]; then
    echo "- 🔴 **Memory pressure is CRITICAL** — quit heavy apps now; the system is thrashing."
  fi
  if [[ "$SWAP_PCT" -ge 80 ]]; then
    echo "- ⚠️ **Swap is ${SWAP_PCT}% full** (${SWAP_USED_MB} MB) — demand exceeded physical RAM at some point. If swap-ins/outs in §1 show (0), it's historical, not active."
  elif [[ "$SWAP_PCT" -ge 40 ]]; then
    echo "- ℹ️ Swap is ${SWAP_PCT}% used — moderate past pressure."
  else
    echo "- ✅ Swap barely used (${SWAP_PCT}%)."
  fi
  if [[ "$COMP_SHARE" -ge 35 ]]; then
    echo "- ⚠️ **Compressor holds ${COMP_SHARE}% of used RAM** ($(p2gb "$P_COMP_OCCUPIED") GB holding $(p2gb "$P_COMP_STORED") GB of idle app data) — a large share of \"used\" memory is idle windows/tabs/sessions, not active work. Quitting idle apps releases it."
  else
    echo "- ✅ Compressor share is modest (${COMP_SHARE}%)."
  fi
  echo "- Total allocation demand is **${DEMAND_GB} GB against $(b2gb "$TOTAL_BYTES") GB physical** (${OVERCOMMIT}×). Reduce demand via §7 (heaviest apps), §8 (Electron count), §9 (forgotten dev/MCP processes)."

  echo ""
  echo "---"
  echo ""
  echo "_Report ends. Nothing was modified — act on §7-§11 with your own judgment._"
} > "${REPORT}"

ln -sfn "${REPORT}" "${LATEST}"

echo "Report written to: ${REPORT}"
echo "Latest symlink:    ${LATEST}"

# ---------- interactive follow-through (double-click / bare terminal run) ----------
if [[ -t 0 ]] || [[ "${FORCE_INTERACTIVE:-0}" == "1" ]]; then
  read -rp "Open the report now? [Y/n] " yn
  [[ ! "$yn" =~ ^[Nn]$ ]] && open "${REPORT}"
  read -rp "Done — press Enter to close this window… " _
fi
