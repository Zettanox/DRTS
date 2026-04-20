use serde::{Deserialize, Serialize};

/// All request types sent over the `/stoa/msg/1.0.0` protocol.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum StoaRequest {
    /// Ask a peer for their display name.
    WhoAreYou,
    /// A peer wants to add us as a contact.
    ContactRequest {
        from_peer_id: String,
        from_name: String,
    },
    /// A chat message from a contact.
    ChatMessage {
        id: String,
        content: String,
        timestamp: i64,
        sender_name: String,
    },
    /// Offer a file to a peer.
    FileOffer {
        transfer_id: String,
        file_name: String,
        file_size: u64,
        checksum: String,
        chunk_count: u32,
        chunk_size: u32,
        sender_name: String,
    },
    /// Request a specific chunk of a file (Pull method).
    FetchChunk {
        transfer_id: String,
        chunk_index: u32,
    },
    /// E2E: Send our X25519 public key for ECDH key exchange.
    KeyExchange {
        x25519_public_key_hex: String,
    },
    /// E2E: An encrypted envelope wrapping any message type.
    /// The decrypted payload is JSON that identifies its inner type.
    EncryptedEnvelope {
        id: String,
        ciphertext_b64: String,
        nonce_b64: String,
    },
    // ─── Group Variants ──────────────────────────────────────────────────────
    /// Invite a peer to a group (auto-accept since they're a contact).
    GroupInvite {
        group_id: String,
        group_name: String,
        members: Vec<String>,
        admin: String,
        inviter_name: String,
    },
    /// A chat message in a group.
    GroupMessage {
        group_id: String,
        id: String,
        content: String,
        timestamp: i64,
        sender_name: String,
    },
    /// Offer a file to a group (each member pulls independently).
    GroupFileOffer {
        group_id: String,
        transfer_id: String,
        file_name: String,
        file_size: u64,
        checksum: String,
        chunk_count: u32,
        chunk_size: u32,
        sender_name: String,
    },
    /// Admin removed a member from the group.
    MemberRemoved {
        group_id: String,
        removed_peer_id: String,
    },
    /// A member left the group voluntarily.
    MemberLeft {
        group_id: String,
        peer_id: String,
    },
    /// Admin disbanded the group.
    GroupDisbanded {
        group_id: String,
    },
    // ─── Shared Space Protocol ───────────────────────────────────────────────
    /// Step 1: Send local StateVector to sync missing updates
    GroupSpaceSync {
        group_id: String,
        state_vector_b64: String,
    },
    /// Live incremental updates pushed to peers
    GroupSpaceUpdate {
        group_id: String,
        update_b64: String,
    },
}

/// All response types for the `/stoa/msg/1.0.0` protocol.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum StoaResponse {
    /// Response to WhoAreYou — our display name.
    PeerIdentity { name: String },
    /// Contact request accepted — includes our display name.
    ContactAccepted { name: String },
    /// Contact request rejected.
    ContactRejected,
    /// Acknowledgement that a chat message was received.
    MessageAck { id: String },
    /// File offer accepted — ready to receive chunks.
    FileAccepted { transfer_id: String },
    /// File offer rejected.
    FileRejected { transfer_id: String },
    /// A chunk of file data (base64-encoded) responding to a FetchChunk.
    FileChunk {
        transfer_id: String,
        chunk_index: u32,
        data_b64: String,
        /// Optional nonce for E2E encrypted chunk data.
        #[serde(skip_serializing_if = "Option::is_none")]
        nonce_b64: Option<String>,
    },
    /// E2E: Acknowledge key exchange with our X25519 public key.
    KeyExchangeAck {
        x25519_public_key_hex: String,
    },
    /// Acknowledgement of a group message.
    GroupAck {
        group_id: String,
        message_id: String,
    },
    // ─── Shared Space Protocol ───────────────────────────────────────────────
    /// Step 2: Receive the missing updates from peer
    GroupSpaceSyncReply {
        group_id: String,
        update_b64: String,
    },
    /// Acknowledgement of an incoming group space update
    GroupSpaceUpdateAck {
        group_id: String,
    },
}
