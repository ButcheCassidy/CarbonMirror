//! Inner TLS end to end in memory: Mac client ↔ phone server with the real policy.

use aws_lc_rs::rand::SystemRandom;
use aws_lc_rs::signature::{ECDSA_P384_SHA384_ASN1_SIGNING, EcdsaKeyPair, KeyPair};
use carbon_core::status::CmStatus;
use carbon_core::tls::{self, Identity, IdentitySigner, Session};

/// Software stand-in for the Keychain identity key.
struct SoftSigner {
    key: EcdsaKeyPair,
}

impl SoftSigner {
    fn new() -> Self {
        let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P384_SHA384_ASN1_SIGNING, &SystemRandom::new()).unwrap();
        Self { key: EcdsaKeyPair::from_pkcs8(&ECDSA_P384_SHA384_ASN1_SIGNING, pkcs8.as_ref()).unwrap() }
    }
}

impl IdentitySigner for SoftSigner {
    fn public_key(&self) -> &[u8] {
        self.key.public_key().as_ref()
    }

    fn sign(&self, message: &[u8]) -> Result<Vec<u8>, CmStatus> {
        Ok(self.key.sign(&SystemRandom::new(), message).map_err(|_| CmStatus::TlsFailed)?.as_ref().to_vec())
    }
}

/// Moves bytes both ways until neither side has anything to send; returns the first error.
fn pump(a: &mut Session, b: &mut Session) -> Result<(), CmStatus> {
    let mut buf = vec![0u8; 64 * 1024];
    for _ in 0..32 {
        let n = a.write_tls(&mut buf)?;
        if n > 0 {
            b.read_tls(&buf[..n])?;
        }
        let m = b.write_tls(&mut buf)?;
        if m > 0 {
            a.read_tls(&buf[..m])?;
        }
        if n == 0 && m == 0 {
            return Ok(());
        }
    }
    Ok(())
}

fn pair() -> (SoftSigner, Vec<u8>, Identity) {
    let mac = SoftSigner::new();
    let ca = tls::make_identity_ca(&mac).unwrap();
    let server = Identity::server(&ca).unwrap();
    (mac, ca, server)
}

#[test]
fn handshake_negotiates_tls13_aes256_and_hybrid_pq() {
    let (mac, _, server_id) = pair();
    let pin = server_id.spki_hash().unwrap();
    let client_id = Identity::client(&mac, &pin).unwrap();
    let mut c = Session::new(&client_id).unwrap();
    let mut s = Session::new(&server_id).unwrap();
    pump(&mut c, &mut s).unwrap();
    assert_eq!(c.status() & tls::STATUS_HANDSHAKING, 0);
    assert_eq!(s.status() & tls::STATUS_HANDSHAKING, 0);
    assert_eq!(c.negotiated().unwrap(), (0x1302, 0x11EC), "TLS_AES_256_GCM_SHA384 + X25519MLKEM768");
    assert_eq!(s.negotiated().unwrap(), (0x1302, 0x11EC));

    c.write_plain(b"session-secret").unwrap();
    s.write_plain(b"video").unwrap();
    pump(&mut c, &mut s).unwrap();
    let mut out = [0u8; 64];
    assert_eq!(s.read_plain(&mut out).unwrap(), 14);
    assert_eq!(&out[..14], b"session-secret");
    assert_eq!(c.read_plain(&mut out).unwrap(), 5);
    assert_eq!(c.read_plain(&mut out).unwrap(), 0, "nothing pending reads as 0");

    c.close();
    pump(&mut c, &mut s).unwrap();
    assert_eq!(s.read_plain(&mut out), Err(CmStatus::TlsClosed));
}

#[test]
fn wrong_phone_pin_is_refused() {
    let (mac, _, server_id) = pair();
    let client_id = Identity::client(&mac, &[0u8; 32]).unwrap();
    let mut c = Session::new(&client_id).unwrap();
    let mut s = Session::new(&server_id).unwrap();
    assert_eq!(pump(&mut c, &mut s), Err(CmStatus::TlsPinMismatch));
}

#[test]
fn mac_certificate_from_another_identity_is_refused() {
    let (_, _, server_id) = pair();
    let intruder = SoftSigner::new();
    let client_id = Identity::client(&intruder, &server_id.spki_hash().unwrap()).unwrap();
    let mut c = Session::new(&client_id).unwrap();
    let mut s = Session::new(&server_id).unwrap();
    let result = pump(&mut c, &mut s);
    assert!(matches!(result, Err(CmStatus::TlsPinMismatch | CmStatus::TlsHandshakeFailed)), "{result:?}");
    assert_ne!(s.status() & tls::STATUS_HANDSHAKING, 0, "server never completes with an unknown Mac");
}

