#!/usr/bin/env bash
# snapshot-windows-test.sh — scripts/tool-windows-refuse.sh (what `scripts/check.sh snapshot` runs) refuses every way a development
# tool can put a window on the owner's display and passes the shared OffscreenWindow. Each case plants a small app folder (a
# Package.swift plus one Swift file) and asks the real script. Runs under bash and /bin/bash.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/../scripts/tool-windows-refuse.sh"
[[ -x "$SCAN" ]] || { echo "SKIP: no scripts/tool-windows-refuse.sh"; exit 0; }
command -v perl >/dev/null || { echo "SKIP: no perl"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if [[ "$2" == "ok" ]]; then echo "PASS  $1"; else echo "FAIL  $1 ($2)"; fail=1; fi; }
MANIFEST='// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "x", targets: [
    .executableTarget(name: "MacAnalyzersApp", dependencies: ["AnalyzersKit"]),
    .executableTarget(name: "AgentRunner", dependencies: ["AnalyzersKit"]),
    .executableTarget(name: "SnapshotRunner", dependencies: ["AnalyzersKit", "ToolWindows"]),
    .executableTarget(name: "NewTool", dependencies: ["AnalyzersKit"]),
    .target(name: "ToolWindows"),
    .target(name: "AnalyzersKit"),
])'
# plant <case> <target folder> <swift text> [manifest]: what the script prints for that tree
plant() {
  local d="$TMP/$1"; mkdir -p "$d/Sources/$2"; printf '%s\n' "${4:-$MANIFEST}" > "$d/Package.swift"; printf '%s\n' "$3" > "$d/Sources/$2/X.swift"
  "$SCAN" "$d" 2>&1
}
refused() { [[ -n "$(plant "$2" "$3" "$4" "${5:-}")" ]] && check "$1" ok || check "$1" "was NOT refused"; }
passes()  { [[ -z "$(plant "$2" "$3" "$4" "${5:-}")" ]] && check "$1" ok || check "$1" "was refused: $(plant "$2" "$3" "$4" "${5:-}" | head -1)"; }

refused "NSWindow( in SnapshotRunner" A SnapshotRunner 'let w = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
refused "NSPanel( in a tool" B AgentRunner 'let p = NSPanel(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
refused "NSWindow.init(" C SnapshotRunner 'let w = NSWindow.init(contentRect: r, styleMask: m, backing: .buffered, defer: false)'
refused "a typed .init" D SnapshotRunner 'let w: NSWindow = .init(contentRect: r, styleMask: m, backing: .buffered, defer: false)'
refused "a typealias of NSWindow" E SnapshotRunner 'typealias Win = NSWindow'
refused "a subclass of NSWindow" F SnapshotRunner 'final class ProbeWindow: NSWindow {'
refused "a subclass whose superclass is on the next line" G SnapshotRunner 'final class ProbeWindow:
    NSWindow, SomeProtocol {'
refused "a subclass with several protocols after NSPanel" H SnapshotRunner 'final class P: NSPanel, A, B {'
refused "NSAlert" I SnapshotRunner 'let a = NSAlert()'
refused "NSSavePanel" J SnapshotRunner 'let p = NSSavePanel()'
refused "NSOpenPanel" K SnapshotRunner 'let p = NSOpenPanel()'
refused "runModal" L SnapshotRunner 'panel.runModal()'
refused "presentAsModalWindow" M SnapshotRunner 'controller.presentAsModalWindow(other)'
refused "a window in a tool the script was never told about" N NewTool 'let w = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
refused "OffscreenWindow used outside the tools" O AnalyzersKit 'let w = OffscreenWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
refused "import ToolWindows outside the tools" P AnalyzersKit 'import ToolWindows'
refused "the app depending on ToolWindows" Q AnalyzersKit 'let x = 1' "${MANIFEST/\"AnalyzersKit\"]),
    .executableTarget(name: \"AgentRunner\"/\"AnalyzersKit\", \"ToolWindows\"]),
    .executableTarget(name: \"AgentRunner\"}"
passes  "an OffscreenWindow in a tool" R SnapshotRunner 'let w = OffscreenWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
passes  "a window in the app itself" S MacAnalyzersApp 'let w = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
passes  "the type's own definition" T ToolWindows 'public final class OffscreenWindow: NSWindow {}'
passes  "a mention in a comment" U SnapshotRunner '// an NSWindow( or NSAlert() here would be shown on the display'
passes  "a mention in a block comment" V SnapshotRunner '/* NSPanel( and
   runModal() */'
exit "$fail"
