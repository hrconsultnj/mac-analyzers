import SwiftUI

/// The shared visual vocabulary — the equivalent of a design-token package.
///
/// Before this, every screen picked its own literals: the same MEANING was
/// rendered in different colours across panes, and hierarchical styles were
/// being multiplied by .opacity(), which double-composites and washes a
/// surface out. Screens now spend tokens, not values, so a new pane cannot
/// drift from the ones written before it.
///
/// Two vocabularies, deliberately separate:
///   Status — WHAT HAPPENED to the user's stuff (never a domain hue)
///   Domain — WHERE YOU ARE (identity; never handed to a badge or chip)
public enum Tokens {

    // MARK: - Spacing scale
    // Every current literal maps into this ramp; 4/5/9 collapse to xs/s.
    public enum Space {
        public static let hair:  CGFloat = 1    // tight two-line label stacks
        public static let xxs:   CGFloat = 2
        public static let xs:    CGFloat = 3
        public static let s:     CGFloat = 6    // the dominant row spacing
        public static let m:     CGFloat = 8
        public static let l:     CGFloat = 10
        public static let xl:    CGFloat = 12
        public static let xxl:   CGFloat = 16
        public static let pane:  CGFloat = 24   // PaneHeader side gutter
        public static let indent: CGFloat = 28  // sub-row indent (sudo command)
    }

    // MARK: - Radius scale
    public enum Radius {
        public static let chip:    CGFloat = 5   // inline code / micro chip
        public static let control: CGFloat = 6   // segment pill
        public static let tile:    CGFloat = 8   // stat tiles, inset panels
        public static let card:    CGFloat = 10  // brand card, glass cards
        /// IconTile keeps its optical ratio rather than a fixed radius.
        public static func icon(_ side: CGFloat) -> CGFloat { side * 0.24 }
    }

    // MARK: - Icon / tile size scale
    public enum Icon {
        public static let dotMicro: CGFloat = 5   // liveness dot
        public static let dot:      CGFloat = 8   // pressure dot
        public static let inline:   CGFloat = 16  // menu + dense list rows
        public static let row:      CGFloat = 20  // sidebar + DataCard
        public static let card:     CGFloat = 30  // Logs "big card"
        public static let hero:     CGFloat = 44  // PaneHeader + brand card
        public static let badge:    CGFloat = 16  // sidebar count bubble
    }

    // MARK: - Typography ramp
    public enum Typography {
        public static let paneTitle    = Font.title2.weight(.bold)
        public static let statValue    = Font.title3.weight(.semibold).monospacedDigit()
        public static let cardTitle    = Font.headline
        public static let rowTitle     = Font.callout
        public static let rowTitleKey  = Font.callout.weight(.medium)
        public static let sectionTitle = Font.callout.weight(.semibold)
        public static let body         = Font.callout
        public static let value        = Font.callout.monospacedDigit()
        public static let valueKey     = Font.callout.monospacedDigit().weight(.semibold)
        public static let caption      = Font.caption
        public static let captionKey   = Font.caption.weight(.semibold)
        public static let mono         = Font.caption.monospaced()
        public static let micro        = Font.caption2
        public static let badge        = Font.caption2.weight(.bold)
        public static let eyebrow      = Font.caption2.weight(.semibold)  // "CONFIGURE"
        public static let fieldLabel   = Font.subheadline.weight(.medium)
        /// Glyph inside an IconTile — optical, not a ramp step.
        public static func tileGlyph(_ side: CGFloat) -> Font {
            .system(size: side * 0.55, weight: .semibold)
        }
    }

    // MARK: - Surfaces
    // NOTE: hierarchical styles are already alpha-composited. Never multiply
    // one by .opacity() — that is what made the stat tiles disappear.
    public enum Surface {
        public static var tile: AnyShapeStyle      { AnyShapeStyle(.quaternary) }
        public static var track: AnyShapeStyle     { AnyShapeStyle(.quaternary) }
        public static var card: AnyShapeStyle      { AnyShapeStyle(.regularMaterial) }
        public static var cardHover: AnyShapeStyle { AnyShapeStyle(.thickMaterial) }
        public static var border: AnyShapeStyle    { AnyShapeStyle(.tertiary) }
        public static var borderHover: AnyShapeStyle { AnyShapeStyle(.secondary) }
        public static let borderWidth: CGFloat = 1
        /// Tint strength for a capsule/chip at rest. One number, not 0.15/0.16.
        public static let tintFill: Double = 0.15
    }

