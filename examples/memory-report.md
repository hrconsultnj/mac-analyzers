# Excerpt: memory analyze.sh — healthy under real load

Real output, 32 GB M2 Mac Studio running 24 containers (two full local dev
stacks), two editor windows, a browser, and an AI coding session.

## 1. Headline

| Metric | Value |
|--------|-------|
| Physical RAM | 32.00 GB |
| Memory used (App + Wired + Compressed) | 21.60 GB |
| Cached files (reclaimable) | 9.73 GB |
| Free | 0.12 GB |
| Memory pressure | NORMAL (green) |
| System-wide free % (incl. reclaimable) | 81% |

## 3. Memory Compressor

| Metric | Value |
|--------|-------|
| Data held (uncompressed size) | 7.10 GB |
| RAM actually occupied | 3.43 GB |
| Compression ratio | 2.1:1 |
| Share of "Memory Used" | 16% |

## 13. Diagnosis

- ✅ CPU load healthy (2.99 on 12 cores).
- ✅ **Memory pressure is NORMAL** — the system is coping; high "used" is macOS working as designed.
- ✅ Swap barely used (0%).
- ✅ Compressor share is modest (16%).
- Total allocation demand is **25.4 GB against 32.00 GB physical** (0.8×).

> "Free 0.12 GB" is not a problem — the 9.7 GB file cache is handed back
> instantly on demand. Pressure + swap are the numbers that matter.
