#!/usr/bin/env bash
# snapshot-windows-test.sh — scripts/tool-windows-refuse.sh (what `scripts/check.sh snapshot` runs) refuses every way a development
# tool can put a window on the owner's display and passes the shared OffscreenWindow. Each case plants a small app folder (a
# Package.swift, a build.sh whose cp lines say what is bundled, plus one Swift file) and asks the real script. Runs under bash and /bin/bash.
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
    .executableTarget(name: "NotifierCLI", dependencies: ["AnalyzersKit"]),
    .executableTarget(name: "SnapshotRunner", dependencies: ["AnalyzersKit", "ToolWindows"]),
    .executableTarget(name: "NewTool", dependencies: ["AnalyzersKit"]),
    .target(name: "ToolWindows"),
    .target(name: "AnalyzersKit"),
])'
# what the app's build copies into the bundle, as app/build.sh does
BUILD='cp "$BIN/MacAnalyzersApp" "$APP/Contents/MacOS/MacAnalyzersApp"
cp "$BIN/NotifierCLI" "$APP/Contents/MacOS/notify"
cp "$BIN/AgentRunner" "$APP/Contents/MacOS/agent-runner"'
# the same manifest with AgentRunner depending on ToolWindows, and the same build with SnapshotRunner copied in as well
MANIFEST_AGENT_TW="$(printf '%s\n' "$MANIFEST" | sed 's/name: "AgentRunner", dependencies: \["AnalyzersKit"\]/name: "AgentRunner", dependencies: ["AnalyzersKit", "ToolWindows"]/')"
BUILD_WITH_SNAPSHOT="$BUILD
"'cp "$BIN/SnapshotRunner" "$APP/Contents/MacOS/SnapshotRunner"'
# plant <case> <target folder> <swift text> [manifest] [build.sh]: what the script prints for that tree
plant() {
  local d="$TMP/$1"; mkdir -p "$d/Sources/$2"; printf '%s\n' "${4:-$MANIFEST}" > "$d/Package.swift"; printf '%s\n' "${5:-$BUILD}" > "$d/build.sh"
  printf '%s\n' "$3" > "$d/Sources/$2/X.swift"
  "$SCAN" "$d" 2>&1
}
refused() { [[ -n "$(plant "$2" "$3" "$4" "${5:-}" "${6:-}")" ]] && check "$1" ok || check "$1" "was NOT refused"; }
passes()  { [[ -z "$(plant "$2" "$3" "$4" "${5:-}" "${6:-}")" ]] && check "$1" ok || check "$1" "was refused: $(plant "$2" "$3" "$4" "${5:-}" "${6:-}" | head -1)"; }

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
refused "AgentRunner (bundled as agent-runner) depending on ToolWindows" W AgentRunner 'let x = 1' "$MANIFEST_AGENT_TW"
refused "OffscreenWindow used in NotifierCLI (bundled as notify)" X NotifierCLI 'let w = OffscreenWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
refused "OffscreenWindow used in AgentRunner" Y AgentRunner 'import ToolWindows'
refused "a tool that starts being bundled loses the window type" Z SnapshotRunner 'let w = OffscreenWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)' "" "$BUILD_WITH_SNAPSHOT"
refused "a plain window in a bundled executable is still refused" AA NotifierCLI 'let w = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
passes  "an OffscreenWindow in a tool that is never bundled" R SnapshotRunner 'let w = OffscreenWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
passes  "a window in the app itself" S MacAnalyzersApp 'let w = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)'
passes  "the type's own definition" T ToolWindows 'public final class OffscreenWindow: NSWindow {}'
passes  "a mention in a comment" U SnapshotRunner '// an NSWindow( or NSAlert() here would be shown on the display'
passes  "a mention in a block comment" V SnapshotRunner '/* NSPanel( and
   runModal() */'
exit "$fail"
