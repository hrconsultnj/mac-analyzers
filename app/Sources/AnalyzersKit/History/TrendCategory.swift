import Foundation

/// Level 2 of Trends: the two kinds of thing it reports on. Memory is what the
/// guard and the cleaners did about running processes; Storage is what the
/// cleanups removed from disk. Each is one tab with its own headline number;
/// a person looking for "how much disk did it free" does not scroll past
/// memory spikes to find out.
public enum TrendCategory: String, CaseIterable, Identifiable, Sendable {
    case memory, storage
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .memory: Names.Group.memory
        case .storage: Names.Group.storage
        }
    }

    public var symbol: String {
        switch self {
        case .memory: "memorychip"
        case .storage: "internaldrive"
        }
    }
}