    // MARK: - Tone: a tint that always knows its own legible foreground
    /// The fix for `Color.white` hard-coded over an arbitrary fill: a tone
    /// carries the colour to fill WITH and the colour to draw ON it.
    public struct Tone: Sendable, Hashable {
        public let tint: Color
        public let onTint: Color

        public init(_ tint: Color, on onTint: Color = .white) {
            self.tint = tint
            self.onTint = onTint
        }

        /// Resting background for a badge/chip of this tone.
        public var softFill: Color { tint.opacity(Surface.tintFill) }
    }

    // MARK: - Status tones — WHAT HAPPENED
    // Rule: colour encodes the OUTCOME for the user's stuff, not the exit code.
    public enum Status {
        /// Irreversibly stopped or removed. KILLED · CLOSED · QUIT · DELETED · CRITICAL · FAILED
        public static let destructive = Tone(.red)
        /// Reversible removal, or a warning worth a look.
        /// TRASHED · SPIKE · OVER CAP · PRESSURE · IN SCOPE · WARM · NEEDS SUDO
        public static let caution = Tone(.orange)
        /// A protection held, or a run completed cleanly.
        /// PROTECTED · EXEMPT · APPLIED · DONE · RESTORED
        public static let safe = Tone(.green, on: .black)
        /// Preview only — NOTHING has happened yet.
        /// DRY RUN · WOULD REMOVE · WOULD CLOSE · DRY
        public static let preview = Tone(.blue)
        /// A document exists to read. REPORT · REPORTED · CPU · FORENSICS
        public static let report = Tone(.purple)
        /// No longer actionable. GONE · SKIPPED · ENDED · LEFTOVER? · RESTORED-elsewhere
        public static let inert = Tone(.secondary, on: .primary)
        /// Live/active affirmative (the liveness chip's ACTIVE state).
        public static let live = Tone(.green, on: .black)
        /// The neutral "no filter" chip — one answer for every FilterChipsBar.
        public static let neutral = Tone(.accentColor, on: .white)
    }

    // MARK: - Domain tones — WHERE YOU ARE
    // Identity hues for sidebar tiles, pane headers and log identities. These
    // are the ONLY place a hue may repeat a status hue, and they must never be
    // handed to BadgeCapsule / FilterChipsBar.
    public enum Domain {
        public static let overview      = Tone(.blue)
        public static let memory        = Tone(.blue)
        public static let storage       = Tone(.indigo)
        public static let notifications = Tone(.red)
        public static let schedule      = Tone(.teal, on: .black)
        public static let monitor       = Tone(.orange)
        public static let network       = Tone(.purple)
        public static let activity      = Tone(.yellow, on: .black)   // was .orange (clashed with Monitor)
        public static let logs          = Tone(.gray)
        public static let actions       = Tone(.cyan, on: .black)
        public static let trends        = Tone(.mint, on: .black)
        public static let undo          = Tone(.brown)                // was .gray (clashed with Logs/About)
        public static let about         = Tone(.gray)
        public static let update        = Tone(.green, on: .black)
        // log identities
        public static let guardLog      = Tone(.blue)
        public static let memoryClean   = Tone(.teal, on: .black)
        public static let reclaim       = Tone(.cyan, on: .black)
        public static let janitor       = Tone(.orange)
        public static let persistence   = Tone(.pink)                 // was .red (clashed with destructive)
        public static let loginItems    = Tone(.brown)
        public static let forensics     = Tone(.purple)
        // cross-cutting subjects
        public static let energy        = Tone(.yellow, on: .black)
        public static let diskIO        = Tone(.indigo)
        public static let dossier       = Tone(.cyan, on: .black)
        public static let snapshots     = Tone(.teal, on: .black)     // Time Machine — pick ONE (was purple/teal)
        public static let supporter     = Tone(.pink)                 // ProKit
    }

    // MARK: - Pressure / capacity ramps (currently 4 inline ternaries)
    public enum Ramp {
        public static func pressure(_ level: PressureLike) -> Tone {
            if level.isCritical { return Status.destructive }
            if level.isWarning { return Status.caution }
            return Status.safe
        }
        /// Disk/capacity fullness — the Finder bar and the Home disk tile.
        public static func capacity(_ fraction: Double) -> Tone {
            fraction > 0.90 ? Status.destructive
                : fraction > 0.75 ? Status.caution
                : Domain.storage
        }
        /// A process's resident size relative to the reporting floor.
        public static func residency(_ mb: Int) -> Tone {
            mb > 4096 ? Status.caution : Status.inert
        }
    }
}

/// Kept protocol-shaped so UIComponents does not need the kernel's enum.
public protocol PressureLike {
    var isWarning: Bool { get }
    var isCritical: Bool { get }
}
