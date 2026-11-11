#if os(macOS)
import CMCore
import CryptoKit
import Foundation
import Security

/// Verifies the bundled adb helper's code signature before it is ever run. The helper is re-signed with the
/// same certificate as the app, so it must satisfy: identifier "adb" and the exact leaf certificate CarbonMirror
/// itself is signed with (by hash, never by name). A hash of the file can't be used — re-signing changes it.
public enum HelperSignature {
    public enum Failure: Error, Equatable {
        case ownSignatureUnreadable
        case requirementInvalid
        case helperUnsigned
        case helperRejected(OSStatus)
    }

    /// Code-signing identifier `codesign` gives the re-signed helper (derived from its file name).
    public static let helperIdentifier = "adb"

    /// Throws unless the helper at `url` is validly signed by CarbonMirror's own certificate.
    public static func verify(helperAt url: URL) throws(Failure) {
        let requirement = try makeRequirement()
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            throw .helperUnsigned
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            Log.error(.security, "adb helper signature rejected", ["status": "\(status)"])
            throw .helperRejected(status)
        }
    }

    private static func makeRequirement() throws(Failure) -> SecRequirement {
        let leafHash = try ownLeafCertificateSHA1()
        let text = "identifier \"\(helperIdentifier)\" and certificate leaf = H\"\(leafHash)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let req = requirement else {
            throw .requirementInvalid
        }
        return req
    }

    /// SHA-1 of the app's own leaf signing certificate — the hash form the code-requirement language uses.
    private static func ownLeafCertificateSHA1() throws(Failure) -> String {
        var selfCode: SecCode?
        var staticSelf: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let me = selfCode,
              SecCodeCopyStaticCode(me, [], &staticSelf) == errSecSuccess, let meStatic = staticSelf,
              SecCodeCopySigningInformation(meStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certs.first else {
            throw .ownSignatureUnreadable
        }
        let der = SecCertificateCopyData(leaf) as Data
        return Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined()
    }
}
#endif
