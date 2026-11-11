import Foundation
import os
import Security

/// Who signed a program: the organisation in the leaf certificate's name, which
/// is what System Settings shows as the developer ("Google LLC", "Zoom Video
/// Communications, Inc."). Read-only, cached per path, and blocking: call it off
/// the main actor.
enum CodeSignature {

    /// What the signature said, and whether it holds.
    enum Result: Sendable, Equatable {
        /// Valid, anchored in Apple or a Developer ID: the organisation is who signed it.
        case verified(String)
        /// A name is there but the signature does not validate (damaged, revoked,
        /// altered, or a certificate Apple never issued): never used as an owner.
        case unverified(String)
        /// Unsigned, ad hoc, or no organisation in the certificate.
        case none
    }

    /// Apple's own anchor, or a Developer ID leaf certificate chaining to Apple.
    private static let requirement = "anchor apple or (anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13])"

    private static let cache = OSAllocatedUnfairLock<[String: Result]>(initialState: [:])

    static func check(ofProgram path: String) -> Result {
        if let hit = cache.withLock({ $0[path] }) { return hit }
        let found = read(path)
        cache.withLock { $0[path] = found }
        return found
    }

    private static func read(_ path: String) -> Result {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return .none }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String?,
              let name = organization(fromCertificateSummary: summary) else { return .none }
        var anchored: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &anchored) == errSecSuccess,
              let anchored,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: 0), anchored) == errSecSuccess
        else { return .unverified(name) }
        return .verified(name)
    }

    /// "Developer ID Application: Google LLC (EQHXZ8M8AV)" is "Google LLC". A
    /// summary that names no organisation (Apple's own "Software Signing", an
    /// ad-hoc signature) names nobody.
    static func organization(fromCertificateSummary summary: String) -> String? {
        guard let colon = summary.range(of: ": ") else { return nil }
        var name = String(summary[colon.upperBound...])
        if name.hasSuffix(")"), let open = name.lastIndex(of: "("),
           name[name.index(after: open)...].dropLast().allSatisfy({ $0.isLetter || $0.isNumber }) {
            name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? nil : name
    }
}
