# Excerpt: memory-reclaim.sh — the "free my RAM now" preview

Real dry-run output (username and project names anonymized). Note the
live-session protection: the AI coding session that happens to be running —
and all its MCP servers — are exempted automatically, no matter how the
script is invoked.

```
==================================================================
 memory-reclaim  |  DRY RUN  |  apps=no  |  2026-07-30 17:20:41
 input: flags: (none — defaults)
 exempt: 3 live Claude/Codex session(s) + their MCP servers (roots: 44671 54803 42141)
==================================================================

### 2. Sweeping dev tooling (MCP servers, dev servers, playwright, node tools)
  [DRY]       87 MB  pid=6171   ~/.deno/bin/deno lsp
  [DRY]       39 MB  pid=6179   ~/.deno/bin/deno lsp
  [DRY]      146 MB  pid=21284  next-server (v16.2.11)
  [DRY]       46 MB  pid=21255  node ~/.nvm/versions/node/v24.16.0/bin/pnpm run dev
  [DRY]       45 MB  pid=21278  node ~/Projects/project-a/apps/web/node_modules/.bin/../next/dist/bin/next dev
  [DRY]       30 MB  pid=95170  next-server (v16.2.7)          <- forgotten since yesterday
  [EXEMPT]  pid=42153  npm exec @upstash/context7-mcp
  [EXEMPT]  pid=42997  node ~/.npm/_npx/.../context7-mcp
  [EXEMPT]  pid=43278  node ~/.npm/_npx/.../mcp-server-sequential-thinking

==================================================================
 DRY RUN — would reclaim ~1353 MB resident across 26 process(es). Re-run with --apply.
==================================================================
```

Resident MB understates the real reclaim: the compressed and swapped pages
these processes hold drain too once they exit — on the session that produced
this excerpt, a sweep + app quits took Activity Monitor's "Memory Used" from
25.15 GB to 19.22 GB (compressed: 8.32 → 3.33 GB).