#[test]
fn capture_records_peer_key_and_aborts() {
    let (_, _, server_id) = pair();
    let mut c = Session::capture().unwrap();
    let mut s = Session::new(&server_id).unwrap();
    assert!(pump(&mut c, &mut s).is_err());
    assert_eq!(c.captured(), server_id.spki_hash());
    assert_eq!(c.write_plain(b"x"), Err(CmStatus::InvalidArgument));
}

#[test]
fn garbage_and_plaintext_are_refused() {
    let (_, _, server_id) = pair();
    let mut s = Session::new(&server_id).unwrap();
    assert!(s.read_tls(b"GET / HTTP/1.1\r\n\r\n").is_err());
    let mut s = Session::new(&server_id).unwrap();
    assert!(s.read_tls(&[0x16, 0x03, 0x01, 0xff, 0xff]).is_err(), "oversized record length is refused");
    let mut s = Session::new(&server_id).unwrap();
    assert!(s.read_tls(&[0x16, 0x03, 0x01, 0x00, 0x40]).is_ok(), "partial record waits for more data");
}

/// Like `pump`, but also records every byte the client sends (an eavesdropper's view of one direction).
fn pump_recording(c: &mut Session, s: &mut Session, sent: &mut Vec<u8>) -> Result<(), CmStatus> {
    let mut buf = vec![0u8; 64 * 1024];
    for _ in 0..32 {
        let n = c.write_tls(&mut buf)?;
        sent.extend_from_slice(&buf[..n]);
        if n > 0 {
            s.read_tls(&buf[..n])?;
        }
        let m = s.write_tls(&mut buf)?;
        if m > 0 {
            c.read_tls(&buf[..m])?;
        }
        if n == 0 && m == 0 {
            return Ok(());
        }
    }
    Ok(())
}

/// Phase 11 Stage 3.9: replaying a recorded client (handshake plus encrypted data) into a fresh phone-side
/// session never yields a session or any plaintext — every handshake is fresh (no resumption, no 0-RTT).
#[test]
fn replayed_session_is_refused() {
    let (mac, _, server_id) = pair();
    let client_id = Identity::client(&mac, &server_id.spki_hash().unwrap()).unwrap();
    let mut c = Session::new(&client_id).unwrap();
    let mut s = Session::new(&server_id).unwrap();
    let mut recorded = Vec::new();
    pump_recording(&mut c, &mut s, &mut recorded).unwrap();
    c.write_plain(b"0123456789abcdef0123456789abcdef").unwrap();
    pump_recording(&mut c, &mut s, &mut recorded).unwrap();

    let mut victim = Session::new(&server_id).unwrap();
    let mut sink = vec![0u8; 64 * 1024];
    let replay = victim.read_tls(&recorded).and_then(|_| victim.write_tls(&mut sink));
    assert!(replay.is_err(), "replayed handshake must fail: {replay:?}");
    assert_ne!(victim.status() & tls::STATUS_HANDSHAKING, 0, "replayed handshake never completes");
    let mut out = [0u8; 64];
    assert!(victim.read_plain(&mut out).map(|n| n == 0).unwrap_or(true), "no replayed plaintext is ever delivered");
}

/// A record delivered twice inside a live session (sequence-number replay) ends the session.
#[test]
fn replayed_record_ends_the_session() {
    let (mac, _, server_id) = pair();
    let client_id = Identity::client(&mac, &server_id.spki_hash().unwrap()).unwrap();
    let mut c = Session::new(&client_id).unwrap();
    let mut s = Session::new(&server_id).unwrap();
    pump(&mut c, &mut s).unwrap();
    c.write_plain(b"tap 100 200").unwrap();
    let mut buf = vec![0u8; 4096];
    let n = c.write_tls(&mut buf).unwrap();
    s.read_tls(&buf[..n]).unwrap();
    let mut out = [0u8; 64];
    assert_eq!(s.read_plain(&mut out).unwrap(), 11);
    let replay = s.read_tls(&buf[..n]);
    assert!(replay.is_err(), "duplicate record is a decrypt error: {replay:?}");
}

/// A flipped bit anywhere in an encrypted record ends the session (AEAD).
#[test]
fn tampered_record_ends_the_session() {
    let (mac, _, server_id) = pair();
    let client_id = Identity::client(&mac, &server_id.spki_hash().unwrap()).unwrap();
    let mut c = Session::new(&client_id).unwrap();
    let mut s = Session::new(&server_id).unwrap();
    pump(&mut c, &mut s).unwrap();
    c.write_plain(b"secret text").unwrap();
    let mut buf = vec![0u8; 4096];
    let n = c.write_tls(&mut buf).unwrap();
    buf[n - 3] ^= 0x01;
    let tampered = s.read_tls(&buf[..n]);
    assert!(tampered.is_err(), "{tampered:?}");
}
