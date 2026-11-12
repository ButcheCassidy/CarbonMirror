// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCoreBridge

/// A paired or seen phone. Persisted without any plaintext Wi-Fi name: endpoints are keyed by an SSID hash.
public struct Device: Equatable, Sendable, Codable, Identifiable {
    public enum Connection: String, Sendable, Codable { case usb, wireless }

    /// A wireless endpoint last seen on one Wi-Fi network.
    public struct Endpoint: Equatable, Sendable, Codable {
        public var ip: String
        public var port: UInt16

        public init(ip: String, port: UInt16) {
            self.ip = ip
            self.port = port
        }
    }

    /// Pinned identities (spec 7.2): SHA-256 of the adb TLS public key (SubjectPublicKeyInfo) and the serial.
    public struct Pins: Equatable, Sendable, Codable {
        public var adbKeySHA256: String
        public var serial: String

        public init(adbKeySHA256: String, serial: String) {
            self.adbKeySHA256 = adbKeySHA256
            self.serial = serial
        }
    }

    public var id: String { serial }
    public var serial: String
    public var model: String
    public var androidVersion: String
    public var connection: Connection
    public var pins: Pins?
    /// Last known endpoint per Wi-Fi network, keyed by ``ssidKey(_:)``.
    public var lastKnownEndpoints: [String: Endpoint]

    public init(serial: String, model: String, androidVersion: String, connection: Connection, pins: Pins? = nil, lastKnownEndpoints: [String: Endpoint] = [:]) {
        self.serial = serial
        self.model = model
        self.androidVersion = androidVersion
        self.connection = connection
        self.pins = pins
        self.lastKnownEndpoints = lastKnownEndpoints
    }

    /// Storage/log key for a Wi-Fi network: SHA-256 of a domain-separated SSID, never the SSID itself.
    public static func ssidKey(_ ssid: String) throws(CoreStatus) -> String {
        try CoreCrypto.sha256Hex(Array("carbonmirror-ssid-v1:\(ssid)".utf8))
    }

    /// Remembers `endpoint` for the Wi-Fi network `ssid` after checking it against the private-range allowlist.
    public mutating func remember(_ endpoint: Endpoint, onNetwork ssid: String) throws(CoreStatus) {
        try NetPolicy.checkEndpoint(ip: endpoint.ip, port: UInt32(endpoint.port))
        lastKnownEndpoints[try Device.ssidKey(ssid)] = endpoint
    }
}
