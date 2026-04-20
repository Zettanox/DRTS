use crate::contacts::Contact;
use libp2p::PeerId;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::protocol::StoaRequest;

/// Info about a discovered LAN peer. Sent to the frontend.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NearbyPeer {
    pub peer_id: String,
    pub addresses: Vec<String>,
    pub display_name: Option<String>,
}

/// Commands the frontend can send to the network task.
#[derive(Debug)]
pub enum NetworkCommand {
    /// Explicitly dial a peer over a relay circuit
    DialPeer {
        peer_id: String,
        relay_addrs: Vec<String>,
    },
    /// Send a contact request to a peer
    SendContactRequest {
        peer_id: String,
        our_name: String,
        our_peer_id: String,
    },
    /// Send a chat message to a contact
    SendMessage {
        peer_id: String,
        message_id: String,
        content: String,
        sender_name: String,
    },
    /// Send a file to a peer
    SendFile {
        peer_id: String,
        file_path: String,
        sender_name: String,
    },
    /// A file has finished hashing and is ready to be offered
    FilePrepared {
        peer_id: String,
        file_path: String,
        file_name: String,
        file_size: u64,
        checksum: String,
        chunk_count: u32,
        sender_name: String,
    },
    /// Pause an ongoing file transfer
    PauseTransfer {
        transfer_id: String,
    },
    /// Resume a paused file transfer
    ResumeTransfer {
        transfer_id: String,
    },
    /// Toggle LAN visibility (mDNS on/off)
    SetVisibility(bool),
    // ─── Group Commands ──────────────────────────────────────────────────────
    /// Create a new group and invite members
    CreateGroup {
        name: String,
        member_ids: Vec<String>,
    },
    /// Send a message to all group members
    SendGroupMessage {
        group_id: String,
        message_id: String,
        content: String,
        sender_name: String,
    },
    /// Send a file to all group members
    SendGroupFile {
        group_id: String,
        file_path: String,
        sender_name: String,
    },
    /// Leave a group
    LeaveGroup {
        group_id: String,
    },
    /// Admin: remove a member from a group
    RemoveGroupMember {
        group_id: String,
        peer_id: String,
    },
    /// Admin: disband a group
    DisbandGroup {
        group_id: String,
    },
    /// Open group space (initiate CRDT sync)
    OpenGroupSpace {
        group_id: String,
    },
    /// Edit a specific file in the group space (apply local CRDT edit and broadcast)
    EditGroupSpace {
        group_id: String,
        file_id: String,
        index: u32,
        delete_count: u32,
        insert_text: String,
    },
    /// Create a new text file in the group space
    CreateSpaceFile {
        group_id: String,
        file_name: String,
        content: Option<String>,
    },
    /// Delete a file from the group space
    DeleteSpaceFile {
        group_id: String,
        file_id: String,
    },
    /// Shut down the network task
    Shutdown,
}

/// A message waiting for a connection to be established.
#[derive(Debug)]
pub struct PendingMessage {
    pub peer_id: PeerId,
    pub request: StoaRequest,
    pub peer_id_str: String,
    pub message_id: Option<String>,
    pub content: Option<String>,
}

/// Shared state tracking discovered peers.
pub type NearbyPeersMap = Arc<Mutex<HashMap<String, NearbyPeer>>>;

/// Shared list of known contacts for auto-dialing.
pub type ContactsList = Arc<Mutex<Vec<Contact>>>;
