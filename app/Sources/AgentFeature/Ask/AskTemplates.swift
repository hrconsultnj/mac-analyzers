import Foundation
import AnalyzersKit

/// One launch template on the Ask home (S1's grid). The template is not a
/// macro: pressing it starts the same loop a typed message starts — the only
/// difference is that the prompt was pre-written by someone who knows what to
/// ask, so nobody has to face a blank box. Every template maps to a fixed
/// READ-ONLY engine invocation (the loop's scan beat), run as a tracked job
/// through the one `JobStore`, so Activity lists every run.
public struct AskTemplate: Identifiable, Equatable, Sendable {

    public let id: String
    /// The button's title, in the person's words ("Free up space").
    public let title: String
    /// One line under the title, saying what will happen.
    public let subtitle: String
    /// The tile's symbol (the Ask row's tint draws it).
    public let symbol: String
    /// The message the button sends. Improving a prompt is a change to this
    /// file, never to a person's config.
    public let prompt: String
    /// The analyzer the turn's scan beat runs, as a `JobStore` request.
    /// Cleaners appear only as a `.preview` (dry run); an agent never queues
    /// an apply — the approved list goes through `JobStore.apply(from:)` only
    /// after a person has ticked it.
    public let scanKind: JobKind
    public let scanIntent: JobIntent

    public init(id: String, title: String, subtitle: String, symbol: String,
                prompt: String, scanKind: JobKind, scanIntent: JobIntent) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.prompt = prompt
        self.scanKind = scanKind
        self.scanIntent = scanIntent
    }

    /// The four launch templates, in grid order (two rows of two).
    public static let all: [AskTemplate] = [
        AskTemplate(
            id: "free-space",
            title: "Free Up Space",
            subtitle: "Scan the disk and propose what is safe to clean.",
            symbol: "internaldrive",
            prompt: "Look at my disk and the latest storage report. What is taking the space, "
                + "and what is safe to clean? Propose a cleanup as a list I can review — "
                + "show me the list before anything is touched.",
            scanKind: .storageReport, scanIntent: .run),
        AskTemplate(
            id: "mac-slow",
            title: "My Mac Feels Slow",
            subtitle: "Find what is using the memory.",
            symbol: "gauge.with.dots.needle.33percent",
            prompt: "My Mac feels slow. Check memory pressure right now and the latest memory report, "
                + "name what is using the memory, and propose what I could safely close or clean — "
                + "as a list to look at first.",
            scanKind: .memoryReport, scanIntent: .run),
        AskTemplate(
            id: "tidy-downloads",
            title: "Tidy My Downloads",
            subtitle: "Review old files before anything moves.",
            symbol: "arrow.down.circle",
            prompt: "Preview the Downloads cleanup: list the old files it would move to the Trash, "
                + "with sizes and dates, and propose it for my review.",
            scanKind: .janitor, scanIntent: .preview),
        AskTemplate(
            id: "memory-hogs",
            title: "What's Eating My Memory?",
            subtitle: "See the biggest users right now.",
            symbol: "memorychip",
            prompt: "What is eating my memory right now? Group the biggest users by app, "
                + "and tell me which are worth closing and which I should leave alone.",
            scanKind: .memoryReport, scanIntent: .run),
    ]

    /// The home grid's shape: two rows of two. A fifth template is a design
    /// change to this grid, not an extra row here.
    public static let gridRows: [[AskTemplate]] = [
        Array(all[0..<2]),
        Array(all[2..<4]),
    ]
}
