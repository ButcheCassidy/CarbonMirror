import CarbonCoreC

/// What the phone's port answered to the adb probe.
public enum AdbProbeAnswer: UInt32, Sendable {
    /// Android Wireless debugging (TLS required) — allowed.
    case tlsRequired = 1
    /// Legacy `adb tcpip` plaintext — refused.
    case plaintext = 2
}

/// adb wire probe packets and classification (spec 6.1).
public enum AdbProbe {
    public static let headerLength = Int(HEADER_LEN)

    private static func packet(_ f: (UnsafeMutablePointer<UInt8>?, Int, UnsafeMutablePointer<Int>) -> Int32) throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 64)
        var n = 0
        let code = out.withUnsafeMutableBufferPointer { f($0.baseAddress, $0.count, &n) }
        try check(code)
        return Array(out[0..<n])
    }

    public static func hello() throws(CoreStatus) -> [UInt8] { try packet(cm_adb_probe_hello) }
    public static func stlsReply() throws(CoreStatus) -> [UInt8] { try packet(cm_adb_probe_stls) }

    public static func classify(_ header: [UInt8]) throws(CoreStatus) -> AdbProbeAnswer {
        var raw: UInt32 = 0
        try check(header.withUnsafeBufferPointer { cm_adb_probe_classify($0.baseAddress, $0.count, &raw) })
        guard let answer = AdbProbeAnswer(rawValue: raw) else { throw CoreStatus.adbProbeMalformed }
        return answer
    }
}

/// A single-use QR pairing code that expires 120 s after creation (spec 7.2).
public final class PairingCode {
    private let handle: OpaquePointer

    public init(now: UInt64) throws(CoreStatus) {
        var h: OpaquePointer?
        try check(cm_pairing_new(now, &h))
        guard let h else { throw CoreStatus.nullPointer }
        handle = h
    }

    deinit {
        cm_pairing_free(handle)
    }

    private func field(_ which: UInt32) -> String {
        var out = [UInt8](repeating: 0, count: 128)
        var len = 0
        let code = out.withUnsafeMutableBufferPointer { cm_pairing_field(handle, which, $0.baseAddress, $0.count, &len) }
        return code == CoreStatus.ok.rawValue ? String(decoding: out[0..<len], as: UTF8.self) : ""
    }

    /// `WIFI:T:ADB;S:<service>;P:<password>;;`
    public var qrPayload: String { field(0) }
    public var serviceName: String { field(1) }
    public var password: String { field(2) }

    /// Uses the code; throws `pairingCodeUsed` / `pairingCodeExpired`.
    public func consume(now: UInt64) throws(CoreStatus) {
        try check(cm_pairing_consume(handle, now))
    }
}

/// Pin check for the single paired phone (spec 7.2 / 7.5).
public enum TrustPolicy {
    /// `pinned` nil = nothing paired; `keyHash` nil = USB (no adb TLS key to compare).
    public static func verify(pinned: (serial: String, keyHash: [UInt8])?, serial: String, keyHash: [UInt8]?) throws(CoreStatus) {
        let ps = Array((pinned?.serial ?? "").utf8), ph = pinned?.keyHash ?? [], s = Array(serial.utf8), kh = keyHash ?? []
        let code = ps.withUnsafeBufferPointer { psb in
            ph.withUnsafeBufferPointer { phb in
                s.withUnsafeBufferPointer { sb in
                    kh.withUnsafeBufferPointer { khb in
                        cm_trust_check(psb.baseAddress, psb.count, phb.baseAddress, phb.count, sb.baseAddress, sb.count, khb.baseAddress, khb.count)
                    }
                }
            }
        }
        try check(code)
    }
}

/// Signs with the Mac identity key (Keychain on the Mac; a software key in tests).
public protocol IdentitySigning: AnyObject, Sendable {
    /// Uncompressed P-384 public point (97 bytes).
    var publicKey: [UInt8] { get }
    /// DER ECDSA-SHA384 signature of `message`.
    func sign(_ message: [UInt8]) throws -> [UInt8]
}

