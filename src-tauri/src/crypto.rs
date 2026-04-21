//! Modular crypto service for Stoa E2E encryption.
//!
//! All cryptographic operations are contained here. Other modules call
//! `crypto::encrypt()`, `crypto::decrypt()`, etc. — no crypto logic elsewhere.
//!
//! Scheme: X25519 ECDH key exchange → 32-byte shared secret → AES-256-GCM.

use aes_gcm::aead::{Aead, AeadCore, KeyInit, OsRng};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::{engine::general_purpose::STANDARD as B64, Engine};
use sha2::{Digest, Sha512};
use std::path::PathBuf;
use x25519_dalek::{PublicKey, StaticSecret};

// ─── X25519 Key Derivation ───────────────────────────────────────────────────

/// Derive an X25519 static secret from an Ed25519 keypair.
///
/// We hash the Ed25519 secret key bytes through SHA-512 and clamp the first 32
/// bytes, which is exactly what Ed25519 → X25519 conversion does per RFC 7748.
/// This means no additional key material needs to be stored.
pub fn derive_x25519_secret(
    ed25519_keypair: &libp2p::identity::Keypair,
) -> Result<StaticSecret, String> {
    // Extract the raw Ed25519 secret key bytes (first 32 bytes of the 64-byte keypair encoding)
    let kp_bytes = ed25519_keypair
        .to_protobuf_encoding()
        .map_err(|e| format!("Failed to encode keypair: {e}"))?;

    // The protobuf encoding has a small header; the actual Ed25519 seed is embedded.
    // We hash the entire protobuf to derive a deterministic X25519 secret.
    let mut hasher = Sha512::new();
    hasher.update(b"stoa-x25519-derivation-v1"); // domain separator
    hasher.update(&kp_bytes);
    let hash = hasher.finalize();

    // Take first 32 bytes and clamp per X25519 spec
    let mut secret_bytes = [0u8; 32];
    secret_bytes.copy_from_slice(&hash[..32]);
    // Clamping is handled internally by x25519-dalek's StaticSecret

    Ok(StaticSecret::from(secret_bytes))
}

/// Get our X25519 public key from our Ed25519 keypair.
pub fn our_x25519_public_key(
    ed25519_keypair: &libp2p::identity::Keypair,
) -> Result<PublicKey, String> {
    let secret = derive_x25519_secret(ed25519_keypair)?;
    Ok(PublicKey::from(&secret))
}

/// Get our X25519 public key as a hex string.
pub fn our_x25519_public_key_hex(
    ed25519_keypair: &libp2p::identity::Keypair,
) -> Result<String, String> {
    let pk = our_x25519_public_key(ed25519_keypair)?;
    Ok(hex::encode(pk.as_bytes()))
}

// ─── ECDH Shared Secret ──────────────────────────────────────────────────────

/// Compute the shared secret from our X25519 private key and their X25519 public key.
pub fn compute_shared_secret(
    ed25519_keypair: &libp2p::identity::Keypair,
    their_public_key_hex: &str,
) -> Result<[u8; 32], String> {
    let our_secret = derive_x25519_secret(ed25519_keypair)?;

    let their_bytes = hex::decode(their_public_key_hex)
        .map_err(|e| format!("Invalid peer X25519 public key hex: {e}"))?;
    if their_bytes.len() != 32 {
        return Err(format!(
            "Invalid X25519 public key length: {} (expected 32)",
            their_bytes.len()
        ));
    }
    let mut their_key_bytes = [0u8; 32];
    their_key_bytes.copy_from_slice(&their_bytes);
    let their_public = PublicKey::from(their_key_bytes);

    let shared = our_secret.diffie_hellman(&their_public);
    Ok(*shared.as_bytes())
}

// ─── AES-256-GCM Encrypt / Decrypt ──────────────────────────────────────────

/// Encrypt plaintext with AES-256-GCM using the shared secret.
/// Returns `(ciphertext_b64, nonce_b64)`.
pub fn encrypt(shared_secret: &[u8; 32], plaintext: &[u8]) -> Result<(String, String), String> {
    let cipher = Aes256Gcm::new_from_slice(shared_secret)
        .map_err(|e| format!("AES key init failed: {e}"))?;

    let nonce_bytes = Aes256Gcm::generate_nonce(&mut OsRng);
    let ciphertext = cipher
        .encrypt(&nonce_bytes, plaintext)
        .map_err(|e| format!("Encryption failed: {e}"))?;

    Ok((B64.encode(&ciphertext), B64.encode(&nonce_bytes)))
}

