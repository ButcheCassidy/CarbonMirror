//! Inner TLS (spec 7.3), the same code on the Mac and on the phone. rustls only runs the TLS state machine
//! over bytes; sockets stay in Swift (Network.framework) and Java.
//!
//! Policy: TLS 1.3 only (rustls is built without TLS 1.2), cipher suites `TLS_AES_256_GCM_SHA384` then
//! `TLS_CHACHA20_POLY1305_SHA256`, key exchange `X25519MLKEM768` then `X25519`, ALPN `carbonmirror/1`
//! required, mutual authentication with pinned keys only (no CA store, no host names), no session
//! resumption, no 0-RTT, traffic keys refreshed every 15 minutes or 4 GiB, 10 s handshake timeout.
//!
//! Keys: the Mac's long-term identity is a P-384 key that never leaves the Keychain; it signs a self-made
//! CA certificate once and, per session, a fresh Ed25519 client certificate (signing happens in Swift via
//! [`IdentitySigner`]). The phone makes a fresh Ed25519 server certificate per server start; its public-key
//! hash travels over the authenticated adb channel and is pinned by the Mac for that session.
#![forbid(unsafe_code)]

use std::io::{self, Read, Write};

use zeroize::Zeroize;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use rcgen::{BasicConstraints, CertificateParams, DnType, ExtendedKeyUsagePurpose, IsCa, Issuer, KeyPair, KeyUsagePurpose};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::client::Resumption;
use rustls::crypto::{aws_lc_rs, verify_tls13_signature, CryptoProvider, WebPkiSupportedAlgorithms};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName, UnixTime};
use rustls::server::{NoServerSessionStorage, WebPkiClientVerifier};
use rustls::{ClientConfig, ClientConnection, Connection, DigitallySignedStruct, RootCertStore, ServerConfig, ServerConnection, SignatureScheme};
use zeroize::Zeroizing;

use crate::crypto;
use crate::status::{CmResult, CmStatus};

/// Required ALPN protocol.
pub const ALPN: &[u8] = b"carbonmirror/1";
pub const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
pub const KEY_UPDATE_INTERVAL: Duration = Duration::from_secs(15 * 60);
pub const KEY_UPDATE_BYTES: u64 = 4 * 1024 * 1024 * 1024;
/// Plaintext buffered inside rustls before `write_plain` pushes back.
/// Largest backlog of decrypted, unread data (above the 8 MiB video packet cap plus headroom).
const PLAIN_LIMIT: usize = 16 << 20;
const BUFFER_LIMIT: usize = 4 * 1024 * 1024;
/// Session certificates are valid from one hour ago (clock skew) for one day.
const SESSION_CERT_BACKDATE: time::Duration = time::Duration::hours(1);
const SESSION_CERT_LIFETIME: time::Duration = time::Duration::hours(24);
const PIN_LEN: usize = crypto::SHA256_LEN;

/// TLS status flags returned by [`Session::status`].
pub const STATUS_HANDSHAKING: u32 = 1;
pub const STATUS_WANTS_WRITE: u32 = 1 << 1;

/// Signs with the Mac identity key (Keychain, P-384, `ecdsaSignatureMessageX962SHA384`, DER signature).
pub trait IdentitySigner {
    /// Uncompressed SEC1 public point (97 bytes).
    fn public_key(&self) -> &[u8];
    fn sign(&self, message: &[u8]) -> CmResult<Vec<u8>>;
}

struct SignerAdapter<'a>(&'a dyn IdentitySigner);

impl rcgen::PublicKeyData for SignerAdapter<'_> {
    fn der_bytes(&self) -> &[u8] {
        self.0.public_key()
    }

    fn algorithm(&self) -> &'static rcgen::SignatureAlgorithm {
        &rcgen::PKCS_ECDSA_P384_SHA384
    }
}

impl rcgen::SigningKey for SignerAdapter<'_> {
    fn sign(&self, msg: &[u8]) -> Result<Vec<u8>, rcgen::Error> {
        self.0.sign(msg).map_err(|_| rcgen::Error::RemoteKeyError)
    }
}

