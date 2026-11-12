import CMCore
import CMCoreBridge
import CMSecurity
import Foundation
import Synchronization
import Testing

/// The Keychain stand-in: same contract, memory only.
final class MemoryKeyStore: KeyStore, @unchecked Sendable {
    let state = Mutex<(identity: OpenSSLSigner?, items: [KeyItem: [UInt8]], created: Int)>((nil, [:], 0))

    func identity() throws -> (any IdentitySigning)? { state.withLock { $0.identity } }

    func createIdentity() throws -> any IdentitySigning {
        let s = try OpenSSLSigner()
        state.withLock {
            $0.identity = s
            $0.created += 1
        }
        return s
    }

    func deleteIdentity() throws { state.withLock { $0.identity = nil } }
    func data(for item: KeyItem) -> [UInt8]? { state.withLock { $0.items[item] } }
    func setData(_ data: [UInt8], for item: KeyItem) throws { state.withLock { $0.items[item] = data } }
    func deleteData(for item: KeyItem) throws { _ = state.withLock { $0.items.removeValue(forKey: item) } }
}

@Suite("Keys, pins and Create new key (7.4/7.5)")
struct KeyTests {
    static func setup() throws -> (KeyManager, MemoryKeyStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cm-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("PRIVATE".utf8).write(to: dir.appendingPathComponent("adbkey"))
        try Data("PUBLIC-1".utf8).write(to: dir.appendingPathComponent("adbkey.pub"))
        let store = MemoryKeyStore()
        return (KeyManager(store: store, adbDirectory: dir), store, dir)
    }

    static func pinned(_ manager: KeyManager) throws {
        let hash = String(repeating: "ab", count: 32)
        try manager.pin(Device(serial: "3A091FDJH00ABC", model: "Pixel_10_Pro_XL", androidVersion: "16", connection: .wireless,
                               pins: .init(adbKeySHA256: hash, serial: "3A091FDJH00ABC")))
    }

    @Test func identityAndCertificateAreCreatedOnceAndReused() throws {
        let (manager, store, _) = try Self.setup()
        let a = try manager.encryption()
        let b = try manager.encryption()
        #expect(a.macCA == b.macCA)
        #expect(store.state.withLock { $0.created } == 1)
        #expect(a.signer.publicKey.count == 97)
    }

    @Test func trustRequiresTheExactPin() throws {
        let (manager, _, _) = try Self.setup()
        #expect(throws: CoreStatus.trustNotPaired) { try manager.verify(serial: "3A091FDJH00ABC", keyHash: [UInt8](repeating: 0xAB, count: 32)) }
        try Self.pinned(manager)
        try manager.verify(serial: "3A091FDJH00ABC", keyHash: [UInt8](repeating: 0xAB, count: 32))
        #expect(throws: CoreStatus.trustIdentityChanged) { try manager.verify(serial: "3A091FDJH00ABC", keyHash: [UInt8](repeating: 1, count: 32)) }
        #expect(throws: CoreStatus.trustUnknownDevice) { try manager.verify(serial: "OTHER", keyHash: nil) }
    }

    @Test func createNewKeyRemovesEverythingAndTrustsNothing() throws {
        let (manager, store, dir) = try Self.setup()
        let old = try manager.encryption()
        try manager.recordAdbKey()
        try Self.pinned(manager)
        try manager.createNewKey()
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("adbkey").path), "old adb key wiped")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("adbkey.pub").path))
        #expect(store.data(for: .adbKeyFingerprint) == nil)
        #expect(manager.pairedDevice() == nil, "pins cleared")
        let fresh = try manager.encryption()
        #expect(fresh.signer.publicKey != old.signer.publicKey, "new identity key")
        #expect(fresh.macCA != old.macCA)
        #expect(throws: CoreStatus.trustNotPaired) { try manager.verify(serial: "3A091FDJH00ABC", keyHash: [UInt8](repeating: 0xAB, count: 32)) }
    }

    @Test func deviceKeyBelongsToOnePhoneAndGoesWithIt() throws {
        let (manager, _, _) = try Self.setup()
        let key = try CoreCrypto.randomBytes(32)
        #expect(manager.deviceKey(serial: "3A091FDJH00ABC") == nil)
        try manager.storeDeviceKey(key, serial: "3A091FDJH00ABC")
        #expect(manager.deviceKey(serial: "3A091FDJH00ABC") == key)
        #expect(manager.deviceKey(serial: "OTHER") == nil, "another phone never inherits the key")
        #expect(throws: CoreStatus.invalidArgument) { try manager.storeDeviceKey([1, 2, 3], serial: "3A091FDJH00ABC") }
        try manager.forgetDevice()
        #expect(manager.deviceKey(serial: "3A091FDJH00ABC") == nil, "Forget device removes it")
        try manager.storeDeviceKey(key, serial: "3A091FDJH00ABC")
        try manager.createNewKey()
        #expect(manager.deviceKey(serial: "3A091FDJH00ABC") == nil, "Create new key removes it")
    }

    @Test func tamperedAdbKeyIsDetected() throws {
        let (manager, store, dir) = try Self.setup()
        try manager.recordAdbKey()
        #expect(manager.checkHealth() == .ok)
        try Data("PUBLIC-2".utf8).write(to: dir.appendingPathComponent("adbkey.pub"))
        #expect(manager.checkHealth() == .corrupted)
        try Data("PUBLIC-1".utf8).write(to: dir.appendingPathComponent("adbkey.pub"))
        try store.deleteData(for: .adbKeyFingerprint)
        try Self.pinned(manager)
        #expect(manager.checkHealth() == .corrupted, "Keychain fingerprint lost while paired")
    }

    @Test func pairingCodesAreSingleUseAndExpire() throws {
        let code = try PairingCode(now: 1000)
        #expect(code.qrPayload == "WIFI:T:ADB;S:\(code.serviceName);P:\(code.password);;")
        #expect(code.password.count >= 22)
        #expect(throws: CoreStatus.pairingCodeExpired) { try code.consume(now: 1120) }
        try code.consume(now: 1100)
        #expect(throws: CoreStatus.pairingCodeUsed) { try code.consume(now: 1101) }
    }
}