/// C callback that forwards to the `IdentitySigning` passed as context.
private let signCallback: CmSignCallback = { ctx, msg, msgLen, out, outCap, outLen in
    guard let ctx, let out, let outLen else { return CoreStatus.nullPointer.rawValue }
    let signer = Unmanaged<AnyObject>.fromOpaque(ctx).takeUnretainedValue() as? IdentitySigning
    let message = msg.map { Array(UnsafeBufferPointer(start: $0, count: msgLen)) } ?? []
    guard let signer, let signature = try? signer.sign(message), signature.count <= outCap else {
        return CoreStatus.tlsFailed.rawValue
    }
    signature.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: $0.count) }
    outLen.pointee = signature.count
    return CoreStatus.ok.rawValue
}

private func withSigner<R>(_ signer: IdentitySigning, _ body: (UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer) -> R) -> R {
    let key = signer.publicKey
    let ctx = Unmanaged.passRetained(signer as AnyObject)
    defer { ctx.release() }
    return key.withUnsafeBufferPointer { body($0.baseAddress, $0.count, ctx.toOpaque()) }
}

/// Inner TLS identities and sessions (spec 7.3).
public enum InnerTLS {
    public static let pinLength = 32
    /// IANA ids of the allowed suites / groups (for the debug HUD).
    public static let suiteAES256GCM: UInt16 = 0x1302
    public static let suiteChaCha20: UInt16 = 0x1303
    public static let groupX25519MLKEM768: UInt16 = 0x11EC
    public static let groupX25519: UInt16 = 0x001D

    /// Self-signed CA certificate for the identity key (DER); made once per key and pinned by the phone.
    public static func makeIdentityCA(signer: IdentitySigning) throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 2048)
        var len = 0
        let code = withSigner(signer) { pk, pkLen, ctx in
            out.withUnsafeMutableBufferPointer { cm_tls_make_identity_ca(pk, pkLen, signCallback, ctx, $0.baseAddress, $0.count, &len) }
        }
        try check(code)
        return Array(out[0..<len])
    }

    public static func describe(suite: UInt16) -> String {
        switch suite {
        case suiteAES256GCM: "TLS_AES_256_GCM_SHA384"
        case suiteChaCha20: "TLS_CHACHA20_POLY1305_SHA256"
        default: "unknown"
        }
    }

    public static func describe(group: UInt16) -> String {
        switch group {
        case groupX25519MLKEM768: "X25519MLKEM768"
        case groupX25519: "X25519"
        default: "unknown"
        }
    }
}

/// One side's TLS configuration.
public final class TLSIdentity: @unchecked Sendable {
    let handle: OpaquePointer

    private init(_ handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        cm_tls_identity_free(handle)
    }

    /// Mac: fresh client certificate signed by the identity key, pinning the phone's session key hash.
    public static func client(signer: IdentitySigning, phonePin: [UInt8]) throws(CoreStatus) -> TLSIdentity {
        guard phonePin.count == InnerTLS.pinLength else { throw CoreStatus.invalidArgument }
        var h: OpaquePointer?
        let code = withSigner(signer) { pk, pkLen, ctx in
            phonePin.withUnsafeBufferPointer { cm_tls_client_identity_new(pk, pkLen, signCallback, ctx, $0.baseAddress, &h) }
        }
        try check(code)
        guard let h else { throw CoreStatus.nullPointer }
        return TLSIdentity(h)
    }

    /// Phone side (used by the virtual phone in tests): trusts only `macCA`.
    public static func server(macCA: [UInt8]) throws(CoreStatus) -> TLSIdentity {
        var h: OpaquePointer?
        try check(macCA.withUnsafeBufferPointer { cm_tls_server_identity_new($0.baseAddress, $0.count, &h) })
        guard let h else { throw CoreStatus.nullPointer }
        return TLSIdentity(h)
    }

    /// Public-key hash the Mac pins (server identities only).
    public func pin() throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: InnerTLS.pinLength)
        try check(out.withUnsafeMutableBufferPointer { cm_tls_identity_pin(handle, $0.baseAddress) })
        return out
    }
}