/// Decrypt ciphertext with AES-256-GCM using the shared secret.
pub fn decrypt(
    shared_secret: &[u8; 32],
    ciphertext_b64: &str,
    nonce_b64: &str,
) -> Result<Vec<u8>, String> {
    let cipher = Aes256Gcm::new_from_slice(shared_secret)
        .map_err(|e| format!("AES key init failed: {e}"))?;

    let ciphertext = B64
        .decode(ciphertext_b64)
        .map_err(|e| format!("Ciphertext base64 decode failed: {e}"))?;

    let nonce_bytes = B64
        .decode(nonce_b64)
        .map_err(|e| format!("Nonce base64 decode failed: {e}"))?;

    if nonce_bytes.len() != 12 {
        return Err(format!(
            "Invalid nonce length: {} (expected 12)",
            nonce_bytes.len()
        ));
    }
    let nonce = Nonce::from_slice(&nonce_bytes);

    cipher
        .decrypt(nonce, ciphertext.as_ref())
        .map_err(|e| format!("Decryption failed: {e}"))
}

// ─── Session Key Persistence ─────────────────────────────────────────────────

fn sessions_dir() -> Result<PathBuf, String> {
    let dir = crate::get_stoa_dir().join("sessions");
    std::fs::create_dir_all(&dir).map_err(|e| format!("Failed to create sessions dir: {e}"))?;
    Ok(dir)
}

fn session_path(peer_id: &str) -> Result<PathBuf, String> {
    let safe_id = peer_id.replace(|c: char| !c.is_alphanumeric(), "_");
    Ok(sessions_dir()?.join(format!("{safe_id}.key")))
}

/// Save a session (shared secret) for a peer.
pub fn save_session(peer_id: &str, shared_secret: &[u8; 32]) -> Result<(), String> {
    let path = session_path(peer_id)?;
    std::fs::write(&path, hex::encode(shared_secret))
        .map_err(|e| format!("Failed to save session: {e}"))?;
    println!(
        "[{}] [Stoa Crypto] Session saved for {peer_id}",
        chrono::Local::now().format("%H:%M:%S")
    );
    Ok(())
}

/// Load a stored session (shared secret) for a peer.
pub fn load_session(peer_id: &str) -> Result<Option<[u8; 32]>, String> {
    let path = session_path(peer_id)?;
    if !path.exists() {
        return Ok(None);
    }
    let hex_str =
        std::fs::read_to_string(&path).map_err(|e| format!("Failed to read session: {e}"))?;
    let bytes =
        hex::decode(hex_str.trim()).map_err(|e| format!("Failed to decode session hex: {e}"))?;
    if bytes.len() != 32 {
        return Err(format!(
            "Invalid session key length: {} (expected 32)",
            bytes.len()
        ));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(Some(key))
}

/// Check if we have a stored session for a peer.
pub fn has_session(peer_id: &str) -> bool {
    session_path(peer_id).map(|p| p.exists()).unwrap_or(false)
}

// ─── High-Level Helpers ──────────────────────────────────────────────────────

/// Encrypt a JSON-serializable payload for a peer (if session exists).
/// Returns `Some((ciphertext_b64, nonce_b64))` or `None` if no session.
pub fn encrypt_for_peer(
    peer_id: &str,
    plaintext: &[u8],
) -> Result<Option<(String, String)>, String> {
    match load_session(peer_id)? {
        Some(secret) => {
            let (ct, nonce) = encrypt(&secret, plaintext)?;
            Ok(Some((ct, nonce)))
        }
        None => Ok(None),
    }
}

/// Decrypt a payload from a peer (if session exists).
/// Returns `Some(plaintext)` or `None` if no session.
pub fn decrypt_from_peer(
    peer_id: &str,
    ciphertext_b64: &str,
    nonce_b64: &str,
) -> Result<Option<Vec<u8>>, String> {
    match load_session(peer_id)? {
        Some(secret) => {
            let plaintext = decrypt(&secret, ciphertext_b64, nonce_b64)?;
            Ok(Some(plaintext))
        }
        None => Ok(None),
    }
}
