#!/usr/bin/env node
// composure-check source-sha256:8746a6b1bad14d26e2297e6e0b8eda65d2c887d242d318331245bc481eed0789 esbuild:0.27.7
import { createRequire } from 'module'; const require = createRequire(import.meta.url);

// check/composure-check.mjs
import { existsSync as existsSync4, readFileSync as readFileSync7 } from "node:fs";
import { dirname, join as join7, resolve as resolve3 } from "node:path";
import { fileURLToPath } from "node:url";

// lib/check/rules.mjs
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

// lib/check/git.mjs
import { spawnSync } from "node:child_process";
var EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904";
var BASE_ARGS = ["-c", "core.quotepath=false", "-c", "core.safecrlf=false"];
function runGit(args, { cwd, input, buffer = false } = {}) {
  const r = spawnSync("git", [...BASE_ARGS, ...args], {
    cwd,
    input,
    ...buffer ? {} : { encoding: "utf8" },
    maxBuffer: 1 << 30,
    windowsHide: true,
    stdio: ["pipe", "pipe", "pipe"]
  });
  if (r.error) throw new Error(`git ${args[0]} could not run: ${r.error.message}`);
  return r;
}
function gitOut(args, opts = {}) {
  const r = runGit(args, opts);
  if (r.status !== 0) {
    const err2 = String(r.stderr ?? "").trim() || `exit ${r.status}`;
    throw new Error(`git ${args.join(" ")} failed: ${err2}`);
  }
  return r.stdout;
}
function gitRoot(cwd) {
  const r = runGit(["rev-parse", "--show-toplevel"], { cwd });
  if (r.status !== 0) return null;
  return String(r.stdout).trim() || null;
}
function hasHead(cwd) {
  return runGit(["rev-parse", "--verify", "-q", "HEAD"], { cwd }).status === 0;
}
function revParse(cwd, rev) {
  const r = runGit(["rev-parse", "--verify", "-q", `${rev}^{commit}`], { cwd });
  return r.status === 0 ? String(r.stdout).trim() : null;
}
function catBatch(cwd, specs) {
  const out2 = /* @__PURE__ */ new Map();
  const wanted = [...new Set(specs)].filter((s) => !/[\n\r]/.test(s));
  if (wanted.length === 0) return out2;
  const r = runGit(["cat-file", "--batch"], { cwd, input: wanted.join("\n") + "\n", buffer: true });
  if (r.status !== 0) throw new Error(`git cat-file --batch failed: ${String(r.stderr).trim()}`);
  const buf = r.stdout;
  let pos = 0;
  for (const spec of wanted) {
    const nl = buf.indexOf(10, pos);
    if (nl < 0) throw new Error("git cat-file --batch: output ended early");
    const header = buf.toString("utf8", pos, nl);
    pos = nl + 1;
    const parts = header.split(" ");
    if (parts.length < 3 || parts[1] !== "blob") {
      out2.set(spec, null);
      if (parts[1] === "tree" || parts[1] === "commit" || parts[1] === "tag") pos += Number(parts[2]) + 1;
      continue;
    }
    const size = Number(parts[2]);
    out2.set(spec, buf.subarray(pos, pos + size));
    pos += size + 1;
  }
  return out2;
}
function sizeBatch(cwd, specs) {
  const out2 = /* @__PURE__ */ new Map();
  const wanted = [...new Set(specs)].filter((s) => !/[\n\r]/.test(s));
  if (wanted.length === 0) return out2;
  const r = runGit(["cat-file", "--batch-check"], { cwd, input: wanted.join("\n") + "\n" });
  if (r.status !== 0) throw new Error(`git cat-file --batch-check failed: ${String(r.stderr).trim()}`);
  const lines = String(r.stdout).split("\n");
  wanted.forEach((spec, i) => {
    const parts = (lines[i] ?? "").split(" ");
    out2.set(spec, parts[1] === "blob" ? Number(parts[2]) : null);
  });
  return out2;
}

// ../defaults/languages/registry.json
var registry_default = {
  frontendPriority: [
    "nextjs",
    "expo",
    "angular",
    "nuxt",
    "svelte",
    "astro",
    "vite"
  ],
  typescript: {
    label: "TypeScript / JavaScript",
    extensions: [
      ".ts",
      ".tsx",
      ".js",
      ".jsx"
    ],
    graphOnlyExtensions: [
      ".mjs",
      ".cjs",
      ".mts",
      ".cts"
    ],
    grammar: "tree-sitter-typescript",
    grammarByExtension: {
      ".ts": "typescript",
      ".tsx": "tsx",
      ".js": "javascript",
      ".jsx": "jsx",
      ".mjs": "javascript",
      ".cjs": "javascript",
      ".mts": "typescript",
      ".cts": "typescript"
    },
    detectionFiles: [
      "package.json",
      "tsconfig.json"
    ],
    frameworks: {
      next: {
        id: "nextjs",
        slot: "frontend",
        conventions: "skills/_shared/references/frameworks/nextjs.md"
      },
      expo: {
        id: "expo",
        slot: "frontend",
        conventions: "skills/_shared/references/frameworks/expo.md"
      },
      "expo-router": {
        id: "expo",
        slot: "frontend",
        conventions: "skills/_shared/references/frameworks/expo.md"
      },
      "@angular/core": {
        id: "angular",
        slot: "frontend",
        conventions: "skills/_shared/references/frameworks/angular.md"
      },
      nuxt: {
        id: "nuxt",
        slot: "frontend"
      },
      svelte: {
        id: "svelte",
        slot: "frontend",
        conventions: "skills/_shared/references/frameworks/svelte.md"
      },
      "@sveltejs/kit": {
        id: "svelte",
        slot: "frontend",
        conventions: "skills/_shared/references/frameworks/svelte.md"
      },
      astro: {
        id: "astro",
        slot: "frontend"
      },
      vite: {
        id: "vite",
        slot: "frontend",
        conventions: "skills/_shared/references/frameworks/vite.md"
      },
      express: {
        id: "express",
        slot: "backend"
      },
      fastify: {
        id: "fastify",
        slot: "backend"
      },
      hono: {
        id: "hono",
        slot: "backend"
      },
      "@nestjs/core": {
        id: "nestjs",
        slot: "backend"
      },
      prisma: {
        id: "prisma",
        slot: "backend"
      },
      "@prisma/client": {
        id: "prisma",
        slot: "backend"
      },
      "drizzle-orm": {
        id: "drizzle",
        slot: "backend"
      },
      pg: {
        id: "postgresql",
        slot: "backend"
      },
      postgres: {
        id: "postgresql",
        slot: "backend"
      },
      mysql2: {
        id: "mysql",
        slot: "backend"
      },
      mongoose: {
        id: "mongodb",
        slot: "backend"
      }
    },
    ruleSource: "defaults/languages/typescript.json",
    rubricDoc: null,
    conventionsDoc: null,
    signatureInputs: []
  },
  python: {
    label: "Python",
    extensions: [
      ".py"
    ],
    grammar: "tree-sitter-python",
    grammarByExtension: {
      ".py": "python"
    },
    detectionFiles: [
      "pyproject.toml",
      "requirements.txt",
      "setup.py",
      "setup.cfg"
    ],
    frameworks: {
      fastapi: {
        id: "fastapi",
        slot: "backend",
        conventions: "skills/_shared/references/frameworks/fastapi.md"
      },
      django: {
        id: "django",
        slot: "backend",
        conventions: "skills/_shared/references/frameworks/django.md"
      },
      flask: {
        id: "flask",
        slot: "backend",
        conventions: "skills/_shared/references/frameworks/flask.md"
      }
    },
    ruleSource: "defaults/languages/python.json",
    rubricDoc: "skills/_shared/references/rubrics/python.md",
    conventionsDoc: null,
    signatureInputs: ["pyproject.toml", "requirements.txt", "setup.py"]
  },
  go: {
    label: "Go",
    extensions: [
      ".go"
    ],
    grammar: "tree-sitter-go",
    grammarByExtension: {
      ".go": "go"
    },
    detectionFiles: [
      "go.mod"
    ],
    frameworks: {
      "github.com/gin-gonic/gin": {
        id: "gin",
        slot: "backend"
      },
      "github.com/labstack/echo": {
        id: "echo",
        slot: "backend"
      },
      "github.com/go-chi/chi": {
        id: "chi",
        slot: "backend"
      }
    },
    backendFallback: "stdlib",
    ruleSource: "defaults/languages/go.json",
    rubricDoc: "skills/_shared/references/rubrics/go.md",
    conventionsDoc: "skills/_shared/references/frameworks/go.md",
    signatureInputs: ["go.mod"]
  },
  rust: {
    label: "Rust",
    extensions: [
      ".rs"
    ],
    grammar: "tree-sitter-rust",
    grammarByExtension: {
      ".rs": "rust"
    },
    detectionFiles: [
      "Cargo.toml"
    ],
    frameworks: {
      axum: {
        id: "axum",
        slot: "backend",
        conventions: "skills/_shared/references/frameworks/axum.md"
      },
      "actix-web": {
        id: "actix",
        slot: "backend",
        conventions: "skills/_shared/references/frameworks/actix-web.md"
      }
    },
    ruleSource: "defaults/languages/rust.json",
    rubricDoc: "skills/_shared/references/rubrics/rust.md",
    conventionsDoc: "skills/_shared/references/frameworks/rust.md",
    signatureInputs: ["Cargo.toml"]
  },
  cpp: {
    label: "C++",
    extensions: [
      ".cpp",
      ".cc",
      ".cxx",
      ".hpp",
      ".h"
    ],
    grammar: null,
    detectionFiles: [
      "CMakeLists.txt",
      "Makefile"
    ],
    frameworks: {},
    ruleSource: "defaults/languages/cpp.json",
    rubricDoc: "skills/_shared/references/rubrics/cpp.md",
    conventionsDoc: "skills/_shared/references/frameworks/cpp.md",
    signatureInputs: ["CMakeLists.txt", "Makefile"]
  },
  swift: {
    label: "Swift",
    extensions: [
      ".swift"
    ],
    grammar: null,
    detectionFiles: [
      "Package.swift"
    ],
    frameworks: {},
    ruleSource: "defaults/languages/swift.json",
    rubricDoc: "skills/_shared/references/rubrics/swift.md",
    conventionsDoc: "skills/_shared/references/frameworks/swift.md",
    signatureInputs: ["Package.swift"]
  },
  kotlin: {
    label: "Kotlin",
    extensions: [
      ".kt",
      ".kts"
    ],
    grammar: null,
    detectionFiles: [
      "build.gradle.kts",
      "build.gradle",
      "settings.gradle.kts",
      "settings.gradle"
    ],
    frameworks: {},
    ruleSource: "defaults/languages/kotlin.json",
    rubricDoc: "skills/_shared/references/rubrics/kotlin.md",
    conventionsDoc: "skills/_shared/references/frameworks/kotlin.md",
    signatureInputs: ["build.gradle.kts", "settings.gradle.kts"]
  },
  java: {
    label: "Java",
    extensions: [
      ".java"
    ],
    grammar: null,
    detectionFiles: [
      "pom.xml",
      "build.gradle",
      "build.gradle.kts",
      "settings.gradle",
      "settings.gradle.kts"
    ],
    frameworks: {
      "spring-boot": {
        id: "spring-boot",
        slot: "backend",
        conventions: "skills/_shared/references/frameworks/java.md"
      }
    },
    ruleSource: "defaults/languages/java.json",
    rubricDoc: "skills/_shared/references/rubrics/java.md",
    conventionsDoc: "skills/_shared/references/frameworks/java.md",
    signatureInputs: ["pom.xml", "build.gradle", "build.gradle.kts"]
  },
  csharp: {
    label: "C#",
    extensions: [
      ".cs"
    ],
    graphOnlyExtensions: [
      ".csproj"
    ],
    grammar: null,
    detectionFiles: [
      "Directory.Build.props",
      "Directory.Packages.props"
    ],
    frameworks: {
      "aspnet-core": {
        id: "aspnet-core",
        slot: "backend",
        conventions: "skills/_shared/references/frameworks/csharp.md"
      }
    },
    ruleSource: "defaults/languages/csharp.json",
    rubricDoc: "skills/_shared/references/rubrics/csharp.md",
    conventionsDoc: "skills/_shared/references/frameworks/csharp.md",
    signatureInputs: ["Directory.Build.props", "Directory.Packages.props"]
  },
  sql: {
    label: "SQL",
    extensions: [
      ".sql"
    ],
    grammar: null,
    detectionFiles: [],
    frameworks: {},
    ruleSource: null,
    rubricDoc: "skills/_shared/references/rubrics/sql.md",
    conventionsDoc: "skills/_shared/references/frameworks/sql.md",
    signatureInputs: []
  },
  supabase: {
    label: "Supabase",
    extensions: [],
    grammar: null,
    detectionFiles: [
      "supabase/config.toml"
    ],
    frameworks: {
      "@supabase/supabase-js": {
        id: "supabase",
        slot: "backend"
      }
    },
    backendId: "supabase",
    ruleSource: null,
    rubricDoc: null,
    conventionsDoc: null,
    signatureInputs: ["supabase/config.toml"]
  },
  infra: {
    label: "Infrastructure",
    extensions: [],
    grammar: null,
    detectionFiles: [
      "docker-compose.yml",
      "docker-compose.yaml",
      "Chart.yaml",
      "helmfile.yaml",
      "Pulumi.yaml",
      "playbook.yml",
      "ansible.cfg",
      "k3s.yaml"
    ],
    fileDetectors: [
      {
        pattern: "k3s.yaml",
        value: "kubernetes"
      },
      {
        pattern: "Chart.yaml",
        value: "helm"
      },
      {
        pattern: "helmfile.yaml",
        value: "helm"
      },
      {
        pattern: "Pulumi.yaml",
        value: "pulumi"
      },
      {
        pattern: "playbook.yml",
        value: "ansible"
      },
      {
        pattern: "ansible.cfg",
        value: "ansible"
      },
      {
        pattern: "docker-compose.yml",
        value: "docker-compose"
      },
      {
        pattern: "docker-compose.yaml",
        value: "docker-compose"
      }
    ],
    frameworks: {},
    ruleSource: null,
    rubricDoc: null,
    conventionsDoc: null,
    signatureInputs: ["docker-compose.yml", "docker-compose.yaml", "Chart.yaml"]
  },
  monorepoConventions: "skills/_shared/references/frameworks/monorepo.md"
};

