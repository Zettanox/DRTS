use anyhow::Result;
use rusqlite::{params, Connection};
use std::path::Path;
use std::sync::Mutex;

use crate::schema::ChatMessage;

/// A contact in the user's address book.
#[derive(Debug, Clone)]
pub struct Contact {
    pub peer_id: String,
    pub display_name: String,
    pub added_at: i64,
}

pub struct MessageStore {
    conn: Mutex<Connection>,
}

impl MessageStore {
    pub fn new<P: AsRef<Path>>(db_path: P) -> Result<Self> {
        let conn = Connection::open(db_path)?;
        
        conn.execute(
            "CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                sender_id TEXT NOT NULL,
                topic TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp INTEGER NOT NULL
            )",
            [],
        )?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS contacts (
                peer_id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                added_at INTEGER NOT NULL
            )",
            [],
        )?;
        
        Ok(Self { conn: Mutex::new(conn) })
    }

    // ── Messages ──────────────────────────────────────────────

    pub fn insert_message(&self, msg: &ChatMessage) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| anyhow::anyhow!("Lock poisoned: {}", e))?;
        conn.execute(
            "INSERT OR IGNORE INTO messages (id, sender_id, topic, content, timestamp)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![msg.id, msg.sender_id, msg.topic, msg.content, msg.timestamp],
        )?;
        Ok(())
    }

    pub fn get_messages(&self, topic: &str) -> Result<Vec<ChatMessage>> {
        let conn = self.conn.lock().map_err(|e| anyhow::anyhow!("Lock poisoned: {}", e))?;
        let mut stmt = conn.prepare(
            "SELECT id, sender_id, topic, content, timestamp 
             FROM messages 
             WHERE topic = ?1 
             ORDER BY timestamp ASC"
        )?;
        
        let message_iter = stmt.query_map(params![topic], |row| {
            Ok(ChatMessage {
                id: row.get(0)?,
                sender_id: row.get(1)?,
                topic: row.get(2)?,
                content: row.get(3)?,
                timestamp: row.get(4)?,
            })
        })?;
        
        let mut messages = Vec::new();
        for msg in message_iter {
            messages.push(msg?);
        }
        
        Ok(messages)
    }

    // ── Contacts ──────────────────────────────────────────────

    pub fn add_contact(&self, peer_id: &str, display_name: &str) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| anyhow::anyhow!("Lock poisoned: {}", e))?;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as i64;
        conn.execute(
            "INSERT OR REPLACE INTO contacts (peer_id, display_name, added_at)
             VALUES (?1, ?2, ?3)",
            params![peer_id, display_name, now],
        )?;
        Ok(())
    }

    pub fn get_contacts(&self) -> Result<Vec<Contact>> {
        let conn = self.conn.lock().map_err(|e| anyhow::anyhow!("Lock poisoned: {}", e))?;
        let mut stmt = conn.prepare(
            "SELECT peer_id, display_name, added_at FROM contacts ORDER BY display_name ASC"
        )?;
        let iter = stmt.query_map([], |row| {
            Ok(Contact {
                peer_id: row.get(0)?,
                display_name: row.get(1)?,
                added_at: row.get(2)?,
            })
        })?;
        let mut contacts = Vec::new();
        for c in iter {
            contacts.push(c?);
        }
        Ok(contacts)
    }

    pub fn remove_contact(&self, peer_id: &str) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| anyhow::anyhow!("Lock poisoned: {}", e))?;
        conn.execute("DELETE FROM contacts WHERE peer_id = ?1", params![peer_id])?;
        Ok(())
    }
}

