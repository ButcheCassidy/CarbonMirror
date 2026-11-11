import CMCore
import CMCoreBridge
import Foundation

/// Storage for CarbonMirror's long-term secrets and pins (the login Keychain on the Mac; in memory in tests).
public protocol KeyStore: AnyObject, Sendable {
    /// The Mac identity key, if one exists.
    func identity() throws -> (any IdentitySigning)?
    /// Creates a new non-extractable P-384 identity key (replacing nothing — delete first).
    func createIdentity() throws -> any IdentitySigning
    func deleteIdentity() throws
    func data(for item: KeyItem) -> [UInt8]?
    func setData(_ data: [UInt8], for item: KeyItem) throws
    func deleteData(for item: KeyItem) throws
}

/// Non-key items CarbonMirror keeps next to the identity key.
public enum KeyItem: String, CaseIterable, Sendable {
    /// Self-signed CA certificate of the identity key (DER), pinned by the phone.
    case identityCertificate = "CarbonMirror identity certificate"
    /// SHA-256 of `adbkey.pub`, to detect a replaced or corrupted adb key.
    case adbKeyFingerprint = "CarbonMirror adb key fingerprint"
    /// The paired phone (JSON `Device`, pins included).
    case pairedDevice = "CarbonMirror paired device"
}

/// Health of the stored keys at launch (spec 7.4/7.5).
public enum KeyHealth: Equatable, Sendable {
    case ok
    /// adb key file and its Keychain fingerprint disagree, or the Keychain item vanished.
    case corrupted
}

/// Owns the Mac identity, the adb key fingerprint and the pins, and runs "Create new key" (spec 7.5).
/// A new key is never trusted for anything until a QR pairing completes.
public final class KeyManager: @unchecked Sendable {
    public static let adbKeyFile = "adbkey"
    public static let adbPublicKeyFile = "adbkey.pub"

    private let store: any KeyStore
    private let adbDirectory: URL
    private let lock = NSLock()

    public init(store: any KeyStore, adbDirectory: URL) {
        self.store = store
        self.adbDirectory = adbDirectory
    }

    private var adbKeyURL: URL { adbDirectory.appendingPathComponent(Self.adbKeyFile) }
    private var adbPublicKeyURL: URL { adbDirectory.appendingPathComponent(Self.adbPublicKeyFile) }

    // MARK: Identity

    /// Identity key and CA certificate, created on first use.
    public func encryption() throws -> Encryption {
        lock.lock()
        defer { lock.unlock() }
        let signer = try store.identity() ?? store.createIdentity()
        if let ca = store.data(for: .identityCertificate) {
            return Encryption(signer: signer, macCA: ca)
        }
        let ca = try InnerTLS.makeIdentityCA(signer: signer)
        try store.setData(ca, for: .identityCertificate)
        return Encryption(signer: signer, macCA: ca)
    }

    // MARK: adb key fingerprint

    private func adbPublicKeyHash() -> [UInt8]? {
        guard let data = FileManager.default.contents(atPath: adbPublicKeyURL.path) else { return nil }
        return try? CoreCrypto.sha256([UInt8](data))
    }

    /// Records the fingerprint of the adb key adb just generated (after the first server start).
    public func recordAdbKey() throws {
        guard let hash = adbPublicKeyHash() else { return }
        if store.data(for: .adbKeyFingerprint) == nil {
            try store.setData(hash, for: .adbKeyFingerprint)
        }
    }

    /// Launch check: a key file whose fingerprint differs from the Keychain copy means tampering or corruption.
    public func checkHealth() -> KeyHealth {
        let stored = store.data(for: .adbKeyFingerprint)
        let current = adbPublicKeyHash()
        switch (stored, current) {
        case (nil, nil): return .ok
        case (nil, .some): return pairedDevice() == nil ? .ok : .corrupted
        case (.some, nil): return .corrupted
        case let (.some(a), .some(b)): return a == b ? .ok : .corrupted
        }
    }

    // MARK: Pins

    public func pairedDevice() -> Device? {
        guard let data = store.data(for: .pairedDevice) else { return nil }
        return try? JSONDecoder().decode(Device.self, from: Data(data))
    }

    /// Pins a phone after a completed pairing (serial + adb TLS key hash).
    public func pin(_ device: Device) throws {
        try store.setData([UInt8](try JSONEncoder().encode(device)), for: .pairedDevice)
    }

    /// May this phone be used? (USB has no adb TLS key: `keyHash` nil.)
    public func verify(serial: String, keyHash: [UInt8]?) throws(CoreStatus) {
        let pinned = pairedDevice().flatMap { d -> (serial: String, keyHash: [UInt8])? in
            guard let p = d.pins, let h = try? CoreCrypto.bytes(fromHex: p.adbKeySHA256) else { return nil }
            return (p.serial, h)
        }
        try TrustPolicy.verify(pinned: pinned, serial: serial, keyHash: keyHash)
    }

    /// "Forget device": pins, endpoints and cached data.
    public func forgetDevice() throws {
        try store.deleteData(for: .pairedDevice)
        Log.info(.security, "device forgotten")
    }

    // MARK: Create new key (spec 7.5.3)

    /// Deletes every key and pin, wipes the adb key files, and makes a new identity. The caller then
    /// restarts adb (which generates a new adb key), calls ``recordAdbKey()`` and starts QR pairing.
    public func createNewKey() throws {
        lock.lock()
        defer { lock.unlock() }
        try store.deleteIdentity()
        for item in KeyItem.allCases { try store.deleteData(for: item) }
        try Self.wipe(adbKeyURL)
        try Self.wipe(adbPublicKeyURL)
        let signer = try store.createIdentity()
        try store.setData(try InnerTLS.makeIdentityCA(signer: signer), for: .identityCertificate)
        Log.info(.security, "key rotated", ["at": "\(Int(Date().timeIntervalSince1970))"])
    }

    /// Overwrites a file with zeros, flushes, then removes it.
    static func wipe(_ url: URL) throws {
        guard let handle = FileHandle(forUpdatingAtPath: url.path) else { return }
        let size = Int(handle.seekToEndOfFile())
        handle.seek(toFileOffset: 0)
        handle.write(Data(count: size))
        handle.synchronizeFile()
        handle.closeFile()
        try FileManager.default.removeItem(at: url)
    }
}
