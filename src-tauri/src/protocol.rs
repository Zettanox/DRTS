use serde::{Deserialize, Serialize};

/// All request types sent over the `/stoa/msg/1.0.0` protocol.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum StoaRequest {
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
}

/// All response types for the `/stoa/msg/1.0.0` protocol.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum StoaResponse {
    /// Contact request accepted — includes our display name.
    ContactAccepted { name: String },
    /// Contact request rejected.
    ContactRejected,
    /// Acknowledgement that a chat message was received.
    MessageAck { id: String },
}
