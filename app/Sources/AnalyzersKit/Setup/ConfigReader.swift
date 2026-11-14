import Foundation

/// Minimal reader for the shell config the app and the engine share. The app
/// writes it; this reads the values back so Setup reports what is really in
/// the file rather than what the UI last had in memory.
enum ConfigReader {
    static func rawValue(forKey key: String) -> String? {
        guard let text = try? String(contentsOf: AnalyzersPaths.configLocal,
                                     encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key)=") || trimmed.hasPrefix("export \(key)=") else { continue }
            let value = trimmed.split(separator: "=", maxSplits: 1)[1]
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return nil
    }

    static func intValue(forKey key: String) -> Int? {
        rawValue(forKey: key).flatMap { Int($0) }
    }

    static func listValue(forKey key: String) -> [String] {
        guard let raw = rawValue(forKey: key) else { return [] }
        return raw.split(whereSeparator: { $0 == "|" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
