#!/usr/bin/env bash
# tool-windows-refuse.sh [app folder] — prints "file:line  what" for every way a development tool can put a window on the
# owner's display, and nothing when there is none. `scripts/check.sh snapshot` runs it on app/.
#
# Every window a tool makes is the shared `OffscreenWindow` (app/Sources/ToolWindows): AppKit moves any other titled window or
# panel back onto the main display when it is ordered in, and a modal panel is shown on it by design. The tools are every
# executable target in Package.swift except the app itself (MacAnalyzersApp), so a new tool is covered without an edit here.
# In a tool's sources, comment lines ignored, refused:
#   a window or panel made directly: NSWindow(…) NSPanel(…) NSWindow.init(…) `: NSWindow = .init(…)` `typealias W = NSWindow`
#   a subclass of NSWindow or NSPanel, however the class line is wrapped
#   NSAlert, NSSavePanel, NSOpenPanel, runModal, presentAsModalWindow, presentAsSheet, beginSheetModal
# The window rules above cover every executable but the app, bundled or not (agent-runner and notify ship inside it and open
# no window). The ToolWindows target is narrower: only an executable that is NEVER bundled may depend on it, mention
# OffscreenWindow or import it, so the app people install does not contain the type. "Bundled" is read from app/build.sh's
# `cp "$BIN/<Executable>" …` lines, so a tool that starts being bundled is caught; SnapshotRunner and MenuSnapshot are the
# expected unbundled ones. ToolWindows itself must depend on nothing of ours.
set -u
app="${1:-app}"
manifest="$app/Package.swift"
[ -f "$manifest" ] || { echo "tool-windows-refuse: no $manifest" >&2; exit 2; }
[ -f "$app/build.sh" ] || { echo "tool-windows-refuse: no $app/build.sh to read what is bundled from" >&2; exit 2; }
exec perl -e '
use strict; use warnings;
my ($app, $manifest) = @ARGV;
my %bundled;
{ local $/; open(my $h, "<", "$app/build.sh") or die; my $b = <$h>; close $h;
  $bundled{$1} = 1 while $b =~ /^\s*cp\s+"\$(?:\{BIN\}|BIN)\/(\w+)"/mg; }
die "tool-windows-refuse: no bundled executable found in $app/build.sh\n" unless %bundled;
sub slurp { my $f = shift; local $/; open(my $h, "<", $f) or return ""; my $t = <$h>; close $h; return $t; }
sub blank { my $s = shift; $s =~ s{/\*.*?\*/}{ my $m = $&; $m =~ s/[^\n]//g; $m }gse; $s =~ s{//[^\n]*}{}g; return $s; }
my $pkg = blank(slurp($manifest));
# one segment per declared target: from its ".xxxTarget(" to the next one
my @parts = split /(?=\.(?:executableTarget|target|testTarget|plugin)\s*\()/, $pkg;
my (%kind, %deps, @tools);
for my $p (@parts) {
  next unless $p =~ /^\.(executableTarget|target|testTarget)\s*\(\s*name:\s*"(\w+)"/s;
  my ($k, $n) = ($1, $2); $kind{$n} = $k; $deps{$n} = $p;
  push @tools, $n if $k eq "executableTarget" && $n ne "MacAnalyzersApp";
}
my %tool = map { $_ => 1 } @tools;
# the executables that may use the window type: tools that are never bundled
my %may = map { $_ => 1 } grep { !$bundled{$_} } @tools;
my @out;
for my $n (sort keys %deps) {
  next if $n eq "ToolWindows" || $may{$n};
  push @out, "$manifest  \xe2\x80\x94 $n depends on ToolWindows: only a tool that is never bundled into the app may" if $deps{$n} =~ /"ToolWindows"/;
}
if (exists $deps{ToolWindows} && $deps{ToolWindows} =~ /dependencies:\s*\[\s*"/) {
  push @out, "$manifest  \xe2\x80\x94 ToolWindows depends on another target: it is AppKit only";
}
my @files = split /\n/, `find "$app/Sources" -name "*.swift" 2>/dev/null | sort`;
for my $f (@files) {
  my ($dir) = $f =~ m{/Sources/([^/]+)/};
  next unless defined $dir;
  my $text = blank(slurp($f));
  my $at = sub { my $pos = shift; my $line = 1 + (() = substr($text, 0, $pos) =~ /\n/g); return "$f:$line"; };
  if ($dir ne "ToolWindows" && !$may{$dir}) {
    while ($text =~ /\bOffscreenWindow\b|\bimport\s+ToolWindows\b/g) { push @out, $at->($-[0]) . "  \xe2\x80\x94 the tools\x27 window type outside a tool that is never bundled"; }
  }
  next unless $tool{$dir};
  my @rules = (
    [qr/\bNS(?:Window|Panel)\s*(?:\.init)?\s*\(/, "a plain window or panel: use OffscreenWindow"],
    [qr/:\s*NS(?:Window|Panel)\??\s*=\s*\.init\b/, "a plain window or panel made with .init: use OffscreenWindow"],
    [qr/\btypealias\s+\w+\s*=\s*NS(?:Window|Panel)\b/, "an alias of a plain window or panel: use OffscreenWindow"],
    [qr/\bclass\s+\w+\s*(?:<[^>{]*>)?\s*:[^{]*?\bNS(?:Window|Panel)\b/s, "a subclass of NSWindow or NSPanel: subclass nothing, use OffscreenWindow"],
    [qr/\bNS(?:Alert|SavePanel|OpenPanel)\b|\.runModal\s*\(|\bpresentAsModalWindow\b|\bpresentAsSheet\b|\bbeginSheetModal\b/, "a modal panel: it is shown on the owner\x27s display"],
  );
  for my $r (@rules) {
    while ($text =~ /$r->[0]/g) { push @out, $at->($-[0]) . "  \xe2\x80\x94 $r->[1]"; }
  }
}
print "$_\n" for @out;
' "$app" "$manifest"
