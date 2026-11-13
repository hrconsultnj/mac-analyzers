import Foundation

/// The kinds of memory the Monitor's "Where Your Memory Is" block lists, each of which opens a screen of its own.
/// The raw value is what a deep link and a pushed route carry.
public enum MemoryKind: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case app, wired, compressed, cached, free, swap

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .app: Names.MemoryKind.app
        case .wired: Names.MemoryKind.wired
        case .compressed: Names.MemoryKind.compressed
        case .cached: Names.MemoryKind.cached
        case .free: Names.MemoryKind.free
        case .swap: Names.MemoryKind.swap
        }
    }

    /// What it is, in a sentence a person reads under the number.
    public var whatItIs: String {
        switch self {
        case .app: "Memory the apps and tools you run are holding right now. It is what Activity Monitor's Memory column adds up."
        case .wired: "Memory macOS keeps for itself: the kernel, drivers and graphics. It can't be moved, squeezed or handed back."
        case .compressed: "Idle memory macOS squeezed to make room. It costs a little processor time to read back, and nothing else."
        case .cached: "Recently used files kept in spare memory for speed. They are not counted as in use: macOS hands them back the moment an app needs the room."
        case .free: "Memory nothing is using. A Mac with plenty of free memory is not better off: macOS fills spare room with cached files on purpose. What matters is the pressure."
        case .swap: "Memory macOS had to move to the disk because there was not enough room. A little is normal; a lot, growing, is a sign the Mac needs more memory."
        }
    }

    public var symbol: String {
        switch self {
        case .app: "app.dashed"
        case .wired: "lock"
        case .compressed: "rectangle.compress.vertical"
        case .cached: "doc.text"
        case .free: "circle.dashed"
        case .swap: "externaldrive"
        }
    }

    /// The deep link that opens this screen.
    public var link: String { "memorykind:\(rawValue)" }
}