/// The only algorithms CarbonMirror negotiates.
pub fn provider() -> CryptoProvider {
    CryptoProvider {
        cipher_suites: vec![
            aws_lc_rs::cipher_suite::TLS13_AES_256_GCM_SHA384,
            aws_lc_rs::cipher_suite::TLS13_CHACHA20_POLY1305_SHA256,
        ],
        kx_groups: vec![aws_lc_rs::kx_group::X25519MLKEM768, aws_lc_rs::kx_group::X25519],
        ..aws_lc_rs::default_provider()
    }
}

fn tls_err(_: rustls::Error) -> CmStatus {
    CmStatus::TlsHandshakeFailed
}

fn cert_err(_: rcgen::Error) -> CmStatus {
    CmStatus::TlsHandshakeFailed
}

/// SHA-256 of a certificate's SubjectPublicKeyInfo — the pin format used everywhere.
pub fn spki_hash(cert: &[u8]) -> CmResult<[u8; PIN_LEN]> {
    let der = CertificateDer::from(cert);
    let ee = webpki::EndEntityCert::try_from(&der).map_err(|_| CmStatus::ParseMalformed)?;
    Ok(crypto::sha256(ee.subject_public_key_info().as_ref()))
}

fn ca_params() -> CmResult<CertificateParams> {
    let mut p = CertificateParams::new(Vec::<String>::new()).map_err(cert_err)?;
    p.distinguished_name.push(DnType::CommonName, "CarbonMirror Mac identity");
    p.is_ca = IsCa::Ca(BasicConstraints::Constrained(0));
    p.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::DigitalSignature];
    Ok(p)
}

fn session_params(common_name: &str, purpose: ExtendedKeyUsagePurpose) -> CmResult<CertificateParams> {
    let mut p = CertificateParams::new(Vec::<String>::new()).map_err(cert_err)?;
    p.distinguished_name.push(DnType::CommonName, common_name);
    p.key_usages = vec![KeyUsagePurpose::DigitalSignature];
    p.extended_key_usages = vec![purpose];
    let now = time::OffsetDateTime::now_utc();
    p.not_before = now - SESSION_CERT_BACKDATE;
    p.not_after = now + SESSION_CERT_LIFETIME;
    Ok(p)
}

/// Self-signed CA certificate for the Mac identity key; made once per key and pinned by the phone.
pub fn make_identity_ca(signer: &dyn IdentitySigner) -> CmResult<Vec<u8>> {
    let key = SignerAdapter(signer);
    Ok(ca_params()?.self_signed(&key).map_err(cert_err)?.der().to_vec())
}

/// Fresh Ed25519 key; the PKCS#8 bytes are wiped when the returned value is dropped.
fn ephemeral_key() -> CmResult<(KeyPair, Zeroizing<Vec<u8>>)> {
    let key = KeyPair::generate_for(&rcgen::PKCS_ED25519).map_err(cert_err)?;
    let der = Zeroizing::new(key.serialize_der());
    Ok((key, der))
}

fn private_key(der: &Zeroizing<Vec<u8>>) -> PrivateKeyDer<'static> {
    PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(der.to_vec()))
}

/// Mac side: verifies the phone's session certificate by its pinned public-key hash only.
#[derive(Debug)]
struct PinnedServerVerifier {
    pin: [u8; PIN_LEN],
    algorithms: WebPkiSupportedAlgorithms,
}

