// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
//! Phase 11 attack target: the phone side of the inner TLS (`Identity::server`, the exact policy the forked
//! server uses through JNI) on a real TCP socket, so foreign clients (`openssl s_client`) can try to
//! downgrade it. Usage: `tls_endpoint <port>`; prints one line per connection: `REFUSED <status>` or
//! `NEGOTIATED <suite> <group>`.

use aws_lc_rs::rand::SystemRandom;
use aws_lc_rs::signature::{ECDSA_P384_SHA384_ASN1_SIGNING, EcdsaKeyPair, KeyPair};
use carbon_core::status::CmStatus;
use carbon_core::tls::{self, Identity, IdentitySigner, Session};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};

/// Software stand-in for the Mac's Keychain identity (only its CA is needed by the phone side).
struct SoftSigner(EcdsaKeyPair);

impl IdentitySigner for SoftSigner {
    fn public_key(&self) -> &[u8] {
        self.0.public_key().as_ref()
    }

    fn sign(&self, message: &[u8]) -> Result<Vec<u8>, CmStatus> {
        Ok(self.0.sign(&SystemRandom::new(), message).map_err(|_| CmStatus::TlsFailed)?.as_ref().to_vec())
    }
}

fn serve(mut socket: TcpStream, identity: &Identity) -> Result<(u16, u16), CmStatus> {
    let mut session = Session::new(identity)?;
    let mut buf = vec![0u8; 64 * 1024];
    loop {
        let n = session.write_tls(&mut buf)?;
        if n > 0 {
            socket.write_all(&buf[..n]).map_err(|_| CmStatus::TlsClosed)?;
        }
        if session.status() & tls::STATUS_HANDSHAKING == 0 && let Ok(negotiated) = session.negotiated() {
            return Ok(negotiated);
        }
        let read = socket.read(&mut buf).map_err(|_| CmStatus::TlsClosed)?;
        if read == 0 {
            return Err(CmStatus::TlsClosed);
        }
        session.read_tls(&buf[..read])?;
    }
}

fn main() {
    let port: u16 = std::env::args().nth(1).and_then(|p| p.parse().ok()).expect("usage: tls_endpoint <port>");
    let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P384_SHA384_ASN1_SIGNING, &SystemRandom::new()).expect("key");
    let signer = SoftSigner(EcdsaKeyPair::from_pkcs8(&ECDSA_P384_SHA384_ASN1_SIGNING, pkcs8.as_ref()).expect("key"));
    let ca = tls::make_identity_ca(&signer).expect("ca");
    let identity = Identity::server(&ca).expect("identity");
    let listener = TcpListener::bind(("127.0.0.1", port)).expect("bind");
    println!("LISTENING {port}");
    for socket in listener.incoming().flatten() {
        match serve(socket, &identity) {
            Ok((suite, group)) => println!("NEGOTIATED {suite:#06x} {group:#06x}"),
            Err(status) => println!("REFUSED {status:?}"),
        }
    }
}
