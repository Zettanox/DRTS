use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub id: String,         // Unique message ID
    pub sender_id: String,  // Node ID of the sender
    pub topic: String,      // Group/Topic ID or Receiver ID
    pub content: String,
    pub timestamp: i64,     // Unix timestamp
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum StoaEvent {
    Chat(ChatMessage),
    // Future expansions: 
    // Presence(Vec<u8>),
    // DocumentSync(Vec<u8>),
}
