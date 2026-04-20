//! connection_code.rs — Encode and decode peer connection codes for cross-network contact exchange.
//!
//! A "connection code" is a compact, human-shareable string that encodes everything
//! another Stoa user needs to dial you over the internet:
//!   - Your PeerID (64-byte Ed25519 public key hash)
//!   - Your relay multiaddr(s) (which relay to find you on)
//!
//! Format: `stoa1<bs58(version || peer_id_bytes || relay_addr_bytes)>`
//!
//! Users can share it as:
//!   - Plain text (paste in chat, email, etc.)
//!   - A QR code (scan with phone)
//!   - A clickable `stoa://` URL (future deep-link support)

use libp2p::PeerId;
use std::str::FromStr;

const VERSION: u8 = 1;
const PREFIX: &str = "stoa1";

/// A decoded connection code — everything needed to dial a peer over the internet.
#[derive(Debug, Clone)]
pub struct ConnectionCode {
    pub peer_id: PeerId,
    /// Relay multiaddrs the peer is registered on (may be empty for LAN-only)
    pub relay_addrs: Vec<String>,
}

impl ConnectionCode {
    pub fn new(peer_id: PeerId, relay_addrs: Vec<String>) -> Self {
        Self { peer_id, relay_addrs }
    }

    /// Encode to a shareable `stoa1<bs58>` string.
    pub fn encode(&self) -> String {
        let peer_bytes = self.peer_id.to_bytes(); // multihash bytes

        // Encode relay addrs as: [n_addrs: u8][len: u8][addr bytes]...
        let mut relay_bytes: Vec<u8> = Vec::new();
        let capped: Vec<&String> = self.relay_addrs.iter().take(3).collect(); // max 3 relays
        relay_bytes.push(capped.len() as u8);
        for addr in &capped {
            let b = addr.as_bytes();
            relay_bytes.push(b.len() as u8);
            relay_bytes.extend_from_slice(b);
        }

        let mut payload: Vec<u8> = Vec::new();
        payload.push(VERSION);
        payload.push(peer_bytes.len() as u8);
        payload.extend_from_slice(&peer_bytes);
        payload.extend_from_slice(&relay_bytes);

        format!("{}{}", PREFIX, bs58::encode(payload).into_string())
    }

    /// Decode from a `stoa1<bs58>` string.
    pub fn decode(code: &str) -> Result<Self, String> {
        let stripped = code
            .trim()
            .strip_prefix(PREFIX)
            .ok_or_else(|| format!("Not a Stoa connection code (must start with '{}', got: '{}')", PREFIX, code.trim()))?;

        let payload = bs58::decode(stripped)
            .into_vec()
            .map_err(|e| format!("Invalid base58: {e}"))?;

        let mut pos = 0;

        // Version byte
        let version = *payload.get(pos).ok_or("Truncated: missing version")?;
        if version != VERSION {
            return Err(format!("Unsupported code version: {version}"));
        }
        pos += 1;

        // PeerID bytes
        let peer_len = *payload.get(pos).ok_or("Truncated: missing peer_id length")? as usize;
        pos += 1;
        if pos + peer_len > payload.len() {
            return Err("Truncated: peer_id bytes".into());
        }
        let peer_id = PeerId::from_bytes(&payload[pos..pos + peer_len])
            .map_err(|e| format!("Invalid PeerID: {e}"))?;
        pos += peer_len;

        // Relay addrs
        let n_addrs = *payload.get(pos).ok_or("Truncated: relay count")? as usize;
        pos += 1;
        let mut relay_addrs = Vec::new();
        for _ in 0..n_addrs {
            let addr_len = *payload.get(pos).ok_or("Truncated: addr length")? as usize;
            pos += 1;
            if pos + addr_len > payload.len() {
                return Err("Truncated: addr bytes".into());
            }
            let addr_str = std::str::from_utf8(&payload[pos..pos + addr_len])
                .map_err(|e| format!("Invalid UTF-8 in relay addr: {e}"))?;
            relay_addrs.push(addr_str.to_string());
            pos += addr_len;
        }

        Ok(ConnectionCode { peer_id, relay_addrs })
    }

    /// Generate a QR code as a PNG image (base64-encoded for Tauri IPC).
    pub fn to_qr_base64(&self) -> Result<String, String> {
        use base64::Engine;
        use qrcode::QrCode;
        use qrcode::render::svg;

        let code_str = self.encode();

        let qr = QrCode::new(code_str.as_bytes())
            .map_err(|e| format!("QR generation failed: {e}"))?;

        // Render as SVG (no pixel manipulation needed, works without image crate)
        let svg_str = qr
            .render::<svg::Color>()
            .min_dimensions(200, 200)
            .build();

        // Base64-encode the SVG for transfer over IPC
        Ok(base64::engine::general_purpose::STANDARD.encode(svg_str.as_bytes()))
    }
}

/// Build our own connection code given our keypair and the currently configured relays.
pub fn build_our_code(
    keypair: &libp2p::identity::Keypair,
    relay_addrs: Vec<String>,
) -> Result<String, String> {
    let peer_id = PeerId::from(keypair.public());
    let code = ConnectionCode::new(peer_id, relay_addrs);
    Ok(code.encode())
}

/// Parse a peer's connection code and return a (PeerId, relay_addrs) tuple.
pub fn parse_peer_code(code: &str) -> Result<(String, Vec<String>), String> {
    let parsed = ConnectionCode::decode(code)?;
    Ok((parsed.peer_id.to_string(), parsed.relay_addrs))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let keypair = libp2p::identity::Keypair::generate_ed25519();
        let peer_id = PeerId::from(keypair.public());
        let code = ConnectionCode::new(
            peer_id,
            vec!["/ip4/1.2.3.4/tcp/4001/p2p/12D3KooWABC".to_string()],
        );
        let encoded = code.encode();
        assert!(encoded.starts_with("stoa1"), "prefix missing: {encoded}");

        let decoded = ConnectionCode::decode(&encoded).expect("decode failed");
        assert_eq!(decoded.peer_id, peer_id);
        assert_eq!(decoded.relay_addrs, code.relay_addrs);
    }

    #[test]
    fn rejects_bad_prefix() {
        assert!(ConnectionCode::decode("notastoa1abc").is_err());
    }
}
