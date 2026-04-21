use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// A saved contact in the local trust store.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Contact {
    pub peer_id: String,
    pub petname: String,
    pub added_at: i64,
    pub trust_level: TrustLevel,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub known_addrs: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TrustLevel {
    Direct,   // Added directly by the user
    Vouched,  // Vouched for by a trusted contact (future: web-of-trust)
}

fn contacts_path() -> Result<PathBuf, String> {
    let dir = crate::get_stoa_dir();
    std::fs::create_dir_all(&dir).map_err(|e| format!("Failed to create .stoa dir: {e}"))?;
    Ok(dir.join("contacts.json"))
}

/// Load contacts from disk. Returns empty vec if file doesn't exist.
pub fn load_contacts() -> Result<Vec<Contact>, String> {
    let path = contacts_path()?;
    if !path.exists() {
        return Ok(vec![]);
    }
    let data = std::fs::read_to_string(&path)
        .map_err(|e| format!("Failed to read contacts: {e}"))?;
    serde_json::from_str(&data)
        .map_err(|e| format!("Failed to parse contacts: {e}"))
}

/// Save the full contacts list to disk.
pub fn save_contacts(contacts: &[Contact]) -> Result<(), String> {
    let path = contacts_path()?;
    let data = serde_json::to_string_pretty(contacts)
        .map_err(|e| format!("Failed to serialize contacts: {e}"))?;
    std::fs::write(&path, data)
        .map_err(|e| format!("Failed to write contacts: {e}"))
}

/// Add a new contact or update existing one with new connection code. Returns Err on disk failure.
pub fn add_contact(contacts: &mut Vec<Contact>, peer_id: String, petname: String, known_addrs: Option<Vec<String>>) -> Result<(), String> {
    if let Some(existing) = contacts.iter_mut().find(|c| c.peer_id == peer_id) {
        // Update existing contact metadata
        existing.petname = petname;
        if known_addrs.is_some() {
            existing.known_addrs = known_addrs;
        }
        return save_contacts(contacts);
    }
    
    contacts.push(Contact {
        peer_id,
        petname,
        added_at: chrono::Utc::now().timestamp(),
        trust_level: TrustLevel::Direct,
        known_addrs,
    });

    save_contacts(contacts)
}

/// Remove a contact by peer_id.
pub fn remove_contact(contacts: &mut Vec<Contact>, peer_id: &str) -> Result<(), String> {
    contacts.retain(|c| c.peer_id != peer_id);
    save_contacts(contacts)
}

/// Rename a contact's petname.
pub fn rename_contact(contacts: &mut Vec<Contact>, peer_id: &str, new_name: String) -> Result<(), String> {
    if let Some(contact) = contacts.iter_mut().find(|c| c.peer_id == peer_id) {
        contact.petname = new_name;
        save_contacts(contacts)
    } else {
        Err("Contact not found".into())
    }
}
