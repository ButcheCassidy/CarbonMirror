// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import CMCore
import Foundation
import Network
import dnssd

/// mDNS discovery of the phone's adb services (spec 6.2, 7.2): `_adb-tls-connect._tcp` and
/// `_adb-tls-pairing._tcp`. Browsing never touches VPN tunnels; resolving yields an IP address and port
/// without opening any connection, so the private-range allowlist runs before a single packet goes to the phone.
public enum Bonjour {
    public static let connectType = "_adb-tls-connect._tcp"
    public static let pairingType = "_adb-tls-pairing._tcp"

    public struct Service: Equatable, Sendable {
        public let name: String
        public let type: String
        public let domain: String
    }

    /// Services of `type` seen within `duration` (incoming multicast may be blocked by Mullvad: empty then).
    public static func browse(type: String, for duration: Duration) async -> [Service] {
        let parameters = NWParameters()
        parameters.prohibitedInterfaceTypes = [.other, .cellular]
        let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: parameters)
        let found = Found()
        browser.browseResultsChangedHandler = { results, _ in
            found.set(results.compactMap { result in
                guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
                return Service(name: name, type: type, domain: domain)
            })
        }
        browser.start(queue: .global(qos: .userInitiated))
        try? await Task.sleep(for: duration)
        browser.cancel()
        return found.get()
    }

    /// IPv4 address and port of `service`, or nil within `timeout`.
    public static func resolve(_ service: Service, timeout: TimeInterval = 5) async -> (ip: String, port: UInt16)? {
        await withCheckedContinuation { continuation in
            Resolver(service: service, timeout: timeout) { continuation.resume(returning: $0) }.start()
        }
    }

    private final class Found: @unchecked Sendable {
        private let lock = NSLock()
        private var services: [Service] = []
        func set(_ s: [Service]) { lock.withLock { services = s } }
        func get() -> [Service] { lock.withLock { services } }
    }
}

/// One DNSServiceResolve → DNSServiceGetAddrInfo pass on a private serial queue; finishes exactly once.
private final class Resolver: @unchecked Sendable {
    private let service: Bonjour.Service
    private let timeout: TimeInterval
    private let done: (( (ip: String, port: UInt16)? ) -> Void)
    private let queue = DispatchQueue(label: "com.nomadicrebel.carbonmirror.bonjour")
    private var resolveRef: DNSServiceRef?
    private var addressRef: DNSServiceRef?
    private var port: UInt16 = 0
    private var finished = false
    private var retainedSelf: Resolver?

    init(service: Bonjour.Service, timeout: TimeInterval, done: @escaping ((ip: String, port: UInt16)?) -> Void) {
        self.service = service
        self.timeout = timeout
        self.done = done
    }

    func start() {
        queue.async { [self] in
            retainedSelf = self
            let context = Unmanaged.passUnretained(self).toOpaque()
            let status = DNSServiceResolve(&resolveRef, 0, 0, service.name, service.type, service.domain, { _, _, _, error, _, host, port, _, _, ctx in
                guard let ctx else { return }
                let me = Unmanaged<Resolver>.fromOpaque(ctx).takeUnretainedValue()
                guard error == kDNSServiceErr_NoError, let host else { return me.finish(nil) }
                me.resolved(host: String(cString: host), port: UInt16(bigEndian: port))
            }, context)
            guard status == kDNSServiceErr_NoError, let resolveRef else { return finish(nil) }
            DNSServiceSetDispatchQueue(resolveRef, queue)
            queue.asyncAfter(deadline: .now() + timeout) { [self] in finish(nil) }
        }
    }

    private func resolved(host: String, port: UInt16) {
        guard addressRef == nil else { return }
        self.port = port
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = DNSServiceGetAddrInfo(&addressRef, 0, 0, DNSServiceProtocol(kDNSServiceProtocol_IPv4), host, { _, _, _, error, _, address, _, ctx in
            guard let ctx else { return }
            let me = Unmanaged<Resolver>.fromOpaque(ctx).takeUnretainedValue()
            guard error == kDNSServiceErr_NoError, let address, address.pointee.sa_family == sa_family_t(AF_INET) else { return }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var inAddr = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            guard inet_ntop(AF_INET, &inAddr, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { return }
            me.finish((String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), me.port))
        }, context)
        guard status == kDNSServiceErr_NoError, let addressRef else { return finish(nil) }
        DNSServiceSetDispatchQueue(addressRef, queue)
    }

    /// Runs on `queue`.
    private func finish(_ result: (ip: String, port: UInt16)?) {
        guard !finished else { return }
        finished = true
        if let resolveRef { DNSServiceRefDeallocate(resolveRef) }
        if let addressRef { DNSServiceRefDeallocate(addressRef) }
        resolveRef = nil
        addressRef = nil
        done(result)
        retainedSelf = nil
    }
}
#endif