// lib/language-registry.mjs
function isLanguageEntry(value) {
  return typeof value === "object" && value !== null;
}
var REGISTRY = registry_default;
var SOURCE_EXTS = /* @__PURE__ */ new Set();
var LANG_MAP = {};
for (const [id, entry] of Object.entries(REGISTRY)) {
  if (!isLanguageEntry(entry)) continue;
  for (const ext of entry.extensions ?? []) {
    const bare = ext.slice(1);
    SOURCE_EXTS.add(bare);
    LANG_MAP[bare] = id;
  }
}

// lib/check/builtins/typescript.mjs
var tsSuppress = {
  id: "ts-suppress",
  scope: "line",
  lang: "typescript",
  names: ["ts-suppress"],
  prepare: (ctx) => ({ isTest: ctx.isTestFile }),
  lines(text, _prev, st) {
    if (st.isTest) {
      if (/\/\/\s*@ts-(ignore|nocheck)/.test(text)) {
        return [{ name: "ts-suppress", message: "@ts-ignore/@ts-nocheck detected. Use @ts-expect-error in test files (it fails when the error is fixed)." }];
      }
      return null;
    }
    if (/\/\/\s*@ts-(ignore|expect-error|nocheck)/.test(text)) {
      return [{ name: "ts-suppress", message: "TS suppression comment detected. Fix the type error. Do not suppress it." }];
    }
    return null;
  }
};
var supabaseClientQuery = {
  id: "supabase-client-query",
  scope: "line",
  lang: "typescript",
  names: ["supabase-client-query"],
  prepare(ctx) {
    const post = ctx.post() ?? "";
    const browserMarker = /['"]use client['"]/.test(post) || /\bcreateBrowserClient\b/.test(post) || /from\s+['"][^'"]*supabase\/client['"]/.test(post);
    const serverMarker = /['"]use server['"]/.test(post) || /\bcreateServerClient\b/.test(post) || /from\s+['"][^'"]*supabase\/server['"]/.test(post);
    const serverPath = /(^|\/)(functions|api)(\/|$)/.test(ctx.rel) || /(^|\/)(server|route)\.[jt]sx?$/.test(ctx.rel);
    const usesSupabaseJs = /from\s+['"]@supabase\/supabase-js['"]/.test(post);
    return { active: !serverMarker && (browserMarker || usesSupabaseJs && !serverPath) };
  },
  lines(text, _prev, st) {
    if (!st.active || !/\.from\(\s*['"]/.test(text)) return null;
    return [{
      name: "supabase-client-query",
      message: "Direct Supabase .from() query from a browser client (use client, createBrowserClient, or @supabase/supabase-js). The browser must not talk to PostgREST \u2014 fetch a GET Route Handler / API instead (catalog 00-foundation/01-data-api-disabled)."
    }];
  }
};
var componentQueryKeys = {
  id: "component-query-keys",
  scope: "line",
  lang: "typescript",
  names: ["component-query-keys"],
  prepare: (ctx) => ({
    active: /\.(tsx|jsx)$/.test(ctx.base) && /(^|\/)components?\//.test(ctx.rel) && !/(^|\/)(hooks|hooks-queries|queries|query-keys)\//.test(ctx.rel)
  }),
  lines(text, _prev, st) {
    if (!st.active || !/queryKey\s*[:=]|useQuery\s*\(|useSuspenseQuery\s*\(|useInfiniteQuery\s*\(/.test(text)) return null;
    return [{
      name: "component-query-keys",
      message: "Inline query keys / useQuery in a component. Query keys belong in the shared query-keys module and data access flows through the generated hooks (hooks/<entity>.queries.ts, cer-generate conventions) \u2014 move the key and fetch there and consume the hook in this component."
    }];
  }
};
var VALID_APP_FILES = /* @__PURE__ */ new Set([
  "page.tsx",
  "layout.tsx",
  "loading.tsx",
  "error.tsx",
  "not-found.tsx",
  "global-error.tsx",
  "template.tsx",
  "default.tsx",
  "opengraph-image.tsx",
  "twitter-image.tsx",
  "icon.tsx",
  "apple-icon.tsx",
  "sitemap.tsx",
  "robots.tsx",
  "manifest.tsx"
]);
var nextjsAppContent = {
  id: "nextjs-app-content",
  scope: "file",
  names: ["nextjs-app-content"],
  file(_post, _base, ctx) {
    if (!/^(app|src\/app)\/.*\.tsx$/.test(ctx.rel) || VALID_APP_FILES.has(ctx.base)) return [];
    return [{
      name: "nextjs-app-content",
      key: ctx.rel,
      line: 1,
      text: ctx.base,
      message: `[nextjs-app-content] Content component '${ctx.base}' belongs in components/, not app/.`
    }];
  }
};

// lib/check/builtins/go.mjs
var goPanic = {
  id: "go-panic",
  scope: "line",
  lang: "go",
  names: ["panic"],
  prepare: (ctx) => ({ active: !ctx.isTestFile && !/^package main$/m.test(ctx.post() ?? "") }),
  lines: (text, _prev, st) => st.active && /panic\(/.test(text) ? [{ name: "panic", message: "Return error instead of panicking." }] : null
};

// lib/check/builtins/rust.mjs
var rustUnsafeSafety = {
  id: "rust-unsafe-safety",
  scope: "line",
  lang: "rust",
  names: ["unsafe"],
  prepare: () => ({}),
  lines: (text, prev) => /unsafe\s*\{/.test(text) && !/\/\/\s*SAFETY:/.test(prev ?? "") ? [{ name: "unsafe", message: "unsafe block without // SAFETY: comment. Add a SAFETY comment explaining the invariants." }] : null
};

// lib/check/builtins/sql-rls.mjs
var PUBLIC_ROLES = /* @__PURE__ */ new Set(["authenticated", "anon"]);
function sqlClean(src) {
  let out2 = "";
  const keepNl = (s) => s.replace(/[^\n]/g, "");
  for (let i = 0; i < src.length; ) {
    const c = src[i], d = src[i + 1];
    if (c === "-" && d === "-") {
      while (i < src.length && src[i] !== "\n") i++;
      continue;
    }
    if (c === "/" && d === "*") {
      const start = i;
      i += 2;
      while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) i++;
      i += 2;
      out2 += " " + keepNl(src.slice(start, i));
      continue;
    }
    if (c === "'") {
      const start = i;
      i++;
      while (i < src.length) {
        if (src[i] === "'" && src[i + 1] === "'") {
          i += 2;
          continue;
        }
        if (src[i] === "'") {
          i++;
          break;
        }
        i++;
      }
      out2 += "''" + keepNl(src.slice(start, i));
      continue;
    }
    const dq = c === "$" ? /^\$(\w*)\$/.exec(src.slice(i, i + 32)) : null;
    if (dq) {
      const start = i;
      const close = src.indexOf(dq[0], i + dq[0].length);
      i = close === -1 ? src.length : close + dq[0].length;
      out2 += " " + keepNl(src.slice(start, i));
      continue;
    }
    out2 += c;
    i++;
  }
  return out2;
}
var uncond = (t) => /USING\s*\(\s*true\s*\)/i.test(t) || /WITH\s+CHECK\s*\(\s*true\s*\)/i.test(t) || /\bOR\s+true\s*\)/i.test(t);
var FIX = "Canonical predicates (content/data-patterns/pro/20-auth/rls/02-rls-patterns.md): tenant-scoped \u2014 USING ((select has_internal_privacy()) OR (select user_in_account(account_id))); user-owned \u2014 USING (user_id = (select auth.uid()) OR (select has_internal_privacy())). If this table really is seeded, read-only reference data, the SELECT policy has to be allowlisted WITH ITS REASON in ALLOWED_PUBLIC_READ (scripts/checks/check-rls-policies.mjs) rather than written unconditionally here \u2014 an unconditional WRITE is never allowlistable.";
var lineOf = (text, offset) => text.slice(0, offset).split("\n").length;
function scan(content) {
  const findings = [];
  const clean = sqlClean(content);
  let residual = "";
  let cursor = 0;
  const stmtRe = /CREATE\s+POLICY/gi;
  let m;
  while ((m = stmtRe.exec(clean)) !== null) {
    residual += clean.slice(cursor, m.index);
    let end = clean.indexOf(";", m.index);
    end = end === -1 ? clean.length : end + 1;
    const body = clean.slice(m.index, end);
    cursor = end;
    stmtRe.lastIndex = end;
    const role = /\bTO\s+([a-z_]+)/i.exec(body)?.[1]?.toLowerCase() ?? null;
    if (role !== null && !PUBLIC_ROLES.has(role)) continue;
    if (!uncond(body)) continue;
    const table = /\bON\s+(?:[\w{}]+\.)?"?([\w{}]+)"?/i.exec(body)?.[1] ?? "the table";
    const verb = /\bFOR\s+(ALL|SELECT|INSERT|UPDATE|DELETE)/i.exec(body)?.[1]?.toUpperCase() ?? "ALL";
    const who = role ?? "PUBLIC (no TO clause, which is every role \u2014 including both a browser can hold)";
    const line = lineOf(clean, m.index);
    const text = content.split("\n")[line - 1]?.trim() ?? "";
    if (/\bOR\s+true\s*\)/i.test(body)) {
      findings.push({ name: "rls-or-true", key: `or|${table}|${verb}|${role}`, line, text, message: `RLS predicate collapses to true: ${verb} on ${table} TO ${who}. \`X OR true\` is true for every row no matter what X returns, so the helper call in front of it enforces nothing \u2014 this reads as scoped and is not. Drop the \`OR true\`. ${FIX}` });
    } else {
      findings.push({ name: "rls-unconditional-public", key: `pub|${table}|${verb}|${role}`, line, text, message: `Unconditional RLS policy: ${verb} on ${table} TO ${who}. \`true\` is the absence of a predicate, not a permissive one \u2014 every logged-in user reaches every row, across every tenant. ${FIX}` });
    }
  }
  residual += clean.slice(cursor);
  if (uncond(residual)) {
    const at = residual.search(/USING\s*\(\s*true\s*\)|WITH\s+CHECK\s*\(\s*true\s*\)|\bOR\s+true\s*\)/i);
    findings.push({ name: "rls-unscoped-predicate", key: "unscoped", line: 1, text: "", message: "Unconditional RLS predicate (`USING (true)` / `WITH CHECK (true)` / `... OR true)`) with no CREATE POLICY statement in the edit, so this change does not show which role it grants. Re-send it with the whole CREATE POLICY statement included: if it is the privileged-role bypass policy the canon requires on every table, it will pass; if the role is authenticated or anon, it is the defect this rule exists for.", _at: at });
  }
  return findings;
}
var sqlRls = {
  id: "sql-rls",
  scope: "file",
  lang: "sql",
  names: ["rls-or-true", "rls-unconditional-public", "rls-unscoped-predicate"],
  file(post, base) {
    void base;
    return scan(post);
  },
  /** Findings of the base file, for the multiset subtraction. */
  fileBase(base) {
    return base === null ? [] : scan(base);
  }
};

// lib/check/builtins/imports.mjs
import { posix } from "node:path";
var EXTS = /* @__PURE__ */ new Set(["ts", "tsx", "js", "jsx", "mts", "cts"]);
var NODE_BUILTINS = /* @__PURE__ */ new Set([
  "assert",
  "async_hooks",
  "buffer",
  "child_process",
  "cluster",
  "console",
  "constants",
  "crypto",
  "dgram",
  "dns",
  "domain",
  "events",
  "fs",
  "http",
  "http2",
  "https",
  "inspector",
  "module",
  "net",
  "os",
  "path",
  "perf_hooks",
  "process",
  "punycode",
  "querystring",
  "readline",
  "repl",
  "stream",
  "string_decoder",
  "sys",
  "timers",
  "tls",
  "trace_events",
  "tty",
  "url",
  "util",
  "v8",
  "vm",
  "wasi",
  "worker_threads",
  "zlib"
]);
var isBuiltin = (spec) => spec.startsWith("node:") || NODE_BUILTINS.has(spec.split("/")[0]);
var packageRootOf = (spec) => spec.startsWith("@") ? spec.split("/").slice(0, 2).join("/") : spec.split("/")[0];
function stripJsonComments(s) {
  let out2 = "";
  let inStr = false;
  let q = "";
  for (let i = 0; i < s.length; i++) {
    const c = s[i], n = s[i + 1];
    if (inStr) {
      out2 += c;
      if (c === "\\") {
        out2 += n ?? "";
        i++;
        continue;
      }
      if (c === q) inStr = false;
      continue;
    }
    if (c === '"' || c === "'") {
      inStr = true;
      q = c;
      out2 += c;
      continue;
    }
    if (c === "/" && n === "/") {
      while (i < s.length && s[i] !== "\n") i++;
      out2 += "\n";
      continue;
    }
    if (c === "/" && n === "*") {
      i += 2;
      while (i < s.length && !(s[i] === "*" && s[i + 1] === "/")) i++;
      i++;
      continue;
    }
    out2 += c;
  }
  return out2;
}
function readJson(ctx, rel, jsonc) {
  try {
    const t = ctx.readFile(rel);
    return t === null || t === void 0 ? null : JSON.parse(jsonc ? stripJsonComments(t) : t);
  } catch {
    return null;
  }
}
function workspacePackages(ctx) {
  const names = /* @__PURE__ */ new Set();
  for (const ws of ["pnpm-workspace.yaml", "pnpm-workspace.yml"]) {
    const content = ctx.readFile(ws);
    if (!content) continue;
    for (const m of content.matchAll(/^\s*-\s*["']?([^"'\n]+)["']?/gm)) {
      const pattern = m[1].trim().replace(/\/\*$/, "");
      const single = readJson(ctx, posix.join(pattern, "package.json"));
      if (single?.name) names.add(single.name);
      for (const e of ctx.listDir(pattern)) {
        const j = readJson(ctx, posix.join(pattern, e, "package.json"));
        if (j?.name) names.add(j.name);
      }
    }
  }
  return names;
}
function facts(ctx) {
  const shared = ctx.shared.imports ??= { dirs: /* @__PURE__ */ new Map(), workspaces: null };
  shared.workspaces ??= workspacePackages(ctx);
  const dirKey = posix.dirname(ctx.rel);
  if (!shared.dirs.has(dirKey)) {
    const declared = /* @__PURE__ */ new Set();
    const aliases = /* @__PURE__ */ new Set();
    let dir = dirKey;
    for (; ; ) {
      const here = (name) => dir === "." ? name : posix.join(dir, name);
      const pkg = readJson(ctx, here("package.json"));
      if (pkg) {
        for (const k of ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]) {
          for (const d of Object.keys(pkg[k] || {})) declared.add(d);
        }
      }
      const ts = readJson(ctx, here("tsconfig.json"), true);
      for (const key of Object.keys(ts?.compilerOptions?.paths || {})) aliases.add(key.replace(/\/\*$/, ""));
      if (dir === "." || dir === "/") break;
      dir = posix.dirname(dir);
    }
    shared.dirs.set(dirKey, { declared, aliases });
  }
  return { ...shared.dirs.get(dirKey), workspaces: shared.workspaces };
}
function specOf(text) {
  if (/^\s*\/\//.test(text)) return null;
  return text.match(/^\s*import\s+(?:[^"';]+?\s+from\s+)?["']([^"']+)["']/)?.[1] ?? text.match(/\bimport\s*\(\s*["']([^"']+)["']/)?.[1] ?? text.match(/\brequire\s*\(\s*["']([^"']+)["']/)?.[1] ?? null;
}
var importsDeclared = {
  id: "imports-declared",
  scope: "line",
  exts: EXTS,
  names: ["imports-declared"],
  prepare: (ctx) => ({ ctx }),
  lines(text, _prev, st) {
    const spec = specOf(text);
    if (!spec || spec.startsWith(".") || spec.startsWith("/") || isBuiltin(spec)) return null;
    const root = packageRootOf(spec);
    const f = facts(st.ctx);
    for (const a of f.aliases) if (root === a || spec === a || spec.startsWith(a + "/")) return null;
    if (f.workspaces.has(root) || f.declared.has(root)) return null;
    return [{
      name: "imports-declared",
      message: `Import "${spec}" names a package that is not declared in package.json (Vercel/Turbopack builds fail with "Module not found"). Install it in the right workspace package: pnpm --filter <workspace> add ${root}. If it lives elsewhere on purpose, add a tsconfig path alias or re-export it through the workspace package's index.`
    }];
  }
};

// lib/check/builtins/index.mjs
var BUILTINS = Object.fromEntries(
  [tsSuppress, supabaseClientQuery, componentQueryKeys, nextjsAppContent, goPanic, rustUnsafeSafety, sqlRls, importsDeclared].map((b) => [b.id, b])
);

// lib/check/rules.mjs
var CHECKER_VERSION = "1.0.0";
var RULES_PATH = ".composure/rules.json";
var DEFAULT_SKIP = ["**/node_modules/**", "**/.next/**", "**/dist/**", "**/*.d.ts", "**/*.generated.*", "**/*.gen.*"];
var HARD_SKIP_DIRS = ["/node_modules/", "/.next/", "/dist/", "/.expo/", "/.claude/", "/.composure/", "/memory/", "/tasks-plans/", "/blueprints/"];
var TS_EXTS = ["ts", "tsx", "js", "jsx"];
var ALL_FILES = ["**/*", "*"];
function appliesRegex(pattern) {
  return new RegExp(
    "^" + pattern.replace(/\*\*/g, "__DBLSTAR__").replace(/\./g, "\\.").replace(/\*/g, "[^/]*").replace(/__DBLSTAR__/g, ".*") + "$"
  );
}
function skipRegex(pattern) {
  let re = "";
  for (let i = 0; i < pattern.length; ) {
    const c = pattern[i];
    if (c === "*" && pattern[i + 1] === "*") {
      if (pattern[i + 2] === "/") {
        re += "(?:.*/)?";
        i += 3;
      } else {
        re += ".*";
        i += 2;
      }
    } else if (c === "*") {
      re += "[^/]*";
      i++;
    } else if (c === "?") {
      re += "[^/]";
      i++;
    } else {
      re += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
      i++;
    }
  }
  return new RegExp("^" + re + "$");
}
var RulesError = class extends Error {
};
function fail(where2, msg) {
  throw new RulesError(`${where2}: ${msg}`);
}
function mustCompile(where2, what, pattern, flags = "") {
  if (typeof pattern !== "string") fail(where2, `${what} must be a string`);
  try {
    new RegExp(pattern, "m" + String(flags).replace(/[gyms]/g, ""));
  } catch (e) {
    fail(where2, `${what} is not a valid regex (${e.message})`);
  }
}
function validateRule(rule, where2) {
  if (!rule || typeof rule !== "object") fail(where2, "a rule is not an object");
  const id = `rule ${JSON.stringify(rule.name)} in ${where2}`;
  if (typeof rule.name !== "string" || !rule.name) fail(where2, "a rule has no name");
  if (rule.severity !== void 0 && rule.severity !== "error" && rule.severity !== "warn") fail(id, `severity must be "error" or "warn", got ${JSON.stringify(rule.severity)}`);
  if (rule.kind === "builtin") {
    if (typeof rule.id !== "string" || !BUILTINS[rule.id]) fail(id, `names builtin ${JSON.stringify(rule.id)}, which this checker (version ${CHECKER_VERSION}) does not have`);
  } else if (rule.kind === "regex") {
    if (rule.scope !== void 0 && rule.scope !== "line" && rule.scope !== "file") fail(id, `scope must be "line" or "file", got ${JSON.stringify(rule.scope)}`);
    if (typeof rule.pattern !== "string" || rule.pattern === "") fail(id, "has no pattern");
    mustCompile(id, "pattern", rule.pattern, rule.flags);
    if (rule.skipIf !== void 0) mustCompile(id, "skipIf", rule.skipIf);
    if (rule.skipIfPath !== void 0) mustCompile(id, "skipIfPath", rule.skipIfPath);
    if (typeof rule.message !== "string") fail(id, "has no message");
  } else {
    fail(id, `has kind ${JSON.stringify(rule.kind)}; the kinds are "regex" and "builtin"`);
  }
}
function validateRuleSet(data, where2 = "rules") {
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new RulesError(`${where2}: rules file is not a JSON object`);
  if (data.version !== 1) throw new RulesError(`${where2}: unsupported rules version ${JSON.stringify(data.version)} (this checker reads version 1)`);
  if (!Array.isArray(data.groups)) throw new RulesError(`${where2}: "groups" must be an array`);
  const need = Number(String(data.checker ?? "0").split(".")[0]);
  if (need > Number(CHECKER_VERSION.split(".")[0])) {
    throw new RulesError(`${where2}: rules need checker ${data.checker}, this is ${CHECKER_VERSION}; update the committed .composure/bin/composure-check.mjs`);
  }
  if (data.skip !== void 0 && !(Array.isArray(data.skip) && data.skip.every((s) => typeof s === "string"))) fail(where2, '"skip" must be an array of globs');
  if (data.overrides?.disabled !== void 0 && !(Array.isArray(data.overrides.disabled) && data.overrides.disabled.every((s) => typeof s === "string"))) fail(where2, '"overrides.disabled" must be an array of names');
  for (const g of data.groups) {
    if (!g || typeof g.name !== "string" || !Array.isArray(g.appliesTo) || !Array.isArray(g.rules)) fail(where2, `malformed group ${JSON.stringify(g?.name)}`);
    for (const rule of g.rules) validateRule(rule, `${where2} group "${g.name}"`);
  }
  return data;
}
function parseRules(text, where2) {
  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    throw new RulesError(`${where2}: not valid JSON (${e.message})`);
  }
  return validateRuleSet(data, where2);
}
function loadRules({ cwd, refs, fromLabel, fallback = "worktree" }) {
  const specs = refs.map((r) => `${r}:${RULES_PATH}`);
  const indexSpec = `:${RULES_PATH}`;
  if (fallback === "index") specs.push(indexSpec);
  const found = catBatch(cwd, specs);
  for (let i = 0; i < refs.length; i++) {
    const buf = found.get(specs[i]);
    if (buf) return { rules: parseRules(buf.toString("utf8"), `${refs[i]}:${RULES_PATH}`), rulesFrom: i === 0 ? fromLabel : "head" };
  }
  if (fallback === "index") {
    const buf = found.get(indexSpec);
    if (buf) {
      return {
        rules: parseRules(buf.toString("utf8"), `index:${RULES_PATH}`),
        rulesFrom: "index",
        notice: `${RULES_PATH} is not in ${refs[0] ?? "HEAD"} yet, so the staged file applies (bootstrap). Commit it so every later check reads the committed rules.`
      };
    }
    return null;
  }
  if (fallback === "none") return null;
  const file = join(cwd, RULES_PATH);
  if (existsSync(file)) {
    return {
      rules: parseRules(readFileSync(file, "utf8"), RULES_PATH),
      rulesFrom: "worktree",
      notice: `${RULES_PATH} is not in ${refs[0] ?? "HEAD"} yet, so the working-tree file applies (bootstrap). Commit it so every later check reads the committed rules.`
    };
  }
  return null;
}
function loadWorktreeRules(cwd) {
  const file = join(cwd, RULES_PATH);
  return existsSync(file) ? { rules: parseRules(readFileSync(file, "utf8"), RULES_PATH), rulesFrom: "worktree" } : null;
}
function inferScope(rule) {
  if (rule.scope === "line" || rule.scope === "file") return rule.scope;
  const p = String(rule.pattern ?? "");
  const invert = rule.invertMatch === true || rule.invertMatch === "true";
  return invert || /\\n|\\r|\[\\s\\S\]|\[\^\]|\(\?s|\[\\S\\s\]/.test(p) ? "file" : "line";
}
function regexRule(rule, groupName) {
  const out2 = {
    name: rule.name || groupName,
    kind: "regex",
    scope: inferScope(rule),
    pattern: rule.pattern,
    severity: rule.severity || "warn",
    message: rule.message
  };
  if (rule.flags) out2.flags = rule.flags;
  if (rule.skipIf) out2.skipIf = rule.skipIf;
  if (rule.skipIfPath) out2.skipIfPath = rule.skipIfPath;
  if (rule.invertMatch === true || rule.invertMatch === "true") out2.invertMatch = true;
  return out2;
}
function groupFrom(name, g, origin) {
  const rules = (g.rules ?? []).filter((r) => r && r.pattern && r.message).map((r) => regexRule(r, name));
  return { name, origin, appliesTo: g.appliesTo ?? [], rules };
}
function readJson2(file) {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}
function resolveRules({ stack = {}, defaultsDir, existing = null }) {
  const overrides = {
    disabled: [.../* @__PURE__ */ new Set([...existing?.overrides?.disabled ?? [], ...stack.disabledRules ?? []])],
    skip: [.../* @__PURE__ */ new Set([...existing?.overrides?.skip ?? [], ...(stack.skipPatterns ?? []).map((p) => p.includes("/") ? p : `**/${p}`)])],
    groups: { ...legacyGroups(stack.frameworkValidation), ...existing?.overrides?.groups ?? {} }
  };
  const disabled = new Set(overrides.disabled);
  const frameworks = stack.frameworks && typeof stack.frameworks === "object" ? stack.frameworks : null;
  const known = new Set(Object.values(LANG_MAP));
  const languages = frameworks ? Object.keys(frameworks).filter((k) => known.has(k)) : ["typescript"];
  const groups = [];
  const seen = /* @__PURE__ */ new Set();
  const add = (file, origin) => {
    const data = readJson2(file);
    if (!data?.rules || Array.isArray(data.rules)) return;
    for (const [name, g] of Object.entries(data.rules)) {
      if (seen.has(name)) continue;
      seen.add(name);
      if (disabled.has(name)) continue;
      const group = groupFrom(name, g, origin);
      group.rules = group.rules.filter((r) => !disabled.has(r.name));
      if (group.rules.length) groups.push(group);
    }
  };
  const d = (...p) => join(defaultsDir, ...p);
  if (defaultsDir && existsSync(defaultsDir)) {
    add(d("shared.json"), "defaults/shared.json");
    for (const lang of languages) add(d("languages", `${lang}.json`), `defaults/languages/${lang}.json`);
    if (frameworks) {
      const frontends = /* @__PURE__ */ new Set();
      const backends = /* @__PURE__ */ new Set();
      for (const fw of Object.values(frameworks)) {
        if (fw?.frontend && fw.frontend !== "null") frontends.add(fw.frontend);
        if (fw?.backend && fw.backend !== "null") backends.add(fw.backend);
      }
      if (frontends.size > 0) {
        const feDir = d("frontend");
        if (existsSync(feDir)) {
          for (const f of readdirSync(feDir).sort()) if (f.endsWith(".json")) add(join(feDir, f), `defaults/frontend/${f}`);
        }
        if (frontends.has("nextjs")) add(d("fullstack", "nextjs.json"), "defaults/fullstack/nextjs.json");
        if (frontends.has("vite")) add(d("fullstack", "vite.json"), "defaults/fullstack/vite.json");
        if (frontends.has("expo")) add(d("mobile", "expo.json"), "defaults/mobile/expo.json");
      }
      for (const be of backends) if (be === "supabase") add(d("backend", "supabase.json"), "defaults/backend/supabase.json");
      if (frameworks.html) add(d("vanilla.json"), "defaults/vanilla.json");
      const versions = JSON.stringify(frameworks);
      if (/tanstack-query|@tanstack\/react-query/.test(versions)) add(d("sdks", "tanstack-query.json"), "defaults/sdks/tanstack-query.json");
      if (/"zod"/.test(versions)) add(d("sdks", "zod.json"), "defaults/sdks/zod.json");
    }
  }
  const builtin = (name, ids, appliesTo) => {
    const rules = ids.filter((id) => !disabled.has(id)).map((id) => ({ name: id, kind: "builtin", id, severity: "error" }));
    if (rules.length && !disabled.has(name)) groups.push({ name, origin: "builtin", appliesTo, rules });
  };
  if (languages.includes("typescript")) {
    builtin("typescript-builtins", ["ts-suppress", "supabase-client-query", "component-query-keys"], ALL_FILES);
    builtin("dependency-declarations", ["imports-declared"], [...TS_EXTS, "mts", "cts"].flatMap((e) => [`**/*.${e}`, `*.${e}`]));
  }
  if (languages.includes("typescript") && !disabled.has("eslint-ts-disable") && !disabled.has("typescript-eslint-disable")) {
    groups.push({
      name: "typescript-eslint-disable",
      origin: "builtin",
      appliesTo: TS_EXTS.flatMap((e) => [`**/*.${e}`, `*.${e}`]),
      rules: [{ name: "eslint-ts-disable", kind: "regex", scope: "line", pattern: "//\\s*eslint-disable.*@typescript-eslint", severity: "error", message: "eslint-disable for @typescript-eslint rule detected. Fix the type." }]
    });
  }
  if (languages.includes("go")) builtin("go-builtins", ["go-panic"], ALL_FILES);
  if (languages.includes("rust")) builtin("rust-builtins", ["rust-unsafe-safety"], ALL_FILES);
  builtin("sql-builtins", ["sql-rls"], ALL_FILES);
  if (frameworks && Object.values(frameworks).some((f) => f?.frontend === "nextjs")) {
    builtin("nextjs-app-content", ["nextjs-app-content"], ["app/*.tsx", "app/**/*.tsx", "src/app/*.tsx", "src/app/**/*.tsx"]);
  }
  for (const [name, g] of Object.entries(overrides.groups)) {
    if (seen.has(name) || disabled.has(name)) continue;
    seen.add(name);
    const rules = (g.rules ?? []).map((r) => r.kind ? r : regexRule(r, name)).filter((r) => !disabled.has(r.name));
    if (rules.length) groups.push({ name, origin: "overrides", appliesTo: g.appliesTo ?? [], rules });
  }
  const out2 = {
    version: 1,
    checker: CHECKER_VERSION,
    source: { composureVersion: stack.composureVersion ?? null, stackHash: stack.stackSignature?.hash ?? null },
    languages,
    overrides,
    skip: [.../* @__PURE__ */ new Set([...DEFAULT_SKIP, ...overrides.skip])],
    groups
  };
  if (stack.typegenHint) out2.typegenHint = stack.typegenHint;
  return out2;
}
function legacyGroups(fv) {
  const out2 = {};
  if (fv === void 0 || fv === null) return out2;
  if (typeof fv !== "object" || Array.isArray(fv)) throw new RulesError("frameworkValidation: must be an object of groups");
  for (const [name, g] of Object.entries(fv)) {
    if (!g || typeof g !== "object" || Array.isArray(g)) throw new RulesError(`frameworkValidation group "${name}": must be an object`);
    if (g.appliesTo !== void 0 && !(Array.isArray(g.appliesTo) && g.appliesTo.every((a) => typeof a === "string"))) throw new RulesError(`frameworkValidation group "${name}": "appliesTo" must be an array of globs`);
    if (g.rules !== void 0 && !Array.isArray(g.rules)) throw new RulesError(`frameworkValidation group "${name}": "rules" must be an array`);
    const rules = (g.rules ?? []).map((r, i) => {
      if (!r || typeof r !== "object" || Array.isArray(r)) throw new RulesError(`frameworkValidation group "${name}": rule ${i + 1} is not an object`);
      const label = `frameworkValidation group "${name}" rule ${JSON.stringify(r.name ?? `#${i + 1}`)}`;
      if (typeof r.pattern !== "string" || r.pattern === "") throw new RulesError(`${label}: has no pattern`);
      if (typeof r.message !== "string") throw new RulesError(`${label}: has no message`);
      return { ...r, ...regexRule(r, name) };
    });
    out2[name] = { appliesTo: g.appliesTo ?? [], rules };
  }
  return out2;
}
function resolveUnmigrated({ projectDir, defaultsDir, readStack }) {
  const file = join(projectDir, ".composure", "no-bandaids.json");
  const stack = (readStack ? readStack() : existsSync(file) ? readJson2(file) : null) ?? {};
  const { disabledRules: _d, skipPatterns: _s, frameworkValidation: _f, ...facts2 } = stack;
  return resolveRules({ stack: facts2, defaultsDir });
}
var UNMIGRATED_NOTICE = "unmigrated project: no committed .composure/rules.json, so the rules are resolved from the plugin defaults and the stack in .composure/no-bandaids.json (its disabledRules, skipPatterns and frameworkValidation are not read; run the user-run step `! node scripts/composure/apply-rules.mjs` (generated by /composure:initialize) to write rules.json and migrate them)";

// lib/check/diff.mjs
import { readFileSync as readFileSync2, readdirSync as readdirSync2, statSync, lstatSync, readlinkSync, realpathSync, openSync, readSync, closeSync } from "node:fs";
import { isAbsolute, join as join2, posix as posix2, relative, sep } from "node:path";
var MAX_FILE_BYTES = 1024 * 1024;
var STRICT_FILE_BYTES = 32 * 1024 * 1024;
var MAX_UNTRACKED_BYTES = STRICT_FILE_BYTES;
var MAX_LINK_HOPS = 8;
var BINARY_SNIFF = 8192;
var DIFF_FLAGS = ["--no-color", "--no-ext-diff", "--no-textconv", "--src-prefix=a/", "--dst-prefix=b/", "-U0", "-M"];
var toPosix = (p) => String(p).replace(/\\/g, "/");
var stripCr = (s) => s.endsWith("\r") ? s.slice(0, -1) : s;
var hasNul = (buf) => buf.subarray(0, BINARY_SNIFF).includes(0);
function parsePatch(text) {
  const sections = [];
  let cur = null;
  let hunk = null;
  let newLine = 0;
  for (const raw of text.split("\n")) {
    if (raw.startsWith("diff --git ")) {
      cur = { header: raw.slice("diff --git ".length), binary: false, newFile: false, mode: null, hunks: [] };
      sections.push(cur);
      hunk = null;
      continue;
    }
    if (!cur) continue;
    if (hunk === null) {
      let m;
      if (/^Binary files .* differ$/.test(raw) || /^GIT binary patch$/.test(raw)) {
        cur.binary = true;
        continue;
      }
      if (raw.startsWith("new file mode ")) {
        cur.newFile = true;
        cur.mode = raw.split(" ")[3];
        continue;
      }
      if (m = /^new mode (\d+)/.exec(raw)) {
        cur.mode = m[1];
        continue;
      }
      if ((m = /^index \S+\.\.\S+ (\d+)/.exec(raw)) && cur.mode === null) {
        cur.mode = m[1];
        continue;
      }
    }
    const h = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/.exec(raw);
    if (h) {
      hunk = { added: [], removed: [] };
      cur.hunks.push(hunk);
      newLine = Number(h[1]);
      continue;
    }
    if (!hunk) continue;
    if (raw.startsWith("+")) hunk.added.push({ line: newLine++, text: stripCr(raw.slice(1)) });
    else if (raw.startsWith("-")) hunk.removed.push(stripCr(raw.slice(1)));
  }
  return sections;
}
function parseNameStatus(text) {
  const tokens = text.split("\0");
  const out2 = [];
  let i = 0;
  while (i < tokens.length && tokens[i] !== "") {
    const st = tokens[i++];
    if (st[0] === "R" || st[0] === "C") {
      const oldFile = toPosix(tokens[i++]);
      out2.push({ status: "R", oldFile, file: toPosix(tokens[i++]) });
    } else {
      out2.push({ status: st[0] === "U" ? "M" : st[0], file: toPosix(tokens[i++]) });
    }
  }
  return out2;
}
function pairSections(names, sections) {
  const byHeader = /* @__PURE__ */ new Map();
  for (const s of sections) {
    if (!byHeader.has(s.header)) byHeader.set(s.header, []);
    byHeader.get(s.header).push(s);
  }
  return names.map((n) => {
    const header = n.status === "R" ? `a/${n.oldFile} b/${n.file}` : `a/${n.file} b/${n.file}`;
    const list = byHeader.get(header);
    if (!list || list.length === 0) throw new Error(`could not find the git diff section for "${n.file}" (header ${JSON.stringify(header)})`);
    return n.status === "T" ? list.find((s) => s.newFile) ?? list[list.length - 1] : list[0];
  });
}
function sniffFile(abs) {
  let fd;
  try {
    fd = openSync(abs, "r");
    const b = Buffer.alloc(BINARY_SNIFF);
    const n = readSync(fd, b, 0, BINARY_SNIFF, 0);
    return b.subarray(0, n).includes(0);
  } catch {
    return false;
  } finally {
    if (fd !== void 0) closeSync(fd);
  }
}
function diffTarget(mode, range, cwd) {
  if (mode === "staged") return { args: ["--cached"], base: hasHead(cwd) ? "HEAD" : EMPTY_TREE };
  if (mode === "range") {
    if (!/^[^\s]+\.\.\.[^\s]+$/.test(range ?? "")) throw new Error(`--range needs "<a>...<b>", got "${range ?? ""}"`);
    return { args: [range], base: null };
  }
  const head = hasHead(cwd) ? "HEAD" : EMPTY_TREE;
  return { args: [head], base: head };
}
function readDiff({ cwd, mode = "worktree", range }) {
  const target = diffTarget(mode, range, cwd);
  const patch = String(gitOut(["diff", ...DIFF_FLAGS, ...target.args], { cwd }));
  const names = parseNameStatus(String(gitOut(["diff", "--name-status", "-z", "--no-ext-diff", "--no-textconv", "-M", ...target.args], { cwd })));
  const paired = pairSections(names, parsePatch(patch));
  const entries = names.map((n, i) => {
    const s = paired[i];
    const e = { ...n, hunks: s.hunks };
    if (s.mode === "120000") {
      e.hunks = [];
      e.link = true;
    } else if (s.binary) e.binary = true;
    return e;
  });
  resolveLinks(entries, { cwd, mode, range });
  resolveBinary(entries, { cwd, mode, range, target });
  if (mode === "worktree") {
    const untracked = String(gitOut(["ls-files", "--others", "--exclude-standard", "-z"], { cwd })).split("\0").filter(Boolean);
    for (const raw of untracked) {
      const file = toPosix(raw);
      const abs = join2(cwd, raw);
      let st;
      try {
        st = lstatSync(abs);
      } catch {
        continue;
      }
      if (st.isSymbolicLink()) {
        const entry = { status: "A", file, hunks: [], untracked: true, link: true };
        entries.push(entry);
        resolveLinks([entry], { cwd, mode, range });
        continue;
      }
      if (!st.isFile()) continue;
      if (st.size > MAX_UNTRACKED_BYTES) {
        entries.push({ status: "A", file, hunks: [], untracked: true, skip: "oversize" });
        continue;
      }
      if (sniffFile(abs)) {
        entries.push({ status: "A", file, hunks: [], untracked: true, skip: "binary" });
        continue;
      }
      const lines = readFileSync2(abs, "utf8").split("\n");
      if (lines.length && lines[lines.length - 1] === "") lines.pop();
      entries.push({
        status: "A",
        file,
        untracked: true,
        size: st.size,
        ...st.size > MAX_FILE_BYTES ? { oversize: true } : {},
        hunks: lines.length ? [{ added: lines.map((t, k) => ({ line: k + 1, text: stripCr(t) })), removed: [] }] : []
      });
    }
  }
  markOversize(entries, { cwd, mode, range });
  return entries;
}
function pathMode(cwd, mode, rev, file) {
  const r = mode === "staged" ? runGit(["--literal-pathspecs", "ls-files", "-s", "-z", "--", file], { cwd }) : runGit(["--literal-pathspecs", "ls-tree", "-z", rev, "--", file], { cwd });
  if (r.status !== 0) return null;
  const first = String(r.stdout).split("\0")[0];
  return first ? first.split(/[ \t]/)[0] : null;
}
function isDirectory(cwd, mode, rev, file) {
  try {
    if (statSync(join2(cwd, file)).isDirectory()) return true;
  } catch {
  }
  if (mode === "range") return pathMode(cwd, mode, rev, file) === "040000";
  if (mode === "staged") {
    const r = runGit(["--literal-pathspecs", "ls-files", "--cached", "-z", "--", file], { cwd });
    const first = r.status === 0 ? String(r.stdout).split("\0")[0] : "";
    return first !== "" && first !== file;
  }
  return false;
}
function isIgnored(cwd, path2) {
  return runGit(["check-ignore", "-q", "--", path2], { cwd }).status === 0;
}
function resolveLinks(entries, { cwd, mode, range }) {
  const rev = mode === "range" ? range.split("...")[1] : "";
  const lexical = (from, t) => isAbsolute(t) || /^[A-Za-z]:[\\/]/.test(t) ? null : posix2.normalize(posix2.join(posix2.dirname(from), t.replace(/\\/g, "/")));
  const escapes = (p) => p === ".." || p.startsWith("../");
  for (const e of entries.filter((x) => x.link)) {
    delete e.link;
    if (e.status === "D") {
      e.hunks = [];
      continue;
    }
    let target = null;
    let content = null;
    let reason = null;
    if (mode === "worktree") {
      try {
        const real = realpathSync(join2(cwd, e.file));
        const rel = relative(realpathSync(cwd), real);
        if (rel.startsWith("..") || isAbsolute(rel)) reason = "symlink-outside";
        else {
          target = rel.split(sep).join("/");
          if (statSync(real).isDirectory()) reason = "symlink-dir";
          else content = readFileSync2(real);
        }
      } catch (err2) {
        if (err2 && err2.code === "ELOOP") reason = "symlink-chain";
        else {
          try {
            const t = readlinkSync(join2(cwd, e.file));
            const next = lexical(e.file, t);
            if (next === null) reason = "symlink-absolute";
            else if (escapes(next)) reason = "symlink-outside";
          } catch {
          }
        }
      }
    } else {
      let cur = e.file;
      reason = "symlink-chain";
      for (let hop = 0; hop <= MAX_LINK_HOPS; hop++) {
        const spec = `${rev}:${cur}`;
        const blob = catBatch(cwd, [spec]).get(spec);
        if (!blob) {
          if (isDirectory(cwd, mode, rev, cur)) {
            target = cur;
            reason = "symlink-dir";
          } else reason = null;
          break;
        }
        if (pathMode(cwd, mode, rev, cur) !== "120000") {
          target = cur;
          content = blob;
          reason = null;
          break;
        }
        const next = lexical(cur, blob.toString("utf8").trim());
        if (next === null) {
          reason = "symlink-absolute";
          break;
        }
        if (escapes(next)) {
          reason = "symlink-outside";
          break;
        }
        cur = next;
      }
    }
    if (reason === "symlink-dir") {
      e.hunks = [];
      e.skip = "symlink-dir";
      e.linkDir = target;
      e.linkIgnored = isIgnored(cwd, `${target}/`);
      continue;
    }
    if (reason) {
      e.hunks = [];
      e.skip = reason;
      continue;
    }
    if (content === null) {
      e.hunks = [];
      e.skip = "symlink";
      continue;
    }
    if (hasNul(content)) {
      e.hunks = [];
      e.skip = "binary";
      continue;
    }
    const lines = content.toString("utf8").split("\n");
    if (lines.length && lines[lines.length - 1] === "") lines.pop();
    e.linkTarget = target;
    e.size = content.length;
    if (content.length > MAX_FILE_BYTES) e.oversize = true;
    e.hunks = lines.length ? [{ added: lines.map((t, k) => ({ line: k + 1, text: stripCr(t) })), removed: [] }] : [];
  }
}
function resolveBinary(entries, { cwd, mode, range, target }) {
  const flagged = entries.filter((e) => e.binary);
  if (flagged.length === 0) return;
  const rev = mode === "range" ? range.split("...")[1] : "";
  const specs = flagged.filter((e) => e.status !== "D" && mode !== "worktree").map((e) => `${rev}:${e.file}`);
  const blobs = catBatch(cwd, specs);
  const hidden = [];
  for (const e of flagged) {
    delete e.binary;
    if (e.status === "D") {
      e.skip = "binary";
      continue;
    }
    let isBinary;
    if (mode === "worktree") isBinary = sniffFile(join2(cwd, e.file));
    else {
      const b = blobs.get(`${rev}:${e.file}`);
      isBinary = !b || hasNul(b);
    }
    if (isBinary) e.skip = "binary";
    else hidden.push(e);
  }
  if (hidden.length === 0) return;
  const paths = [...new Set(hidden.flatMap((e) => e.oldFile ? [e.oldFile, e.file] : [e.file]))];
  const r = runGit(["--literal-pathspecs", "diff", ...DIFF_FLAGS, "--text", ...target.args, "--", ...paths], { cwd });
  if (r.status !== 0) throw new Error(`git diff --text failed: ${String(r.stderr).trim()}`);
  const sections = parsePatch(String(r.stdout));
  for (const e of hidden) {
    const header = e.status === "R" ? `a/${e.oldFile} b/${e.file}` : `a/${e.file} b/${e.file}`;
    const s = sections.find((x) => x.header === header);
    if (!s) throw new Error(`could not re-read "${e.file}" as text`);
    e.hunks = s.hunks;
  }
}
function markOversize(entries, { cwd, mode, range }) {
  const live = entries.filter((e) => e.status !== "D" && !e.skip && !e.untracked && !e.linkTarget);
  if (live.length === 0) return;
  if (mode === "worktree") {
    for (const e of live) {
      try {
        e.size = statSync(join2(cwd, e.file)).size;
        if (e.size > MAX_FILE_BYTES) e.oversize = true;
      } catch {
      }
    }
    return;
  }
  const rev = mode === "staged" ? "" : range.split("...")[1];
  const sizes = sizeBatch(cwd, live.map((e) => `${rev}:${e.file}`));
  for (const e of live) {
    const size = sizes.get(`${rev}:${e.file}`);
    if (size !== null && size !== void 0) {
      e.size = size;
      if (size > MAX_FILE_BYTES) e.oversize = true;
    }
  }
}
function makeReaders({ cwd, mode = "worktree", range, links = /* @__PURE__ */ new Map() }) {
  const cache = /* @__PURE__ */ new Map();
  const headOk = mode === "range" ? true : hasHead(cwd);
  let baseRev = "HEAD";
  let postRev = "";
  if (mode === "range") {
    const [a, b] = range.split("...");
    postRev = b;
    baseRev = String(gitOut(["merge-base", a, b], { cwd })).trim();
  }
  const decode = (buf) => buf ? buf.toString("utf8") : null;
  const fromGit = (spec) => {
    if (!cache.has(spec)) cache.set(spec, decode(catBatch(cwd, [spec]).get(spec)));
    return cache.get(spec);
  };
  const readFile = (rel0) => {
    const rel = links.get(rel0) ?? rel0;
    if (mode === "worktree") {
      try {
        return readFileSync2(join2(cwd, rel), "utf8");
      } catch {
        return null;
      }
    }
    return fromGit(`${postRev}:${rel}`);
  };
  return {
    /** Batch every file the run will read: one git process per side instead of one per file. */
    prefetch(list) {
      if (mode !== "worktree") {
        const specs = list.map((e) => `${postRev}:${links.get(e.file) ?? e.file}`).filter((s) => !cache.has(s));
        const got = catBatch(cwd, specs);
        for (const s of specs) cache.set(s, decode(got.get(s)));
      }
      if (headOk) {
        const specs = list.filter((e) => e.status !== "A").map((e) => `${baseRev}:${e.oldFile ?? e.file}`).filter((s) => !cache.has(s));
        const got = catBatch(cwd, specs);
        for (const s of specs) cache.set(s, decode(got.get(s)));
      }
    },
    readPost: readFile,
    readBase(entry) {
      if (!headOk || entry.status === "A") return null;
      return fromGit(`${baseRev}:${entry.oldFile ?? entry.file}`);
    },
    /** Any repo-relative path, from the SAME side of the diff as the source files. */
    readFile,
    /** Immediate child names of a repo-relative directory, from the same side. */
    listDir(dir) {
      if (mode === "worktree") {
        try {
          return readdirSync2(join2(cwd, dir));
        } catch {
          return [];
        }
      }
      if (mode === "staged") {
        const r2 = runGit(["ls-files", "--cached", "-z", "--", dir ? `${dir}/` : "."], { cwd });
        if (r2.status !== 0) return [];
        const prefix = dir ? `${dir}/` : "";
        return [...new Set(String(r2.stdout).split("\0").filter(Boolean).map((p) => p.slice(prefix.length).split("/")[0]))];
      }
      const r = runGit(["ls-tree", "--name-only", dir ? `${postRev}:${dir}` : postRev], { cwd });
      return r.status === 0 ? String(r.stdout).split("\n").filter(Boolean) : [];
    }
  };
}
function countAdded(entries) {
  let n = 0;
  for (const e of entries) for (const h of e.hunks) n += h.added.length;
  return n;
}

// lib/check/evaluate.mjs
import { readFileSync as readFileSync3, readdirSync as readdirSync3 } from "node:fs";
import { join as join3 } from "node:path";
var TEXT_CAP = 200;
var LINK_MESSAGES = {
  "symlink-outside": (e) => `symlink target outside repository: not judged (${e.file}); code reached through it is not checked here. Point it inside the repository or keep it out of source.`,
  "symlink-absolute": (e) => `absolute symlink target: not judged (${e.file}); make it relative. An absolute path cannot be shown to be inside the repository from the index, and it is not portable.`,
  "symlink-chain": (e) => `symlink chain longer than 8 hops, or a cycle: not judged (${e.file}). Point the link at its final target.`,
  "symlink-skipped-dir": (e) => `directory symlink into a skipped path: not judged (${e.file} -> ${e.linkDir}); code under it is reachable as source but no rule looks at it. Move the code, or link into judged source.`
};
var extOf = (rel) => {
  const b = rel.slice(rel.lastIndexOf("/") + 1);
  const i = b.lastIndexOf(".");
  return i > 0 ? b.slice(i + 1) : "";
};
var norm = (s) => typeof s === "string" ? s.replace(/\r\n/g, "\n") : s;
function isTestFilePath(rel) {
  const base = rel.slice(rel.lastIndexOf("/") + 1);
  return /\.(test|spec)\.[^.]+$/.test(base) || /_test\.(go|py)$/.test(base) || /\/(tests|test|__tests__)\//.test("/" + rel);
}
var compile = (pattern, flags = "") => new RegExp(pattern, "m" + String(flags).replace(/[gyms]/g, ""));
function surplusPush(out2, hits, removedCount, netNew, make) {
  const n = netNew ? Math.max(0, hits.length - removedCount) : hits.length;
  for (const h of hits.slice(0, n)) out2.push(make(h));
}
function evaluate(entries, rules, deps = {}) {
  validateRuleSet(rules, "rules");
  const { readPost = () => null, readBase = () => null, prefetch, projectDir = "", netNew = true, moved = true, skipBuiltins = [], strict = false } = deps;
  const tooBig = (e) => (e.size ?? (e.oversize ? MAX_FILE_BYTES + 1 : 0)) > (strict ? STRICT_FILE_BYTES : MAX_FILE_BYTES);
  const readFile = deps.readFile ?? ((rel) => {
    try {
      return readFileSync3(join3(projectDir, rel), "utf8");
    } catch {
      return null;
    }
  });
  const listDir = deps.listDir ?? ((dir) => {
    try {
      return readdirSync3(join3(projectDir, dir));
    } catch {
      return [];
    }
  });
  const skipIds = new Set(skipBuiltins);
  const disabled = new Set(rules.overrides?.disabled ?? []);
  const langs = new Set(rules.languages ?? ["typescript"]);
  const skipRes = (rules.skip ?? []).map(skipRegex);
  const groups = rules.groups.filter((g) => !disabled.has(g.name)).map((g) => ({ ...g, appliesRes: g.appliesTo.map(appliesRegex) }));
  const MAX_DIR_ENTRIES = 5e3;
  const dirHoldsJudged = (e) => {
    const list = e.linkIgnored ? (d) => {
      try {
        return readdirSync3(join3(projectDir, d));
      } catch {
        return [];
      }
    } : listDir;
    const queue = [[e.linkDir ?? "", e.file]];
    let seen = 0;
    while (queue.length) {
      const [real, via] = queue.shift();
      for (const name of list(real)) {
        if (++seen > MAX_DIR_ENTRIES) return true;
        const realPath = real ? `${real}/${name}` : name;
        const viaPath = `${via}/${name}`;
        if (SOURCE_EXTS.has(extOf(name)) && groups.some((g) => g.appliesRes.some((re) => re.test(viaPath)))) return true;
        if (name !== ".git") queue.push([realPath, viaPath]);
      }
    }
    return false;
  };
  const findings = [];
  const skipped = [];
  const judged = [];
  for (const e of entries) {
    if (e.skip) {
      let reason = e.skip;
      const link = LINK_MESSAGES[reason];
      if (reason === "symlink-dir") {
        const t = e.linkDir ?? "";
        const underSkipped = e.linkIgnored || HARD_SKIP_DIRS.some((x) => ("/" + t + "/").includes(x)) || skipRes.some((re) => re.test(t) || re.test(t + "/x"));
        if (underSkipped) {
          if (skipRes.some((re) => re.test(e.file) || re.test(e.file + "/x"))) reason = "skip-glob";
          else if (dirHoldsJudged(e)) reason = "symlink-skipped-dir";
        }
      }
      skipped.push({ file: e.file, reason });
      const msg = LINK_MESSAGES[reason] ?? link;
      if (strict && msg) findings.push({ rule: reason, group: "checker", severity: "error", file: e.file, line: 1, text: "", kind: "checker", message: msg(e) });
      continue;
    }
    const rel = e.file;
    const base = rel.slice(rel.lastIndexOf("/") + 1);
    if (HARD_SKIP_DIRS.some((d) => ("/" + rel).includes(d)) || /\.(generated|gen|d)\.[^.]+$/.test(base)) continue;
    if (skipRes.some((re) => re.test(rel))) {
      if (SOURCE_EXTS.has(extOf(rel)) && e.status !== "D") skipped.push({ file: rel, reason: "skip-glob" });
      continue;
    }
    judged.push(e);
  }
  const work = /* @__PURE__ */ new Map();
  const pool = /* @__PURE__ */ new Map();
  const kind = (rel) => `${LANG_MAP[extOf(rel)] || ""}|${isTestFilePath(rel) ? 1 : 0}|`;
  for (const e of judged) {
    work.set(e, e.hunks.map((h) => ({ added: h.added, removed: h.removed.map((text) => ({ text, used: false })) })));
    if (!moved) continue;
    for (const h of work.get(e)) for (const r of h.removed) {
      const t = r.text.trim();
      if (!t) continue;
      const k = kind(e.file) + t;
      if (!pool.has(k)) pool.set(k, []);
      pool.get(k).push(r);
    }
  }
  let addedTotal = 0;
  const todo = [];
  for (const e of judged) {
    if (e.status === "D") continue;
    const hunks = work.get(e).map((h) => {
      const added = [];
      for (const a of h.added) {
        addedTotal++;
        const t = a.text.trim();
        const twin = moved && t ? pool.get(kind(e.file) + t)?.find((r) => !r.used) : void 0;
        if (twin) {
          twin.used = true;
          continue;
        }
        added.push(a);
      }
      return { added, removed: h.removed };
    });
    if (hunks.some((h) => h.added.length)) todo.push({ e, hunks });
  }
  prefetch?.(todo.map((t) => t.e));
  const shared = {};
  for (const { e, hunks: wh } of todo) {
    const rel = e.file;
    const base = rel.slice(rel.lastIndexOf("/") + 1);
    const ext = extOf(rel);
    const lang = LANG_MAP[ext] || "";
    const langOk = SOURCE_EXTS.has(ext) && !!lang && (lang === "sql" || langs.has(lang));
    const hunks = wh.map((h) => ({ added: h.added, removed: h.removed.filter((r) => !r.used).map((r) => r.text) }));
    let postMemo;
    let postDone = false;
    let baseMemo;
    let baseDone = false;
    let linesMemo;
    const post = () => postDone ? postMemo : (postDone = true, postMemo = norm(readPost(rel)));
    const baseText = () => baseDone ? baseMemo : (baseDone = true, baseMemo = norm(readBase(e)));
    const postLines = () => linesMemo ??= (post() ?? "").split("\n");
    const ctx = { rel, base, ext, lang, isTestFile: isTestFilePath(rel), post, baseText, postLines, projectDir, shared, readFile, listDir };
    let fileRulesSkipped = false;
    for (const group of groups) {
      if (!group.appliesRes.some((re) => re.test(rel))) continue;
      for (const rule of group.rules) {
        if (disabled.has(rule.name)) continue;
        const sev = rule.severity === "warn" ? "warn" : "error";
        if (rule.kind === "builtin") {
          if (skipIds.has(rule.id)) continue;
          const def = BUILTINS[rule.id];
          const gate = def.exts ? def.exts.has(ext) : langOk && (!def.lang || def.lang === lang);
          if (!gate) continue;
          if (def.scope === "line") {
            const st = def.prepare(ctx);
            for (const h of hunks) {
              if (!h.added.length) continue;
              const addHits = /* @__PURE__ */ new Map();
              h.added.forEach((a) => {
                const prev = a.line > 1 ? postLines()[a.line - 2] ?? "" : "";
                for (const r of def.lines(a.text, prev, st, ctx) ?? []) {
                  if (disabled.has(r.name)) continue;
                  if (!addHits.has(r.name)) addHits.set(r.name, []);
                  addHits.get(r.name).push({ a, r });
                }
              });
              const remCount = /* @__PURE__ */ new Map();
              h.removed.forEach((t, i) => {
                for (const r of def.lines(t, i > 0 ? h.removed[i - 1] : "", st, ctx) ?? []) remCount.set(r.name, (remCount.get(r.name) ?? 0) + 1);
              });
              for (const [name, hits] of addHits) {
                surplusPush(findings, hits, remCount.get(name) ?? 0, netNew, ({ a, r }) => ({
                  rule: name,
                  group: group.name,
                  severity: sev,
                  file: rel,
                  line: a.line,
                  text: a.text.trim().slice(0, TEXT_CAP),
                  message: rule.message ?? r.message,
                  kind: "builtin"
                }));
              }
            }
          } else {
            if (tooBig(e)) {
              fileRulesSkipped = true;
              continue;
            }
            const p = post();
            if (p === null || p === void 0) continue;
            const mine = def.file(p, baseText(), ctx).filter((f) => !disabled.has(f.name));
            const prior = /* @__PURE__ */ new Map();
            if (netNew) {
              const b = baseText();
              if (b !== null && b !== void 0) for (const f of def.file(b, null, ctx)) prior.set(`${f.name}|${f.key}`, (prior.get(`${f.name}|${f.key}`) ?? 0) + 1);
            }
            for (const f of mine) {
              const k = `${f.name}|${f.key}`;
              if ((prior.get(k) ?? 0) > 0) {
                prior.set(k, prior.get(k) - 1);
                continue;
              }
              findings.push({ rule: f.name, group: group.name, severity: sev, file: rel, line: f.line, text: String(f.text).trim().slice(0, TEXT_CAP), message: rule.message ?? f.message, kind: "builtin" });
            }
          }
          continue;
        }
        if (!langOk) continue;
        if (rule.scope === "file" && tooBig(e)) {
          fileRulesSkipped = true;
          continue;
        }
        if (rule.skipIfPath && compile(rule.skipIfPath).test(rel)) continue;
        const re = compile(rule.pattern, rule.flags);
        if (rule.skipIf) {
          const p = post();
          if (p && compile(rule.skipIf).test(p)) continue;
        }
        const message = `[${group.name}] ${rule.message}`;
        if (rule.scope === "file") {
          const p = post();
          if (p === null || p === void 0) continue;
          const matched = (text) => rule.invertMatch ? !re.test(text) : re.test(text);
          if (!matched(p)) continue;
          if (netNew) {
            const b = baseText();
            if (b !== null && b !== void 0 && matched(b)) continue;
          }
          const m = rule.invertMatch ? null : re.exec(p);
          const line = m ? p.slice(0, m.index).split("\n").length : 1;
          findings.push({ rule: rule.name, group: group.name, severity: sev, file: rel, line, text: String(p.split("\n")[line - 1] ?? "").trim().slice(0, TEXT_CAP), message, kind: "regex" });
        } else {
          for (const h of hunks) {
            const hits = h.added.filter((a) => re.test(a.text));
            if (!hits.length) continue;
            const removedCount = h.removed.filter((t) => re.test(t)).length;
            surplusPush(findings, hits, removedCount, netNew, (a) => ({
              rule: rule.name,
              group: group.name,
              severity: sev,
              file: rel,
              line: a.line,
              text: a.text.trim().slice(0, TEXT_CAP),
              message,
              kind: "regex"
            }));
          }
        }
      }
    }
    if (fileRulesSkipped) {
      skipped.push({ file: rel, reason: "oversize" });
      if (strict) {
        findings.push({
          rule: "file-scope-skipped",
          group: "checker",
          severity: "error",
          file: rel,
          line: 1,
          text: "",
          kind: "checker",
          message: `file-scope rules were not run on ${rel} (${Math.round((e.size ?? 0) / 1048576)} MB, over the ${STRICT_FILE_BYTES / 1048576} MB ceiling), so it cannot be fully judged. Split the file, or add its path to overrides.skip in .composure/rules.json (through the apply script: ! node scripts/composure/apply-rules.mjs).`
        });
      }
    }
  }
  findings.sort((a, b) => a.file < b.file ? -1 : a.file > b.file ? 1 : a.line - b.line);
  return {
    ok: !findings.some((f) => f.severity === "error"),
    mode: deps.mode ?? "diff",
    rulesFrom: deps.rulesFrom ?? "worktree",
    findings,
    skipped,
    stats: { files: todo.length, added: addedTotal }
  };
}

// lib/check/run.mjs
import { existsSync as existsSync2, readFileSync as readFileSync4 } from "node:fs";
import { join as join4 } from "node:path";
var STOP_MAX_ADDED = 2e5;
var CheckError = class extends Error {
};
function mustResolve(cwd, ref, what) {
  if (!ref || !revParse(cwd, ref)) throw new CheckError(`${what} "${ref ?? ""}" does not resolve to a commit in this repository (a ref that is missing here is an error, never a reason to use other rules)`);
}
function runCheck(opts) {
  const root = gitRoot(opts.cwd);
  if (!root) throw new CheckError(`${opts.cwd} is not inside a git repository`);
  const mode = opts.mode ?? "worktree";
  let a;
  let b;
  if (mode === "range") {
    const parts = String(opts.range ?? "").split("...");
    if (parts.length !== 2 || !parts[0] || !parts[1]) throw new CheckError(`--range needs "<a>...<b>", got "${opts.range ?? ""}"`);
    [a, b] = parts;
    mustResolve(root, a, "--range base");
    mustResolve(root, b, "--range head");
  }
  if (opts.rulesRef !== void 0) mustResolve(root, opts.rulesRef, "--rules-ref");
  const refs = mode === "range" ? [opts.rulesRef ?? a, b] : [opts.rulesRef ?? "HEAD"];
  const fallback = mode === "range" ? "none" : mode === "staged" ? "index" : "worktree";
  let loaded = loadRules({ cwd: root, refs, fromLabel: mode === "range" ? "base" : "head", fallback });
  if (!loaded && (mode !== "range" || opts.unmigrated === true) && opts.defaultsDir && existsSync2(opts.defaultsDir)) {
    const stackSpec = mode === "range" ? `${opts.rulesRef ?? a}:.composure/no-bandaids.json` : mode === "staged" ? ":.composure/no-bandaids.json" : "HEAD:.composure/no-bandaids.json";
    const readStack = () => {
      const buf = catBatch(root, [stackSpec]).get(stackSpec);
      if (buf) {
        try {
          return JSON.parse(buf.toString("utf8"));
        } catch {
          return null;
        }
      }
      if (mode !== "worktree") return null;
      try {
        return JSON.parse(readFileSync4(join4(root, ".composure", "no-bandaids.json"), "utf8"));
      } catch {
        return null;
      }
    };
    loaded = { rules: resolveUnmigrated({ projectDir: root, defaultsDir: opts.defaultsDir, readStack }), rulesFrom: "resolved", notice: UNMIGRATED_NOTICE };
  }
  if (!loaded) return { ok: true, none: true, mode, rulesFrom: "worktree", findings: [], skipped: [], notice: "no .composure/rules.json in this project; nothing to check" };
  const entries = readDiff({ cwd: root, mode, range: opts.range });
  const added = countAdded(entries);
  if (opts.maxAdded && added > opts.maxAdded) {
    return {
      ok: true,
      mode,
      rulesFrom: loaded.rulesFrom,
      findings: [],
      skipped: [],
      notice: `${added} added lines is too large for a turn-time check; the commit gate will check`,
      tooLarge: true
    };
  }
  const links = new Map(entries.filter((e) => e.linkTarget).map((e) => [e.file, e.linkTarget]));
  const readers = makeReaders({ cwd: root, mode, range: opts.range, links });
  const result = evaluate(entries, loaded.rules, { ...readers, projectDir: root, mode, rulesFrom: loaded.rulesFrom, netNew: opts.netNew, moved: opts.moved, strict: mode === "staged" || mode === "range" });
  if (loaded.notice) result.notice = loaded.notice;
  return result;
}

// lib/check/hosts.mjs
var HOSTS = {
  claude: {
    id: "claude",
    stop: { configPath: ".claude/settings.json", event: "Stop", shape: "claude-decision" },
    perEdit: "plugin",
    skills: { root: "~/.claude/skills", alias: "~/.claude/skills/composure" },
    mcp: { writer: "plugin" },
    rules: { file: ".composure/rules.json" },
    trust: "The committed Stop adapter runs only in a workspace whose trust prompt was accepted interactively. Untrusted -p, the SDK and CI agents do not load hooks from shared settings; settings.local.json and --settings do.",
    verified: "P-A1 negative case probed 2026-11-18 on Claude Code 2.1.327; trusted interactive pending"
  },
  codex: {
    id: "codex",
    stop: { configPath: ".codex/hooks.json", event: "Stop", shape: "exit2-stderr" },
    perEdit: "plugin",
    skills: { root: "~/.agents/skills", alias: "~/.agents/skills/composure" },
    mcp: { writer: "plugin" },
    rules: { file: ".composure/rules.json" },
    trust: "Codex trusts a hook by its hash and skips a changed one until re-trusted: keep the adapter command string stable.",
    verified: "P-D0 pending"
  }
};
function hostRow(id) {
  return HOSTS[id] ?? null;
}

// lib/check/hook-output.mjs
var where = (f) => `${f.file}:${f.line}`;
var errors = (r) => r.findings.filter((f) => f.severity === "error");
var warns = (r) => r.findings.filter((f) => f.severity === "warn");
function formatText(result) {
  const lines = [];
  const errs = errors(result);
  const ws = warns(result);
  for (const f of [...errs, ...ws]) lines.push(`${f.severity === "error" ? "ERROR" : "warn "} ${where(f)}  ${f.rule}  ${f.message}${f.text ? `
        > ${f.text}` : ""}`);
  for (const s of result.skipped ?? []) lines.push(`skipped ${s.file} (${s.reason})`);
  if (result.notice) lines.push(`note: ${result.notice}`);
  lines.push(errs.length ? `composure-check: ${errs.length} violation${errs.length === 1 ? "" : "s"} in ${result.mode} (rules from ${result.rulesFrom})` : `composure-check: clean (${result.mode}, rules from ${result.rulesFrom})`);
  return lines.join("\n") + "\n";
}
var UNJUDGED = /* @__PURE__ */ new Set(["symlink-outside", "symlink-absolute", "symlink-chain", "symlink-skipped-dir"]);
function unjudgedNotice(result) {
  const list = (result.skipped ?? []).filter((s) => UNJUDGED.has(s.reason));
  if (!list.length) return "";
  return `Not judged (the commit gate will fail on these): ${list.slice(0, 8).map((s) => `${s.file} (${s.reason})`).join(", ")}${list.length > 8 ? `, and ${list.length - 8} more` : ""}.`;
}
function warnMessage(findings) {
  return findings.map((f) => `${where(f)} ${f.rule}: ${f.message}`).join("\n");
}
function blockReminder(result, ctx) {
  const errs = errors(result);
  const out2 = [];
  out2.push("<system-reminder>");
  out2.push(`[composure:enforcement] The write you just attempted to ${ctx.base} matches a pattern this codebase doesn't want shipped.`);
  out2.push(`
What the rule caught (${errs.length} item${errs.length === 1 ? "" : "s"}):`);
  for (const f of errs) out2.push(`  - ${f.message}${f.line ? ` (line ${f.line})` : ""}`);
  if (ctx.lang === "typescript") {
    out2.push("\nFor TypeScript, the in-codebase ways through this:");
    out2.push("  - `satisfies` operator for type validation without widening");
    out2.push("  - type guards (`is` / `in` / `instanceof`) to narrow unknown or union types");
    out2.push("  - generic type params on hooks/helpers (`useLocalSearchParams<T>`, `ChangeEvent<T>`, `Ref<T>`)");
    out2.push("  - regenerate types if the schema changed");
    if (ctx.typegenHint) out2.push(`    regen command: ${ctx.typegenHint}`);
  }
  const ws = warns(result);
  if (ws.length) {
    out2.push("\nAlso flagged (non-blocking) \u2014 worth addressing in the same edit:");
    for (const w of ws) out2.push(`  - ${w.message}`);
  }
  out2.push(result.notice ? `
Rules: ${result.notice}.` : `
Rules: the project's committed .composure/rules.json (read from ${result.rulesFrom === "head" ? "HEAD" : result.rulesFrom}).`);
  if (ctx.count >= 3) {
    out2.push(`
This is enforcement-rule #${ctx.count} hit in this session. The pattern reference docs likely have the precise shape you're reaching for \u2014 \`/composure:app-architecture\` loads them tier-aware. Worth a read before the next edit.`);
  }
  out2.push("\nLegitimate exits (don't try to work around the rule \u2014 surface the situation instead):");
  out2.push("  - if the rule misreads what you're doing and your edit is correct, say so and I'll consider a one-off override");
  out2.push("  - if you're not sure which pattern applies, run `/composure:app-architecture` to load the relevant catalog");
  out2.push("  - if the pattern catalog itself disagrees with the rule, surface that \u2014 the rule is what needs updating");
  out2.push("</system-reminder>");
  return out2.join("\n") + "\n";
}
function summary(findings, limit = 12) {
  const errs = findings.filter((f) => f.severity === "error");
  const body = errs.slice(0, limit).map((f) => `- ${where(f)} ${f.rule}: ${f.message}`).join("\n");
  const more = errs.length > limit ? `
... and ${errs.length - limit} more` : "";
  return `${errs.length} rule violation${errs.length === 1 ? "" : "s"} in the lines you added this turn:
${body}${more}

Fix them, or say why a rule misreads the change. The commit gate will block these too.`;
}
function stopOutput(host, decision) {
  const row = hostRow(host);
  if (!row) throw new Error(`unknown host "${host}"`);
  const shape = row.stop.shape;
  if (decision.action === "block") {
    const reason = decision.reason ?? summary(decision.findings ?? []);
    if (shape === "claude-decision") return { stdout: JSON.stringify({ decision: "block", reason }) + "\n", stderr: "", exit: 0 };
    if (shape === "exit2-stderr") return { stdout: "", stderr: reason + "\n", exit: 2 };
    throw new Error(`host "${host}" has no Stop output shape yet`);
  }
  const msg = decision.systemMessage;
  return { stdout: msg ? JSON.stringify({ systemMessage: msg }) + "\n" : shape === "claude-decision" ? "{}\n" : "", stderr: "", exit: 0 };
}

// lib/check/proposed-hook.mjs
import { join as join6 } from "node:path";

// lib/check/proposed.mjs
import { existsSync as existsSync3, readFileSync as readFileSync5, realpathSync as realpathSync2 } from "node:fs";
import path from "node:path";
var { isAbsolute: isAbsolute2, resolve } = path;
var stripCr2 = (s) => s.endsWith("\r") ? s.slice(0, -1) : s;
function readDisk(abs) {
  try {
    return readFileSync5(abs, "utf8");
  } catch {
    return null;
  }
}
function replaceOnce(text, oldS, newS, all) {
  if (!oldS) return null;
  if (all) return text.includes(oldS) ? text.split(oldS).join(newS) : null;
  const i = text.indexOf(oldS);
  return i < 0 ? null : text.slice(0, i) + newS + text.slice(i + oldS.length);
}
function parseApplyPatch(text) {
  const ops = [];
  let op = null;
  let chunk = null;
  for (const raw of String(text).split("\n")) {
    const line = stripCr2(raw);
    let m;
    if (m = /^\*\*\* (Add|Update|Delete) File:\s*(.+)$/.exec(line)) {
      op = { op: m[1].toLowerCase(), path: m[2].trim(), chunks: [] };
      ops.push(op);
      chunk = null;
      continue;
    }
    if (!op) continue;
    if (/^\*\*\* (Begin|End) Patch/.test(line) || /^\*\*\* Move to:/.test(line)) continue;
    if (line.startsWith("@@")) {
      chunk = { lines: [] };
      op.chunks.push(chunk);
      continue;
    }
    if (op.op === "delete") continue;
    if (!chunk) {
      chunk = { lines: [] };
      op.chunks.push(chunk);
    }
    const t = line[0];
    if (t === "+" || t === "-" || t === " ") chunk.lines.push({ t, s: line.slice(1) });
  }
  return ops;
}
function applyChunks(before, chunks) {
  const lines = before.split("\n");
  let cursor = 0;
  for (const c of chunks) {
    const oldSeq = c.lines.filter((l) => l.t !== "+").map((l) => l.s);
    const newSeq = c.lines.filter((l) => l.t !== "-").map((l) => l.s);
    const find = (cmp) => {
      for (let i = cursor; i + oldSeq.length <= lines.length; i++) {
        if (oldSeq.every((s, k) => cmp(lines[i + k], s))) return i;
      }
      return -1;
    };
    let at = oldSeq.length ? find((a, b) => a === b) : lines.length;
    if (at < 0) at = find((a, b) => a.trimEnd() === b.trimEnd());
    if (at < 0) return null;
    lines.splice(at, oldSeq.length, ...newSeq);
    cursor = at + newSeq.length;
  }
  return lines.join("\n");
}
function fromPayload(payload = {}, cwd = process.cwd()) {
  const tool = String(payload.tool_name || payload.toolName || payload.tool || payload.name || payload.event?.tool || "").toLowerCase();
  const input = payload.tool_input || payload.toolInput || payload.params || payload.arguments || payload.input || {};
  const base = String(payload.cwd || payload.workspace?.current_dir || input.cwd || cwd);
  const abs = (p) => isAbsolute2(p) ? p : resolve(base, p);
  const patchText = [input.command, input.patch, input.input].find((v) => typeof v === "string" && /^[ \t]*\*\*\* begin patch/im.test(v));
  if (patchText) {
    const out2 = [];
    for (const op of parseApplyPatch(patchText)) {
      if (op.op === "delete") continue;
      const file2 = abs(op.path);
      const before = op.op === "add" ? "" : readDisk(file2) ?? "";
      const after = op.op === "add" ? op.chunks.flatMap((c) => c.lines.filter((l) => l.t === "+").map((l) => l.s)).join("\n") : applyChunks(before, op.chunks) ?? before + "\n" + op.chunks.flatMap((c) => c.lines.filter((l) => l.t === "+").map((l) => l.s)).join("\n");
      out2.push({ file: file2, before, after });
    }
    return out2;
  }
  const path2 = input.file_path || input.TargetFile || input.path || input.AbsolutePath || input.filePath || input.target_file || payload.file_path || payload.path || "";
  if (!path2) return [];
  const file = abs(String(path2));
  const disk = readDisk(file);
  if (/^(write|create_file|write_file|write_to_file)$/.test(tool)) {
    const content = input.content ?? input.contents ?? input.CodeContent ?? input.ReplacementContent ?? input.text ?? input.new_string;
    return typeof content === "string" ? [{ file, before: disk ?? "", after: content }] : [];
  }
  const oldS = input.old_string ?? input.oldString ?? input.TargetContent;
  const newS = input.new_string ?? input.newString ?? input.ReplacementContent;
  if (tool === "multiedit" || Array.isArray(input.edits)) {
    const edits = Array.isArray(input.edits) ? input.edits : [];
    let text = disk ?? "";
    for (const e of edits) {
      const o = e.old_string ?? e.oldString;
      const n = e.new_string ?? e.newString ?? "";
      const next = replaceOnce(text, o, n, e.replace_all === true);
      if (next === null) {
        text = text + (text && !text.endsWith("\n") ? "\n" : "") + n;
      } else text = next;
    }
    return [{ file, before: disk ?? "", after: text }];
  }
  if (/^(edit|edit_file|search_replace|replace_file_content|patch)$/.test(tool) && typeof newS === "string") {
    if (disk !== null && typeof oldS === "string") {
      const next = replaceOnce(disk, oldS, newS, input.replace_all === true);
      if (next !== null) return [{ file, before: disk, after: next }];
    }
    return [{ file, before: typeof oldS === "string" ? oldS : "", after: newS }];
  }
  return [];
}
var MAX_EDIT_DISTANCE = 1500;
function diffLines(a, b) {
  let s = 0;
  while (s < a.length && s < b.length && a[s] === b[s]) s++;
  let ea = a.length;
  let eb = b.length;
  while (ea > s && eb > s && a[ea - 1] === b[eb - 1]) {
    ea--;
    eb--;
  }
  const A = a.slice(s, ea);
  const B = b.slice(s, eb);
  const wholeMiddle = () => A.length || B.length ? [{ removed: A, added: B.map((text, j2) => ({ line: s + j2 + 1, text })) }] : [];
  const n = A.length;
  const m = B.length;
  if (n === 0 || m === 0) return wholeMiddle();
  const max = Math.min(n + m, MAX_EDIT_DISTANCE);
  const off = max + 1;
  const trace = [];
  let v = new Int32Array(2 * max + 3);
  let found = -1;
  for (let d = 0; d <= max && found < 0; d++) {
    trace.push(v.slice());
    for (let k = -d; k <= d; k += 2) {
      let x2 = k === -d || k !== d && v[off + k - 1] < v[off + k + 1] ? v[off + k + 1] : v[off + k - 1] + 1;
      let y2 = x2 - k;
      while (x2 < n && y2 < m && A[x2] === B[y2]) {
        x2++;
        y2++;
      }
      v[off + k] = x2;
      if (x2 >= n && y2 >= m) {
        found = d;
        break;
      }
    }
  }
  if (found < 0) return wholeMiddle();
  const del = /* @__PURE__ */ new Set();
  const ins = /* @__PURE__ */ new Set();
  let x = n;
  let y = m;
  for (let d = found; d > 0; d--) {
    const vv = trace[d];
    const k = x - y;
    const prevK = k === -d || k !== d && vv[off + k - 1] < vv[off + k + 1] ? k + 1 : k - 1;
    const prevX = vv[off + prevK];
    const prevY = prevX - prevK;
    if (prevK === k + 1) ins.add(prevY);
    else del.add(prevX);
    x = prevX;
    y = prevY;
  }
  const hunks = [];
  let i = 0;
  let j = 0;
  while (i < n || j < m) {
    if (i < n && del.has(i) || j < m && ins.has(j)) {
      const h = { removed: [], added: [] };
      while (i < n && del.has(i) || j < m && ins.has(j)) {
        if (i < n && del.has(i)) h.removed.push(A[i++]);
        else {
          h.added.push({ line: s + j + 1, text: B[j] });
          j++;
        }
      }
      hunks.push(h);
    } else {
      i++;
      j++;
    }
  }
  return hunks;
}
function pseudoEntry(file, before, after) {
  const hunks = diffLines(before.split("\n").map(stripCr2), after.split("\n").map(stripCr2));
  return { file, status: before === "" ? "A" : "M", hunks };
}
function stripLongPrefix(p) {
  const s = String(p);
  if (/^\\\\\?\\UNC\\/i.test(s)) return "\\\\" + s.slice(8);
  if (/^\\\\\?\\/.test(s)) return s.slice(4);
  if (/^\/\/\?\/UNC\//i.test(s)) return "//" + s.slice(8);
  if (/^\/\/\?\//.test(s)) return s.slice(4);
  return s;
}
function relativeToRoot(root0, file0, { pathApi = path, real = realpathSync2 } = {}) {
  const root = stripLongPrefix(root0);
  const file = stripLongPrefix(file0);
  const rp = (p) => {
    try {
      return real(p);
    } catch {
      return null;
    }
  };
  const abs = pathApi.resolve(file);
  const realRoot = rp(root) ?? pathApi.resolve(root);
  let dir = pathApi.dirname(abs);
  const tail = [pathApi.basename(abs)];
  let realDir = rp(dir);
  while (realDir === null && dir !== pathApi.dirname(dir)) {
    tail.unshift(pathApi.basename(dir));
    dir = pathApi.dirname(dir);
    realDir = rp(dir);
  }
  const realFile = pathApi.join(realDir ?? dir, ...tail);
  const norm2 = (p) => String(p).replace(/\\/g, "/").replace(/\/+$/, "");
  const ci = pathApi === path.win32;
  const R = norm2(realRoot);
  const F = norm2(realFile);
  const cmp = (s) => ci ? s.toLowerCase() : s;
  if (cmp(F) === cmp(R)) return "";
  return cmp(F).startsWith(cmp(R) + "/") ? F.slice(R.length + 1) : null;
}
function locate(file, baseRoot) {
  let dir = path.dirname(file);
  const tail = [path.basename(file)];
  while (!existsSync3(dir) && dir !== path.dirname(dir)) {
    tail.unshift(path.basename(dir));
    dir = path.dirname(dir);
  }
  const r = runGit(["rev-parse", "--show-toplevel", "--show-prefix"], { cwd: dir });
  if (r.status === 0) {
    const [top, prefix = ""] = String(r.stdout).split("\n");
    if (top) return { top, rel: prefix + tail.join("/") };
  }
  const rel = relativeToRoot(baseRoot, file);
  return rel ? { top: null, root: baseRoot, rel } : null;
}
function proposedCheck(payload, { cwd = process.cwd(), defaultsDir, asNew = false } = {}) {
  const base = String(payload.cwd || payload.workspace?.current_dir || process.env.CLAUDE_PROJECT_DIR || cwd);
  let baseRoot = base;
  try {
    baseRoot = realpathSync2(base);
  } catch {
  }
  const changes = fromPayload(payload, base);
  const result = { ok: true, mode: "proposed", rulesFrom: "resolved", findings: [], skipped: [] };
  if (changes.length === 0) return result;
  const groups = /* @__PURE__ */ new Map();
  const notices = [];
  for (const c of changes) {
    const where2 = locate(c.file, baseRoot);
    if (!where2) {
      result.skipped.push({ file: c.file.split(path.sep).join("/"), reason: "outside-repository" });
      notices.push("a file is outside every repository and the project root: not judged");
      continue;
    }
    const key = where2.top ?? `nogit:${where2.root}`;
    if (!groups.has(key)) groups.set(key, { where: where2, items: [] });
    groups.get(key).items.push({ ...c, rel: where2.rel });
  }
  let first = true;
  for (const { where: where2, items } of groups.values()) {
    const root = where2.top ?? where2.root;
    let rules;
    let rulesFrom = "resolved";
    let notice;
    const loaded = where2.top ? loadRules({ cwd: where2.top, refs: hasHead(where2.top) ? ["HEAD"] : [], fromLabel: "head" }) : loadWorktreeRules(root);
    if (loaded) {
      rules = loaded.rules;
      rulesFrom = loaded.rulesFrom;
      notice = loaded.notice;
    } else {
      rules = resolveUnmigrated({ projectDir: root, defaultsDir });
      notice = UNMIGRATED_NOTICE;
    }
    const entries = [];
    const posts = /* @__PURE__ */ new Map();
    const bases = /* @__PURE__ */ new Map();
    for (const c of items) {
      const before = asNew ? "" : c.before;
      entries.push(pseudoEntry(c.rel, before, c.after));
      posts.set(c.rel, c.after);
      bases.set(c.rel, before === "" ? null : before);
    }
    const r = evaluate(entries, rules, {
      readPost: (f) => posts.get(f) ?? null,
      readBase: (e) => bases.get(e.file) ?? null,
      projectDir: root,
      mode: "proposed",
      rulesFrom,
      // Imports are judged where the package is installed by the time the code is committed, not mid-edit.
      skipBuiltins: ["imports-declared"]
    });
    result.findings.push(...r.findings);
    result.skipped.push(...r.skipped);
    if (first) {
      result.rulesFrom = rulesFrom;
      if (rules.typegenHint) result.typegenHint = rules.typegenHint;
      first = false;
    }
    if (notice) notices.push(notice);
  }
  result.ok = !result.findings.some((f) => f.severity === "error");
  if (notices.length) result.notice = [...new Set(notices)].join("; ");
  return result;
}

// lib/check/state.mjs
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync as readFileSync6, statSync as statSync2, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { isAbsolute as isAbsolute3, join as join5, resolve as resolve2 } from "node:path";
function stateDir(cwd) {
  try {
    const p = String(gitOut(["rev-parse", "--git-path", "composure-check"], { cwd })).trim();
    const dir = isAbsolute3(p) ? p : resolve2(cwd, p);
    mkdirSync(dir, { recursive: true });
    return dir;
  } catch {
    return null;
  }
}
function readState(dir, name) {
  if (!dir) return null;
  try {
    return JSON.parse(readFileSync6(join5(dir, name), "utf8"));
  } catch {
    return null;
  }
}
function writeState(dir, name, value) {
  if (!dir) return;
  try {
    writeFileSync(join5(dir, name), JSON.stringify(value));
  } catch {
  }
}
function violationHash(findings) {
  const keys = findings.filter((f) => f.severity === "error").map((f) => `${f.rule}|${f.file}|${f.text}`).sort();
  return createHash("sha1").update(keys.join("\n")).digest("hex");
}
function treeHash(cwd) {
  const head = (() => {
    try {
      return String(gitOut(["rev-parse", "-q", "--verify", "HEAD"], { cwd })).trim();
    } catch {
      return "none";
    }
  })();
  const status = String(gitOut(["status", "--porcelain=v2", "-z", "--untracked-files=all"], { cwd }));
  const h = createHash("sha1").update(head).update("\0").update(status);
  const tokens = status.split("\0");
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (!t) continue;
    let path2 = null;
    if (t[0] === "1") path2 = t.split(" ").slice(8).join(" ");
    else if (t[0] === "2") {
      path2 = t.split(" ").slice(9).join(" ");
      i++;
    } else if (t[0] === "u") path2 = t.split(" ").slice(10).join(" ");
    else if (t[0] === "?") path2 = t.slice(2);
    if (path2) {
      try {
        const s = statSync2(join5(cwd, path2));
        h.update(`${path2}|${s.size}|${s.mtimeMs}\0`);
      } catch {
        h.update(`${path2}|gone\0`);
      }
    }
  }
  return h.digest("hex");
}
function bumpSessionCount(sessionId) {
  const file = join5(tmpdir(), `composure-enforcement-${String(sessionId || "unknown").replace(/[^\w.-]/g, "_")}`);
  let n = 0;
  try {
    n = parseInt(readFileSync6(file, "utf8"), 10) || 0;
  } catch {
  }
  n++;
  try {
    writeFileSync(file, String(n));
  } catch {
  }
  return n;
}

// lib/check/proposed-hook.mjs
function runProposed({ payload, complete = true, empty = false, pluginRoot, sessionId }) {
  if (!complete && !empty) {
    return { exit: 0, stdout: "", stderr: "composure-check proposed: the payload was incomplete or not JSON; allowing the edit (commit and CI still check it)\n" };
  }
  try {
    const result = proposedCheck(payload, { defaultsDir: join6(pluginRoot, "defaults") });
    const errs = result.findings.filter((f) => f.severity === "error");
    const ws = result.findings.filter((f) => f.severity === "warn");
    if (errs.length) {
      const file = fromPayload(payload)[0]?.file ?? "";
      const base = file.split(/[\\/]/).pop();
      const lang = LANG_MAP[base.split(".").pop()] || "";
      const count = bumpSessionCount(sessionId || payload.session_id);
      return { exit: 2, stdout: "", stderr: blockReminder(result, { base, lang, typegenHint: result.typegenHint ?? "", count }) };
    }
    const stdout = ws.length ? JSON.stringify({ systemMessage: `Framework warnings (non-blocking):
${warnMessage(ws)}` }) + "\n" : "";
    return { exit: 0, stdout, stderr: "" };
  } catch (e) {
    return { exit: 0, stdout: "", stderr: `composure-check proposed: ${e.message}; allowing the edit (commit and CI still check it)
` };
  }
}

// ../hooks/lib/stdin.mjs
import { isatty } from "node:tty";
var PIPED_STDIN_MS = 2e3;
function readStdin({ deadlineMs } = {}) {
  if (!Number.isFinite(deadlineMs) || deadlineMs <= 0) throw new TypeError("readStdin needs deadlineMs: half of the calling hook's declared timeout, in ms");
  return new Promise((resolve4) => {
    if (isatty(0)) return resolve4({ bytes: Buffer.alloc(0), complete: true });
    const chunks = [];
    let timer = null;
    let settled = false;
    const finish2 = (complete) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      const s = process.stdin;
      s.removeListener("data", onData);
      s.removeListener("end", onEnd);
      s.removeListener("error", onError);
      s.destroy();
      resolve4({ bytes: Buffer.concat(chunks), complete });
    };
    const onData = (c) => chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c));
    const onEnd = () => finish2(true);
    const onError = () => finish2(chunks.length === 0);
    try {
      process.stdin.on("data", onData).on("end", onEnd).on("error", onError);
      timer = setTimeout(() => finish2(false), deadlineMs);
    } catch {
      finish2(true);
    }
  });
}

// check/composure-check.mjs
var HERE = dirname(fileURLToPath(import.meta.url));
var PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT || join7(HERE, "..", "..");
var BOOL_FLAGS = /* @__PURE__ */ new Set(["worktree", "staged", "resolve", "version", "unmigrated"]);
var VALUE_FLAGS = /* @__PURE__ */ new Set(["range", "rules-ref", "format", "cwd", "stack", "defaults", "overrides", "max-added"]);
var UsageError = class extends Error {
};
function parseArgs(argv) {
  const flags = {};
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) {
      rest.push(a);
      continue;
    }
    const key = a.slice(2);
    if (BOOL_FLAGS.has(key)) flags[key] = true;
    else if (VALUE_FLAGS.has(key)) {
      const value = argv[++i];
      if (value === void 0 || value === "" || value.startsWith("--")) throw new UsageError(`--${key} needs a value${value === "" ? " (it is empty: an unset CI variable?)" : ""}`);
      flags[key] = value;
    } else throw new UsageError(`unknown flag --${key}`);
  }
  if ([flags.worktree, flags.staged, flags.range !== void 0].filter(Boolean).length > 1) throw new UsageError("choose one of --worktree, --staged, --range");
  if (flags.format !== void 0 && flags.format !== "text" && flags.format !== "json") throw new UsageError("--format is text or json");
  if (flags["max-added"] !== void 0 && !(Number(flags["max-added"]) > 0)) throw new UsageError("--max-added needs a positive number");
  return { flags, rest };
}
async function readPayload() {
  const { bytes, complete } = await readStdin({ deadlineMs: PIPED_STDIN_MS });
  const text = bytes.toString("utf8");
  if (!text.trim()) return { payload: {}, complete, empty: true };
  try {
    const parsed = JSON.parse(text);
    return { payload: parsed && typeof parsed === "object" ? parsed : {}, complete, empty: false };
  } catch {
    return { payload: {}, complete: false, empty: false };
  }
}
var out = (s) => process.stdout.write(s);
var err = (s) => process.stderr.write(s);
function finish(code) {
  process.exitCode = code;
}
async function cmdCheck(flags) {
  const cwd = resolve3(flags.cwd || process.cwd());
  const mode = flags.staged ? "staged" : flags.range ? "range" : "worktree";
  const result = runCheck({ cwd, mode, range: flags.range, rulesRef: flags["rules-ref"], defaultsDir: join7(PLUGIN_ROOT, "defaults"), unmigrated: flags.unmigrated === true, maxAdded: flags["max-added"] ? Number(flags["max-added"]) : void 0 });
  out(flags.format === "json" ? JSON.stringify(result, null, 2) + "\n" : formatText(result));
  finish(result.ok ? 0 : 1);
}
async function cmdProposed() {
  const { payload, complete, empty } = await readPayload();
  const r = runProposed({ payload, complete, empty, pluginRoot: PLUGIN_ROOT, sessionId: process.env.CLAUDE_SESSION_ID });
  if (r.stdout) out(r.stdout);
  if (r.stderr) err(r.stderr);
  finish(r.exit);
}
async function cmdHook(host) {
  const { payload } = await readPayload();
  const emit = (decision) => {
    const o = stopOutput(host, decision);
    if (o.stdout) out(o.stdout);
    if (o.stderr) err(o.stderr);
    finish(o.exit);
  };
  const cwd = resolve3(payload.cwd || payload.workspace?.current_dir || process.env.CLAUDE_PROJECT_DIR || process.cwd());
  const session = String(payload.session_id ?? process.env.CLAUDE_SESSION_ID ?? "");
  let dir = null;
  try {
    const root = gitRoot(cwd);
    if (!root) return emit({ action: "allow" });
    dir = stateDir(root);
    const th = treeHash(root);
    const last = readState(dir, "last-check.json");
    if (last && last.treeHash === th && last.clean) return emit({ action: "allow" });
    const result = runCheck({ cwd: root, mode: "worktree", maxAdded: STOP_MAX_ADDED, defaultsDir: join7(PLUGIN_ROOT, "defaults") });
    const errs = result.findings.filter((f) => f.severity === "error");
    writeState(dir, "last-check.json", { treeHash: th, clean: errs.length === 0 });
    if (errs.length === 0) {
      const parts = [result.tooLarge ? result.notice : "", unjudgedNotice(result), result.findings.length ? `Non-blocking findings:
${warnMessage(result.findings)}` : ""].filter(Boolean);
      return emit({ action: "allow", systemMessage: parts.join("\n") || void 0 });
    }
    return guarded(emit, dir, session, payload, violationHash(result.findings), { findings: result.findings }, errs.length);
  } catch (e) {
    const reason = `composure-check could not run: ${e.message}`;
    return guarded(emit, dir, session, payload, violationHash([{ severity: "error", rule: "checker-error", file: "", text: e.message }]), { reason }, 1);
  }
}
function guarded(emit, dir, session, payload, hash, block, count) {
  const last = readState(dir, "last-block.json");
  if (payload.stop_hook_active === true && last && last.hash === hash && last.session === session) {
    return emit({ action: "allow", systemMessage: `composure-check: ${count} violation${count === 1 ? "" : "s"} still present after one continuation; allowing the stop. The commit gate will block these.` });
  }
  writeState(dir, "last-block.json", { session, hash });
  return emit({ action: "block", ...block });
}
function cmdRules(flags) {
  if (!flags.resolve) throw new Error("rules: use --resolve");
  if (!flags.defaults) throw new Error("rules --resolve needs --defaults <dir>");
  const read = (p) => {
    try {
      return JSON.parse(readFileSync7(p, "utf8"));
    } catch {
      return null;
    }
  };
  const stack = flags.stack && existsSync4(flags.stack) ? read(flags.stack) ?? {} : {};
  const existing = flags.overrides && existsSync4(flags.overrides) ? read(flags.overrides) : null;
  try {
    const resolved = resolveRules({ stack, defaultsDir: resolve3(flags.defaults), existing });
    validateRuleSet(resolved, "resolved rules");
    out(JSON.stringify(resolved, null, 2) + "\n");
    finish(0);
  } catch (e) {
    if (!(e instanceof RulesError)) throw e;
    err(`composure-check rules --resolve: ${e.message}
`);
    finish(2);
  }
}
async function main() {
  try {
    const { flags, rest } = parseArgs(process.argv.slice(2));
    const cmd = rest[0];
    if (cmd === "version" || flags.version) {
      out(`composure-check ${CHECKER_VERSION}
`);
      return finish(0);
    }
    if (cmd === "proposed") return await cmdProposed();
    if (cmd === "hook") {
      if (!rest[1]) {
        err("usage: composure-check hook <claude|codex>\n");
        return finish(2);
      }
      return await cmdHook(rest[1]);
    }
    if (cmd === "rules") return cmdRules(flags);
    if (cmd && cmd !== "check") {
      err(`unknown command "${cmd}"
`);
      return finish(2);
    }
    return await cmdCheck(flags);
  } catch (e) {
    err(`composure-check: ${e.message}
`);
    finish(2);
  }
}
await main();