impl ServerCertVerifier for PinnedServerVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        let hash = spki_hash(end_entity).map_err(|_| rustls::Error::InvalidCertificate(rustls::CertificateError::BadEncoding))?;
        if !intermediates.is_empty() || !crypto::constant_time_eq(&hash, &self.pin) {
            return Err(rustls::Error::InvalidCertificate(rustls::CertificateError::ApplicationVerificationFailure));
        }
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(&self, _: &[u8], _: &CertificateDer<'_>, _: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        Err(rustls::Error::General("TLS 1.2 is not allowed".into()))
    }

    fn verify_tls13_signature(&self, message: &[u8], cert: &CertificateDer<'_>, dss: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(message, cert, dss, &self.algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

/// adb probe: records the phone's adb TLS public-key hash, then aborts the handshake (CarbonMirror never
/// completes a TLS session with adbd itself; adb does that).
#[derive(Debug)]
struct CaptureVerifier {
    captured: Arc<Mutex<Option<[u8; PIN_LEN]>>>,
    algorithms: WebPkiSupportedAlgorithms,
}

impl ServerCertVerifier for CaptureVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        let hash = spki_hash(end_entity).map_err(|_| rustls::Error::InvalidCertificate(rustls::CertificateError::BadEncoding))?;
        if let Ok(mut slot) = self.captured.lock() {
            *slot = Some(hash);
        }
        Err(rustls::Error::General("captured".into()))
    }

    fn verify_tls12_signature(&self, _: &[u8], _: &CertificateDer<'_>, _: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        Err(rustls::Error::General("TLS 1.2 is not allowed".into()))
    }

    fn verify_tls13_signature(&self, message: &[u8], cert: &CertificateDer<'_>, dss: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(message, cert, dss, &self.algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

fn client_builder(p: Arc<CryptoProvider>) -> CmResult<rustls::ConfigBuilder<ClientConfig, rustls::WantsVerifier>> {
    ClientConfig::builder_with_provider(p).with_protocol_versions(&[&rustls::version::TLS13]).map_err(tls_err)
}

fn harden_client(mut config: ClientConfig) -> ClientConfig {
    config.alpn_protocols = vec![ALPN.to_vec()];
    config.resumption = Resumption::disabled();
    config.enable_early_data = false;
    config
}

/// Prepared configuration for one side of a session (Mac client or phone server).
pub enum Identity {
    Client(Arc<ClientConfig>),
    Server { config: Arc<ServerConfig>, spki_hash: [u8; PIN_LEN] },
}

impl Identity {
    /// Mac: fresh Ed25519 client certificate signed by the identity key; the phone's session key is pinned.
    pub fn client(signer: &dyn IdentitySigner, phone_pin: &[u8]) -> CmResult<Self> {
        let pin: [u8; PIN_LEN] = phone_pin.try_into().map_err(|_| CmStatus::InvalidArgument)?;
        let (key, key_der) = ephemeral_key()?;
        let ca = ca_params()?;
        let issuer = Issuer::from_params(&ca, SignerAdapter(signer));
        let cert = session_params("CarbonMirror Mac session", ExtendedKeyUsagePurpose::ClientAuth)?
            .signed_by(&key, &issuer)
            .map_err(cert_err)?;
        let p = Arc::new(provider());
        let verifier = Arc::new(PinnedServerVerifier { pin, algorithms: p.signature_verification_algorithms });
        let config = client_builder(p)?
            .dangerous()
            .with_custom_certificate_verifier(verifier)
            .with_client_auth_cert(vec![cert.der().clone()], private_key(&key_der))
            .map_err(tls_err)?;
        Ok(Self::Client(Arc::new(harden_client(config))))
    }

    /// Phone: fresh Ed25519 server certificate; only client certificates issued by the pinned Mac CA pass.
    pub fn server(mac_ca_der: &[u8]) -> CmResult<Self> {
        let mut roots = RootCertStore::empty();
        roots.add(CertificateDer::from(mac_ca_der.to_vec())).map_err(|_| CmStatus::ParseMalformed)?;
        let p = Arc::new(provider());
        let verifier = WebPkiClientVerifier::builder_with_provider(Arc::new(roots), p.clone()).build().map_err(|_| CmStatus::InvalidArgument)?;
        let (key, key_der) = ephemeral_key()?;
        let cert = session_params("CarbonMirror phone session", ExtendedKeyUsagePurpose::ServerAuth)?.self_signed(&key).map_err(cert_err)?;
        let spki_hash = spki_hash(cert.der())?;
        let mut config = ServerConfig::builder_with_provider(p)
            .with_protocol_versions(&[&rustls::version::TLS13])
            .map_err(tls_err)?
            .with_client_cert_verifier(verifier)
            .with_single_cert(vec![cert.der().clone()], private_key(&key_der))
            .map_err(tls_err)?;
        config.alpn_protocols = vec![ALPN.to_vec()];
        config.session_storage = Arc::new(NoServerSessionStorage {});
        config.send_tls13_tickets = 0;
        config.max_early_data_size = 0;
        Ok(Self::Server { config: Arc::new(config), spki_hash })
    }

    /// Hash the Mac pins for this server session (phone side only).
    pub fn spki_hash(&self) -> Option<[u8; PIN_LEN]> {
        match self {
            Self::Server { spki_hash, .. } => Some(*spki_hash),
            Self::Client(_) => None,
        }
    }
}

fn server_name() -> ServerName<'static> {
    ServerName::from(std::net::IpAddr::from([127, 0, 0, 1]))
}

