import Foundation

/// Identity of one sidebar section. The value is a plain string so a group
/// file can declare its own constants without a shared enum — and so a saved
/// location from an older build still decodes (an unknown id falls back to
/// Overview when the window opens).
struct SectionID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
