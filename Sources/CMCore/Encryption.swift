// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCoreBridge

/// What the Mac signs with and the CA certificate the phone pins (spec 7.3/7.4).
public struct Encryption: Sendable {
    public let signer: any IdentitySigning
    public let macCA: [UInt8]

    public init(signer: any IdentitySigning, macCA: [UInt8]) {
        self.signer = signer
        self.macCA = macCA
    }
}