/// One TLS connection over a byte stream owned by the caller.
pub struct Session {
    conn: Connection,
    /// Decrypted data not yet read. rustls keeps at most 16 KiB of unread plaintext and refuses further
    /// records beyond that, so every batch is moved here (bounded by `PLAIN_LIMIT`, zeroed on drop).
    plain: Vec<u8>,
    peer_closed: bool,
    started: Instant,
    last_key_update: Instant,
    bytes_since_update: u64,
    policy_checked: bool,
    captured: Option<Arc<Mutex<Option<[u8; PIN_LEN]>>>>,
}

impl Session {
    fn wrap(mut conn: Connection, captured: Option<Arc<Mutex<Option<[u8; PIN_LEN]>>>>) -> Self {
        conn.set_buffer_limit(Some(BUFFER_LIMIT));
        let now = Instant::now();
        Self { conn, plain: Vec::new(), peer_closed: false, started: now, last_key_update: now, bytes_since_update: 0, policy_checked: false, captured }
    }

    pub fn new(identity: &Identity) -> CmResult<Self> {
        let conn: Connection = match identity {
            Identity::Client(config) => ClientConnection::new(config.clone(), server_name()).map_err(tls_err)?.into(),
            Identity::Server { config, .. } => ServerConnection::new(config.clone()).map_err(tls_err)?.into(),
        };
        Ok(Self::wrap(conn, None))
    }

    /// Client that only records the peer's public-key hash (adb TLS fingerprint probe).
    pub fn capture() -> CmResult<Self> {
        let p = Arc::new(provider());
        let captured = Arc::new(Mutex::new(None));
        let verifier = Arc::new(CaptureVerifier { captured: captured.clone(), algorithms: p.signature_verification_algorithms });
        let mut config = client_builder(p)?.dangerous().with_custom_certificate_verifier(verifier).with_no_client_auth();
        config.resumption = Resumption::disabled();
        let conn = ClientConnection::new(Arc::new(config), server_name()).map_err(tls_err)?;
        Ok(Self::wrap(conn.into(), Some(captured)))
    }

    /// Public-key hash recorded by a capture session.
    pub fn captured(&self) -> Option<[u8; PIN_LEN]> {
        self.captured.as_ref().and_then(|c| c.lock().ok().and_then(|g| *g))
    }

    fn map_error(&self, e: &rustls::Error) -> CmStatus {
        match e {
            rustls::Error::InvalidCertificate(_) | rustls::Error::NoCertificatesPresented => CmStatus::TlsPinMismatch,
            rustls::Error::PeerIncompatible(_) | rustls::Error::NoApplicationProtocol => CmStatus::TlsPolicyViolation,
            _ if self.conn.is_handshaking() => CmStatus::TlsHandshakeFailed,
            _ => CmStatus::TlsFailed,
        }
    }

    fn check_progress(&mut self) -> CmResult<()> {
        if self.conn.is_handshaking() {
            if self.started.elapsed() > HANDSHAKE_TIMEOUT {
                return Err(CmStatus::TlsTimeout);
            }
            return Ok(());
        }
        if !self.policy_checked {
            let suite_ok = self.conn.negotiated_cipher_suite().is_some_and(|s| provider().cipher_suites.iter().any(|a| a.suite() == s.suite()));
            if self.conn.alpn_protocol() != Some(ALPN) || !suite_ok || self.conn.protocol_version() != Some(rustls::ProtocolVersion::TLSv1_3) {
                return Err(CmStatus::TlsPolicyViolation);
            }
            self.policy_checked = true;
        }
        Ok(())
    }