/// One TLS connection over a caller-owned byte stream. Not thread-safe: confine to one actor.
public final class TLSSession: @unchecked Sendable {
    private let handle: OpaquePointer
    private var scratch = [UInt8](repeating: 0, count: 64 * 1024)

    private init(_ handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        cm_tls_session_free(handle)
    }

    public convenience init(identity: TLSIdentity) throws(CoreStatus) {
        var h: OpaquePointer?
        try check(cm_tls_session_new(identity.handle, &h))
        guard let h else { throw CoreStatus.nullPointer }
        self.init(h)
    }

    /// Capture-only session for the adb TLS key probe.
    public static func capture() throws(CoreStatus) -> TLSSession {
        var h: OpaquePointer?
        try check(cm_tls_capture_new(&h))
        guard let h else { throw CoreStatus.nullPointer }
        return TLSSession(h)
    }

    public var isHandshaking: Bool {
        var flags: UInt32 = 0
        _ = cm_tls_status(handle, &flags)
        return flags & UInt32(STATUS_HANDSHAKING) != 0
    }

    public var wantsWrite: Bool {
        var flags: UInt32 = 0
        _ = cm_tls_status(handle, &flags)
        return flags & UInt32(STATUS_WANTS_WRITE) != 0
    }

    /// Feeds ciphertext from the socket.
    public func receive(_ ciphertext: UnsafeRawBufferPointer) throws(CoreStatus) {
        try check(cm_tls_read_tls(handle, ciphertext.bindMemory(to: UInt8.self).baseAddress, ciphertext.count))
    }

    /// Feeds ciphertext from the socket.
    public func receive(_ ciphertext: [UInt8]) throws(CoreStatus) {
        try check(ciphertext.withUnsafeBufferPointer { cm_tls_read_tls(handle, $0.baseAddress, $0.count) })
    }

    /// All ciphertext waiting to be sent.
    public func takeOutgoing() throws(CoreStatus) -> [UInt8] {
        var result: [UInt8] = []
        while wantsWrite {
            var n = 0
            try check(scratch.withUnsafeMutableBufferPointer { cm_tls_write_tls(handle, $0.baseAddress, $0.count, &n) })
            if n == 0 { break }
            result.append(contentsOf: scratch[0..<n])
        }
        return result
    }

    /// Decrypted data, empty when none is pending; throws `tlsClosed` when the peer closed.
    public func takePlaintext() throws(CoreStatus) -> [UInt8] {
        var result: [UInt8] = []
        while true {
            var n = 0
            try check(scratch.withUnsafeMutableBufferPointer { cm_tls_read_plain(handle, $0.baseAddress, $0.count, &n) })
            if n == 0 { return result }
            result.append(contentsOf: scratch[0..<n])
        }
    }

    /// Queues data for encryption (call ``takeOutgoing()`` to get the ciphertext).
    public func send(_ plaintext: [UInt8]) throws(CoreStatus) {
        var offset = 0
        while offset < plaintext.count {
            var consumed = 0
            let code = plaintext.withUnsafeBufferPointer {
                cm_tls_write_plain(handle, $0.baseAddress! + offset, $0.count - offset, &consumed)
            }
            try check(code)
            if consumed == 0 { throw CoreStatus.bufferTooSmall }
            offset += consumed
        }
    }

    /// Negotiated suite and group (IANA ids).
    public func negotiated() throws(CoreStatus) -> (suite: UInt16, group: UInt16) {
        var suite: UInt16 = 0, group: UInt16 = 0
        try check(cm_tls_negotiated(handle, &suite, &group))
        return (suite, group)
    }

    /// Public-key hash recorded by a capture session.
    public func capturedPin() throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: InnerTLS.pinLength)
        try check(out.withUnsafeMutableBufferPointer { cm_tls_captured_pin(handle, $0.baseAddress) })
        return out
    }

    /// Queues close_notify.
    public func close() {
        _ = cm_tls_close(handle)
    }
}
