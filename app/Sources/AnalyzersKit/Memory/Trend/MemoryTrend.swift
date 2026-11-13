import Foundation
import Observation

/// The short history behind the memory screens, and the one sampler that fills it.
///
/// - **One sampler for every screen**: `begin()` and `end()` are called by the screens as they appear and go; samples are
///   taken only while at least one is open, every `interval` (2 s), and the graphics driver's figure (an IORegistry read)
///   only every fifth time.
/// - **Short, and in memory only**: the last `capacity` samples (900, 30 minutes at 2 s, about 100 KB), never written to
///   disk. If every screen was closed for more than `restartAfter` the history starts again (a gap drawn as a line would
///   say something that was not measured), and `since` says when it began.
/// - **Cheap**: one `host_statistics64`, two `sysctl`s per sample (about 3 microseconds of reads).
@MainActor @Observable
public final class MemoryTrend {

    public static let shared = MemoryTrend()

    public nonisolated static let interval: Duration = .seconds(2)
    public nonisolated static let capacity = 900
    public nonisolated static let restartAfter: TimeInterval = 60

    public private(set) var samples: [MemorySample] = []
    /// The newest sample, or nil before the first one.
    public var latest: MemorySample? { samples.last }

    /// The samples of the last `seconds`, oldest first.
    public func window(seconds: TimeInterval) -> [MemorySample] {
        let from = Date().addingTimeInterval(-seconds)
        return samples.filter { $0.date >= from }
    }

    /// The pressure level now (1 normal, 2 warning, 4 critical); normal before the first sample.
    public var pressureLevel: Int { samples.last?.pressureLevel ?? 1 }

    /// When the history this screen shows began.
    public var since: Date? { samples.first?.date }

    private var watchers = 0
    private var loop: Task<Void, Never>?
    private var graphics: Int64?
    private var taken = 0

    public init() {}

    /// A screen that needs the history is on screen.
    public func begin() {
        watchers += 1
        guard watchers == 1 else { return }
        if let last = samples.last, Date().timeIntervalSince(last.date) > Self.restartAfter { samples.removeAll() }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleNow()
                try? await Task.sleep(for: MemoryTrend.interval)
            }
        }
    }

    /// That screen has gone.
    public func end() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        loop?.cancel()
        loop = nil
    }

    /// Takes one sample now (the loop's step; a probe calls it too).
    public func sampleNow() async {
        let readGraphics = taken % 5 == 0
        let known = graphics
        let sample = await Task.detached(priority: .utility) { () -> (MemorySample?, Int64?) in
            let fresh = readGraphics ? MemorySample.readGraphicsBytes() : known
            return (MemorySample.read(graphics: fresh), fresh)
        }.value
        taken += 1
        graphics = sample.1 ?? graphics
        guard let reading = sample.0 else { return }
        append(reading)
    }

    /// Adds a sample and drops the oldest past `capacity` (the loop's step; a probe calls it with its own samples).
    public func append(_ sample: MemorySample) {
        samples.append(sample)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    /// For a probe: a history built from samples.
    public func replace(with new: [MemorySample]) { samples = new }
}
