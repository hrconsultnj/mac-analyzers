#!/usr/bin/env bash
# network-snapshot.sh — read-only top-talkers snapshot (ANALYZER: observes,
# never acts). Uses nettop's per-process counters, which are CUMULATIVE since
# each process launched — so this answers "who has moved the most data",
# not "who is fast right now". No sudo, no packet inspection, nothing leaves
# the machine.
#
# Usage:
#   ./network-snapshot.sh            # top 25, prints table + appends to log
#   ./network-snapshot.sh 50         # top 50
#
# Log: ~/mac-analyzers/reports/network/top-talkers.log (run blocks, ====-separated)
set -euo pipefail

OUT_DIR="${HOME}/mac-analyzers/reports/network"
mkdir -p "${OUT_DIR}"
LOG_FILE="${OUT_DIR}/top-talkers.log"
LIMIT="${1:-25}"
STAMP="$(date '+%Y-%m-%d %H:%M')"

{
  echo "================================================================"
  echo "${STAMP} | network snapshot | cumulative bytes since process launch"
  nettop -P -x -L 1 -J bytes_in,bytes_out 2>/dev/null | awk -F',' -v limit="${LIMIT}" '
    NR > 1 && $1 != "" {
      name = $1; pid = $1
      sub(/\.[0-9]+$/, "", name)
      sub(/^.*\./, "", pid)
      bin = $2 + 0; bout = $3 + 0
      total = bin + bout
      if (total > 0) {
        rows[NR] = sprintf("%s pid=%s in=%d out=%d", name, pid, bin, bout)
        keys[NR] = total
        ti += bin; to += bout
      }
    }
    END {
      printf "TOTAL in=%d out=%d\n", ti, to
      for (i = 0; i < limit; i++) {
        best = -1; bi = 0
        for (k in keys) if (keys[k] > best) { best = keys[k]; bi = k }
        if (bi == 0) break
        print rows[bi]
        delete keys[bi]
      }
    }'
} | tee -a "${LOG_FILE}"
