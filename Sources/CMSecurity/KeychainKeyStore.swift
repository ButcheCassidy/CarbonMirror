// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import CMCore
import CMCoreBridge
import Foundation
import Security

/// Mac identity key in the login Keychain: ECDSA P-384, permanent, non-extractable. Signing happens inside
/// the Keychain (`SecKeyCreateSignature`); the private key never enters app or Rust memory (spec 7.4).
/// Items are created by CarbonMirror, so their access list trusts only CarbonMirror's code signature.
final class KeychainSigner: IdentitySigning, @unchecked Sendable {
    let key: SecKey
    let publicKey: [UInt8]

    init(key: SecKey) throws {
        guard let pub = SecKeyCopyPublicKey(key), let data = SecKeyCopyExternalRepresentation(pub, nil) as Data? else {
            throw KeychainKeyStore.Failure.keyUnavailable
        }
        self.key = key
        publicKey = [UInt8](data)
    }

    func sign(_ message: [UInt8]) throws -> [UInt8] {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA384, Data(message) as CFData, &error) as Data? else {
            throw KeychainKeyStore.Failure.signingFailed
        }
        return [UInt8](sig)
    }
}

/// Login-Keychain storage (file-based keychain: the data-protection keychain and Secure Enclave need an Apple
/// Developer Team ID, which a self-signed certificate does not have — see SECURITY_NOTES.md).
public final class KeychainKeyStore: KeyStore, @unchecked Sendable {
    public enum Failure: Error {
        case keyUnavailable
        case keyCreationFailed
        case signingFailed
        case keychain(OSStatus)
    }

    static let service = "com.nomadicrebel.carbonmirror"
    static let identityTag = Data("com.nomadicrebel.carbonmirror.identity".utf8)
    static let identityLabel = "CarbonMirror identity"

    public init() {}

    public func identity() throws -> (any IdentitySigning)? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Self.identityTag,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecReturnRef: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item, CFGetTypeID(item) == SecKeyGetTypeID() else { throw Failure.keychain(status) }
        return try KeychainSigner(key: item as! SecKey)
    }

    public func createIdentity() throws -> any IdentitySigning {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 384,
            kSecAttrLabel: Self.identityLabel,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrIsExtractable: false,
                kSecAttrApplicationTag: Self.identityTag,
                kSecAttrLabel: Self.identityLabel,
            ] as [CFString: Any],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { throw Failure.keyCreationFailed }
        return try KeychainSigner(key: key)
    }

    public func deleteIdentity() throws {
        let query: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrApplicationTag: Self.identityTag]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }

    private func itemQuery(_ item: KeyItem) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: item.rawValue, kSecAttrSynchronizable: false]
    }

    public func data(for item: KeyItem) -> [UInt8]? {
        var query = itemQuery(item)
        query[kSecReturnData] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return [UInt8](data)
    }

    public func setData(_ data: [UInt8], for item: KeyItem) throws {
        try deleteData(for: item)
        var attributes = itemQuery(item)
        attributes[kSecValueData] = Data(data)
        attributes[kSecAttrLabel] = item.rawValue
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    public func deleteData(for item: KeyItem) throws {
        let status = SecItemDelete(itemQuery(item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }
}
#endif