    /// Feeds ciphertext received from the socket; every byte is consumed or the session fails.
    pub fn read_tls(&mut self, mut data: &[u8]) -> CmResult<()> {
        while !data.is_empty() {
            let n = self.conn.read_tls(&mut data).map_err(|_| CmStatus::TlsFailed)?;
            if n == 0 {
                return Err(CmStatus::TlsFailed);
            }
            if let Err(e) = self.conn.process_new_packets() {
                return Err(self.map_error(&e));
            }
            self.drain_plaintext()?;
        }
        self.check_progress()
    }

    /// Moves everything rustls decrypted into `plain`; a peer that outruns the reader past `PLAIN_LIMIT` fails.
    fn drain_plaintext(&mut self) -> CmResult<()> {
        let mut chunk = [0u8; 16 * 1024];
        loop {
            match self.conn.reader().read(&mut chunk) {
                Ok(0) => {
                    self.peer_closed = true;
                    break;
                }
                Ok(n) => self.plain.extend_from_slice(&chunk[..n]),
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                Err(_) => return Err(CmStatus::TlsFailed),
            }
            if self.plain.len() > PLAIN_LIMIT {
                return Err(CmStatus::ParseTooLarge);
            }
        }
        chunk.zeroize();
        Ok(())
    }

    /// Ciphertext to send to the socket.
    pub fn write_tls(&mut self, mut out: &mut [u8]) -> CmResult<usize> {
        let mut total = 0;
        while self.conn.wants_write() && !out.is_empty() {
            let n = self.conn.write_tls(&mut out).map_err(|_| CmStatus::TlsFailed)?;
            if n == 0 {
                break;
            }
            total += n;
        }
        Ok(total)
    }

    /// Decrypted application data; 0 when nothing is pending. A closed peer is reported as `TlsClosed`.
    pub fn read_plain(&mut self, out: &mut [u8]) -> CmResult<usize> {
        if self.plain.is_empty() {
            return if self.peer_closed && !out.is_empty() { Err(CmStatus::TlsClosed) } else { Ok(0) };
        }
        let n = out.len().min(self.plain.len());
        out[..n].copy_from_slice(&self.plain[..n]);
        self.plain[..n].zeroize();
        self.plain.drain(..n);
        Ok(n)
    }

    /// Queues application data for encryption; refreshes traffic keys on schedule first.
    pub fn write_plain(&mut self, data: &[u8]) -> CmResult<usize> {
        if self.captured.is_some() {
            return Err(CmStatus::InvalidArgument);
        }
        if !self.conn.is_handshaking()
            && (self.bytes_since_update >= KEY_UPDATE_BYTES || self.last_key_update.elapsed() >= KEY_UPDATE_INTERVAL)
        {
            self.conn.refresh_traffic_keys().map_err(|_| CmStatus::TlsFailed)?;
            self.last_key_update = Instant::now();
            self.bytes_since_update = 0;
        }
        let n = self.conn.writer().write(data).map_err(|_| CmStatus::TlsFailed)?;
        self.bytes_since_update = self.bytes_since_update.saturating_add(n as u64);
        Ok(n)
    }

    pub fn status(&self) -> u32 {
        let mut s = 0;
        if self.conn.is_handshaking() {
            s |= STATUS_HANDSHAKING;
        }
        if self.conn.wants_write() {
            s |= STATUS_WANTS_WRITE;
        }
        s
    }

    /// Negotiated cipher suite and key-exchange group (IANA ids), once the handshake is done.
    pub fn negotiated(&self) -> CmResult<(u16, u16)> {
        let suite = self.conn.negotiated_cipher_suite().ok_or(CmStatus::NeedMoreData)?;
        let group = self.conn.negotiated_key_exchange_group().ok_or(CmStatus::NeedMoreData)?;
        Ok((u16::from(suite.suite()), u16::from(group.name())))
    }

    /// Sends close_notify (call `write_tls` afterwards to flush it).
    pub fn close(&mut self) {
        self.conn.send_close_notify();
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.plain.zeroize();
    }
}
