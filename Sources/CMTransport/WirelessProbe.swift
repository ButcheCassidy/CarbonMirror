import CMCore
import CMCoreBridge
import Foundation

/// What CarbonMirror's own probe of the phone's Wireless-debugging port found (spec 6.1/6.2/7.2).
public enum ProbeResult: Equatable, Sendable {
    /// Android Wireless debugging (TLS); `keyHash` is the SHA-256 of the phone's adb TLS public key.
    case wirelessDebugging(keyHash: [UInt8])
    /// Legacy `adb tcpip` — plaintext, refused.
    case plaintextRefused
    /// No answer over the physical interface.
    case unreachable
    /// The route goes through a VPN tunnel (`utun`) — LAN sharing is off.
    case viaTunnel
    /// The address is not an allowed private-range target.
    case refusedAddress(CoreStatus)
    /// The port answered something that is not adb.
    case notAdb
}

/// Speaks just enough adb to tell Wireless debugging (`STLS`) from plaintext `adb tcpip`, then reads the
/// phone's adb TLS public key and aborts. CarbonMirror never completes a TLS session with adbd; adb does.
public enum WirelessProbe {
    public static let timeout: Duration = .seconds(5)

    /// Runs the probe over an already-connected stream (closed afterwards).
    public static func run(over stream: any ByteStream) async -> ProbeResult {
        defer { stream.close() }
        guard let hello = try? AdbProbe.hello() else { return .notAdb }
        stream.send(hello)
        guard let header = try? await stream.readExactly(AdbProbe.headerLength) else { return .unreachable }
        switch try? AdbProbe.classify(header) {
        case .plaintext?:
            Log.error(.security, "plaintext adb endpoint refused")
            return .plaintextRefused
        case .tlsRequired?:
            break
        case nil:
            return .notAdb
        }
        guard let reply = try? AdbProbe.stlsReply(), let tls = try? TLSSession.capture() else { return .notAdb }
        stream.send(reply)
        do {
            stream.send(try tls.takeOutgoing())
            while true {
                let chunk = try await stream.read(max: 16 * 1024)
                if chunk.isEmpty { break }
                try tls.receive(chunk)
                let out = try tls.takeOutgoing()
                if !out.isEmpty { stream.send(out) }
            }
        } catch {
            if let pin = try? tls.capturedPin() { return .wirelessDebugging(keyHash: pin) }
        }
        if let pin = try? tls.capturedPin() { return .wirelessDebugging(keyHash: pin) }
        return .notAdb
    }

    /// Checks the address against the private-range allowlist before anything is sent.
    public static func check(ip: String, port: UInt16) -> ProbeResult? {
        do {
            try NetPolicy.checkEndpoint(ip: ip, port: UInt32(port))
            return nil
        } catch {
            return error == .portLegacyTcpipRefused ? .plaintextRefused : .refusedAddress(error)
        }
    }
}

#if canImport(Network)
import Network

extension WirelessProbe {
    /// Probes `ip:port` over the physical Wi-Fi (or Ethernet) interface only; a route through `utun`
    /// (Mullvad's tunnel) is reported as `viaTunnel` (spec 6.2 LAN-sharing self-check).
    public static func probe(ip: String, port: UInt16) async -> ProbeResult {
        if let refused = check(ip: ip, port: port) { return refused }
        for interface in [NWInterface.InterfaceType.wifi, .wiredEthernet] {
            switch await NWByteStream.connectLAN(ip: ip, port: port, interface: interface) {
            case let .success((stream, name)):
                if let name, (try? NetPolicy.checkInterface(name)) == nil {
                    stream.close()
                    return .viaTunnel
                }
                return await run(over: stream)
            case .failure:
                continue
            }
        }
        return .unreachable
    }
}

extension NWByteStream {
    /// Connects to a phone on the LAN by IP address over one physical interface type; never through
    /// `.other` (VPN tunnels). Returns the stream and the interface name the route used.
    static func connectLAN(ip: String, port: UInt16, interface: NWInterface.InterfaceType) async -> Result<(NWByteStream, String?), StreamError> {
        guard let nwPort = NWEndpoint.Port(rawValue: port), let address = IPv4Address(ip).map(NWEndpoint.Host.ipv4) ?? IPv6Address(ip).map(NWEndpoint.Host.ipv6) else {
            return .failure(.connectFailed)
        }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = interface
        parameters.prohibitedInterfaceTypes = [.other, .cellular]
        do {
            let stream = try await NWByteStream.connect(endpoint: .hostPort(host: address, port: nwPort), parameters: parameters, timeout: 5)
            return .success((stream, stream.interfaceName))
        } catch {
            return .failure(.connectFailed)
        }
    }
}
#endif
