use libp2p::identity::Keypair;
use libp2p::PeerId;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredIdentity {
    /// Ed25519 keypair bytes (PKCS8 encoded)
    pub keypair_bytes: Vec<u8>,
    /// Human-readable display name
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IdentityInfo {
    pub peer_id: String,
    pub public_key_hex: String,
    pub name: String,
}

/// Returns the path to ~/.stoa/
fn stoa_dir() -> PathBuf {
    crate::get_stoa_dir()
}

/// Returns the path to ~/.stoa/identity.json
fn identity_path() -> PathBuf {
    stoa_dir().join("identity.json")
}

/// Generate a fresh Ed25519 identity, persist it, and return the keypair + info.
pub fn generate_identity(display_name: &str) -> Result<(Keypair, IdentityInfo), String> {
    let keypair = Keypair::generate_ed25519();
    let peer_id = PeerId::from(keypair.public());

    // Serialize the keypair to protobuf bytes for storage
    let keypair_bytes = keypair
        .to_protobuf_encoding()
        .map_err(|e| format!("Failed to encode keypair: {e}"))?;

    let stored = StoredIdentity {
        keypair_bytes,
        name: display_name.to_string(),
    };

    // Ensure ~/.stoa/ exists
    let dir = stoa_dir();
    fs::create_dir_all(&dir).map_err(|e| format!("Failed to create {}: {e}", dir.display()))?;

    // Write identity.json
    let json = serde_json::to_string_pretty(&stored)
        .map_err(|e| format!("Failed to serialize identity: {e}"))?;
    fs::write(identity_path(), json).map_err(|e| format!("Failed to write identity file: {e}"))?;

    let info = IdentityInfo {
        peer_id: peer_id.to_string(),
        public_key_hex: hex::encode(keypair.public().encode_protobuf()),
        name: stored.name,
    };

    Ok((keypair, info))
}

/// Load an existing identity from disk, or create a new one with a generated name.
pub fn load_or_create_identity() -> Result<(Keypair, IdentityInfo), String> {
    let path = identity_path();

    if path.exists() {
        let json =
            fs::read_to_string(&path).map_err(|e| format!("Failed to read identity file: {e}"))?;
        let stored: StoredIdentity = serde_json::from_str(&json)
            .map_err(|e| format!("Failed to parse identity file: {e}"))?;

        let keypair = Keypair::from_protobuf_encoding(&stored.keypair_bytes)
            .map_err(|e| format!("Failed to decode keypair: {e}"))?;
        let peer_id = PeerId::from(keypair.public());

        let info = IdentityInfo {
            peer_id: peer_id.to_string(),
            public_key_hex: hex::encode(keypair.public().encode_protobuf()),
            name: stored.name,
        };

        Ok((keypair, info))
    } else {
        // Generate a random display name
        let name = format!("Crab_{}", rand::random::<u16>() % 10000);
        generate_identity(&name)
    }
}

/// Export the raw keypair bytes (protobuf-encoded) as base64, for cross-platform import.
pub fn export_keypair_base64() -> Result<String, String> {
    let path = identity_path();
    let json = fs::read_to_string(&path).map_err(|e| format!("No identity found: {e}"))?;
    let stored: StoredIdentity =
        serde_json::from_str(&json).map_err(|e| format!("Failed to parse identity: {e}"))?;

    use base64::Engine;
    Ok(base64::engine::general_purpose::STANDARD.encode(&stored.keypair_bytes))
}

/// Update the display name in the identity file without changing the keypair.
pub fn update_identity_name(new_name: &str) -> Result<IdentityInfo, String> {
    let path = identity_path();
    let json = fs::read_to_string(&path).map_err(|e| format!("No identity found: {e}"))?;
    let mut stored: StoredIdentity =
        serde_json::from_str(&json).map_err(|e| format!("Failed to parse identity: {e}"))?;

    stored.name = new_name.to_string();

    let json = serde_json::to_string_pretty(&stored)
        .map_err(|e| format!("Failed to serialize identity: {e}"))?;
    fs::write(&path, json).map_err(|e| format!("Failed to write identity file: {e}"))?;

    let keypair = Keypair::from_protobuf_encoding(&stored.keypair_bytes)
        .map_err(|e| format!("Failed to decode keypair: {e}"))?;
    let peer_id = PeerId::from(keypair.public());

    Ok(IdentityInfo {
        peer_id: peer_id.to_string(),
        public_key_hex: hex::encode(keypair.public().encode_protobuf()),
        name: stored.name,
    })
}
