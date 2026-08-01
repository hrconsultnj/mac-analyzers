import Foundation

/// Translates raw process identities ("next-server (v16.2.6)") into words a
/// non-developer can act on ("Next.js dev server"). Ordered: specific tokens
/// before generic runtimes, so "next-server" never falls through to "node".
public enum ProcessGlossary {

    private static let entries: [(token: String, friendly: String)] = [
        ("next-server", "Next.js dev server"),
        ("next dev", "Next.js dev server"),
        ("vite", "Vite dev server"),
        ("webpack", "Webpack build"),
        ("turbo", "Turborepo task"),
        ("esbuild", "esbuild bundler"),
        ("tsup", "tsup bundler"),
        ("vitest", "Vitest test runner"),
        ("jest", "Jest test runner"),
        ("playwright", "Playwright headless browser"),
        ("ms-playwright", "Playwright headless browser"),
        ("headless_shell", "Headless Chrome (test browser)"),
        ("--headless", "Headless browser"),
        ("mcp", "AI tool server (MCP)"),
        ("nodemon", "Node.js watcher"),
        ("tsx", "TypeScript runner"),
        ("deno", "Deno runtime"),
        ("bun", "Bun runtime"),
        ("npx", "npm package runner"),
        ("npm", "npm task"),
        ("node", "Node.js process"),
    ]

    /// Human description for a raw ps-args identity, or nil if unknown.
    public static func friendlyName(for raw: String) -> String? {
        let lowered = raw.lowercased()
        return entries.first { lowered.contains($0.token) }?.friendly
    }
}
