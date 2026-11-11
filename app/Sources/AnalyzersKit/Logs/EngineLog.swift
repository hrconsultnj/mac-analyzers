import Foundation

/// The suite's logs: which engine log a screen is reading, and where its file
/// lives. How each one looks (title, symbol, tint) is the presentation
/// extension in SettingsFeature.
public enum EngineLog: String, CaseIterable, Identifiable, Sendable {
    case guardLog, memoryClean, reclaim, storageClean, janitor, tempSpace, persistence,
         loginItems, spotlightAudit, forensics
    public var id: String { rawValue }

    public var url: URL? {
        switch self {
        case .guardLog: AnalyzersPaths.guardLog
        case .memoryClean: AnalyzersPaths.memoryAutoCleanLog
        case .reclaim: AnalyzersPaths.reclaimLog
        case .storageClean: AnalyzersPaths.storageAutoCleanLog
        case .janitor: AnalyzersPaths.janitorLog
        case .tempSpace: AnalyzersPaths.tempCleanLog
        case .persistence: AnalyzersPaths.persistenceLog
        case .loginItems: AnalyzersPaths.loginItemsAuditLog
        case .spotlightAudit: AnalyzersPaths.spotlightAuditLog
        case .forensics: AnalyzersPaths.latestForensics()
        }
    }
}
