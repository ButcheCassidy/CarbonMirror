import CarbonCoreC

/// SHA-256, constant-time verification and CSPRNG bytes (aws-lc via the Rust core; same code on the phone).
public enum CoreCrypto {
    /// SHA-256 of `data`.
    public static func sha256(_ data: [UInt8]) throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: Int(SHA256_LEN))
        let code = data.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { cm_sha256(src.baseAddress, src.count, $0.baseAddress) }
        }
        try check(code)
        return out
    }

    /// Lower-case hex SHA-256 of `data`.
    public static func sha256Hex(_ data: [UInt8]) throws(CoreStatus) -> String {
        hex(try sha256(data))
    }

    /// Lower-case hex of `bytes`.
    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let s = String(byte, radix: 16)
            return s.count == 1 ? "0" + s : s
        }.joined()
    }

    /// Throws `digestMismatch` unless `data` hashes to `expected` (constant-time compare).
    public static func verifySHA256(_ data: [UInt8], expected: [UInt8]) throws(CoreStatus) {
        let code = data.withUnsafeBufferPointer { d in
            expected.withUnsafeBufferPointer { e in cm_sha256_verify(d.baseAddress, d.count, e.baseAddress, e.count) }
        }
        try check(code)
    }

    /// HMAC-SHA-256 of `data` under `key`.
    public static func hmacSHA256(key: [UInt8], _ data: [UInt8]) throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: Int(SHA256_LEN))
        let code = key.withUnsafeBufferPointer { k in
            data.withUnsafeBufferPointer { d in
                out.withUnsafeMutableBufferPointer { cm_hmac_sha256(k.baseAddress, k.count, d.baseAddress, d.count, $0.baseAddress) }
            }
        }
        try check(code)
        return out
    }

    /// Throws `digestMismatch` unless `tag` is the HMAC-SHA-256 of `data` under `key` (constant-time compare).
    public static func verifyHMACSHA256(key: [UInt8], _ data: [UInt8], tag: [UInt8]) throws(CoreStatus) {
        let code = key.withUnsafeBufferPointer { k in
            data.withUnsafeBufferPointer { d in
                tag.withUnsafeBufferPointer { t in cm_hmac_sha256_verify(k.baseAddress, k.count, d.baseAddress, d.count, t.baseAddress, t.count) }
            }
        }
        try check(code)
    }

    /// Parses 64 hex characters into 32 bytes.
    public static func bytes(fromHex hex: String) throws(CoreStatus) -> [UInt8] {
        let chars = Array(hex.utf8)
        guard chars.count == Int(SHA256_LEN) * 2 else { throw CoreStatus.invalidArgument }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { throw CoreStatus.invalidArgument }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): c - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// `count` bytes from the operating system's CSPRNG.
    public static func randomBytes(_ count: Int) throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        try check(out.withUnsafeMutableBufferPointer { cm_random($0.baseAddress, $0.count) })
        return out
    }

    /// Uniform random integer in `range` (rejection sampling, no modulo bias).
    public static func randomInt(in range: ClosedRange<UInt32>) throws(CoreStatus) -> UInt32 {
        let span = UInt64(range.upperBound - range.lowerBound) + 1
        let limit = (UInt64(1) << 32) / span * span
        while true {
            let b = try randomBytes(4)
            let v = UInt64(b[0]) | UInt64(b[1]) << 8 | UInt64(b[2]) << 16 | UInt64(b[3]) << 24
            if v < limit { return range.lowerBound + UInt32(v % span) }
        }
    }
}
