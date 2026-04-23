use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// File metadata stored alongside a message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredFileInfo {
    pub transfer_id: String,
    pub file_name: String,
    pub file_size: u64,
    pub direction: String, // "upload" or "download"
    pub status: String,    // "transferring", "complete", "failed"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_path: Option<String>,
}

/// A persisted chat message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredMessage {
    pub id: String,
    pub sender_id: String,
    pub content: String,
    pub timestamp: i64,
    pub delivered: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_info: Option<StoredFileInfo>,
}

fn messages_dir() -> Result<PathBuf, String> {
    let dir = crate::get_stoa_dir().join("messages");
    std::fs::create_dir_all(&dir).map_err(|e| format!("Failed to create messages dir: {e}"))?;
    Ok(dir)
}

fn peer_messages_path(peer_id: &str) -> Result<PathBuf, String> {
    // Sanitize peer_id for filesystem safety
    let safe_id = peer_id.replace(|c: char| !c.is_alphanumeric(), "_");
    Ok(messages_dir()?.join(format!("{safe_id}.json")))
}

/// Load all messages for a conversation with a specific peer.
pub fn load_messages(peer_id: &str) -> Result<Vec<StoredMessage>, String> {
    let path = peer_messages_path(peer_id)?;
    if !path.exists() {
        return Ok(vec![]);
    }
    let data =
        std::fs::read_to_string(&path).map_err(|e| format!("Failed to read messages: {e}"))?;
    serde_json::from_str(&data).map_err(|e| format!("Failed to parse messages: {e}"))
}

/// Save a new message to the peer's message history.
pub fn save_message(peer_id: &str, msg: &StoredMessage) -> Result<(), String> {
    let mut messages = load_messages(peer_id)?;

    // Update existing message if same ID (e.g., marking delivered)
    if let Some(existing) = messages.iter_mut().find(|m| m.id == msg.id) {
        existing.delivered = msg.delivered;
        return write_messages(peer_id, &messages);
    }

    messages.push(msg.clone());
    write_messages(peer_id, &messages)
}

/// Mark a message as delivered.
pub fn mark_delivered(peer_id: &str, message_id: &str) -> Result<(), String> {
    let mut messages = load_messages(peer_id)?;
    if let Some(msg) = messages.iter_mut().find(|m| m.id == message_id) {
        msg.delivered = true;
        write_messages(peer_id, &messages)
    } else {
        Ok(()) // Message not found, ignore
    }
}

/// Get chat history for a peer, sorted by timestamp.
pub fn get_chat_history(peer_id: &str) -> Result<Vec<StoredMessage>, String> {
    let mut messages = load_messages(peer_id)?;
    messages.sort_by_key(|m| m.timestamp);
    Ok(messages)
}

fn write_messages(peer_id: &str, messages: &[StoredMessage]) -> Result<(), String> {
    let path = peer_messages_path(peer_id)?;
    let data = serde_json::to_string_pretty(messages)
        .map_err(|e| format!("Failed to serialize messages: {e}"))?;
    std::fs::write(&path, data).map_err(|e| format!("Failed to write messages: {e}"))
}

/// Delete a specific message from history.
pub fn delete_message(peer_id: &str, message_id: &str) -> Result<(), String> {
    delete_messages(peer_id, &[message_id.to_string()])
}

/// Delete multiple messages from history.
pub fn delete_messages(peer_id: &str, message_ids: &[String]) -> Result<(), String> {
    let mut messages = load_messages(peer_id)?;
    let initial_len = messages.len();
    messages.retain(|m| !message_ids.contains(&m.id));

    if messages.len() < initial_len {
        write_messages(peer_id, &messages)
    } else {
        Ok(())
    }
}

/// Clear all message history for a peer.
pub fn clear_chat_history(peer_id: &str) -> Result<(), String> {
    write_messages(peer_id, &[])
}
