use flutter_rust_bridge::frb;

#[frb(opaque)]
pub struct ChatStore {
    inner: stoa_messaging::MessageStore,
}

pub struct ChatMessage {
    pub id: String,
    pub sender_id: String,
    pub topic: String,
    pub content: String,
    pub timestamp: i64,
}

pub struct ContactEntry {
    pub peer_id: String,
    pub display_name: String,
    pub added_at: i64,
}

impl From<stoa_messaging::ChatMessage> for ChatMessage {
    fn from(msg: stoa_messaging::ChatMessage) -> Self {
        Self {
            id: msg.id,
            sender_id: msg.sender_id,
            topic: msg.topic,
            content: msg.content,
            timestamp: msg.timestamp,
        }
    }
}

impl From<ChatMessage> for stoa_messaging::ChatMessage {
    fn from(msg: ChatMessage) -> Self {
        Self {
            id: msg.id,
            sender_id: msg.sender_id,
            topic: msg.topic,
            content: msg.content,
            timestamp: msg.timestamp,
        }
    }
}

impl From<stoa_messaging::Contact> for ContactEntry {
    fn from(c: stoa_messaging::Contact) -> Self {
        Self {
            peer_id: c.peer_id,
            display_name: c.display_name,
            added_at: c.added_at,
        }
    }
}

impl ChatStore {
    #[frb(sync)]
    pub fn new(db_path: String) -> anyhow::Result<ChatStore> {
        let inner = stoa_messaging::MessageStore::new(db_path)?;
        Ok(Self { inner })
    }

    // ── Messages ──────────────────────────────────────────

    #[frb(sync)]
    pub fn insert_message(&self, msg: ChatMessage) -> anyhow::Result<()> {
        self.inner.insert_message(&msg.into())
    }

    #[frb(sync)]
    pub fn get_messages(&self, topic: String) -> anyhow::Result<Vec<ChatMessage>> {
        let msgs = self.inner.get_messages(&topic)?;
        Ok(msgs.into_iter().map(Into::into).collect())
    }

    // ── Contacts ──────────────────────────────────────────

    #[frb(sync)]
    pub fn add_contact(&self, peer_id: String, display_name: String) -> anyhow::Result<()> {
        self.inner.add_contact(&peer_id, &display_name)
    }

    #[frb(sync)]
    pub fn get_contacts(&self) -> anyhow::Result<Vec<ContactEntry>> {
        let contacts = self.inner.get_contacts()?;
        Ok(contacts.into_iter().map(Into::into).collect())
    }

    #[frb(sync)]
    pub fn remove_contact(&self, peer_id: String) -> anyhow::Result<()> {
        self.inner.remove_contact(&peer_id)
    }
}

