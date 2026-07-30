# Excerpt: memory analyze.sh — the sick state that started this toolkit

Same machine, earlier the same day: "Activity Monitor says 23 GB and things
freeze during meetings." The report shows WHY — half of "used" was the
compressor holding idle dead weight, and swap had filled.

## 2. Where the Used RAM Sits

| GB | Component | Meaning |
|----|-----------|---------|
| 8.12 | App Memory | anonymous pages apps allocated, minus purgeable |
| 2.91 | Wired | kernel + drivers, can never be paged out |
| 11.04 | Compressed | RAM occupied by the compressor |
| **22.08** | **= Memory Used** | the Activity Monitor headline number |

## 3. Memory Compressor

| Metric | Value |
|--------|-------|
| Data held (uncompressed size) | 23.07 GB |
| RAM actually occupied | 11.04 GB |
| Compression ratio | 2.1:1 |
| Share of "Memory Used" | 50% |

## 12. Diagnosis

- ✅ Memory pressure is NORMAL — the system is coping.
- ⚠️ **Swap is 87% full** (3569.94 MB) — demand exceeded physical RAM at some point.
- ⚠️ **Compressor holds 50% of used RAM** (11.04 GB holding 23.07 GB of idle
  app data) — a large share of "used" memory is idle windows/tabs/sessions,
  not active work. Quitting idle apps releases it.
- Total allocation demand is **37.7 GB against 32.00 GB physical** (1.2×).

The per-app rollup (§7) then names the holders: 41 editor helper processes,
22 browser processes across abandoned workspaces, triplicated MCP servers,
and a container VM idling at 5 GB with zero containers. The daily reaper +
manual reclaim exist to keep this state from returning.
