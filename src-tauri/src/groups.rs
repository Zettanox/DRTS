//! Group state management for Stoa.
//!
//! Groups are serverless mesh groups — every member communicates directly
//! with every other member. The creator is the admin.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// A Stoa group.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Group {
    pub id: String,
    pub name: String,
    pub members: Vec<String>, // peer IDs (includes self)
    pub admin: String,        // peer ID of creator/admin
    pub created_at: i64,
}

fn groups_path() -> Result<PathBuf, String> {
    let dir = crate::get_stoa_dir();
    std::fs::create_dir_all(&dir).map_err(|e| format!("Failed to create .stoa dir: {e}"))?;
    Ok(dir.join("groups.json"))
}

/// Load all groups from disk.
pub fn load_groups() -> Result<Vec<Group>, String> {
    let path = groups_path()?;
    if !path.exists() {
        return Ok(vec![]);
    }
    let data =
        std::fs::read_to_string(&path).map_err(|e| format!("Failed to read groups: {e}"))?;
    serde_json::from_str(&data).map_err(|e| format!("Failed to parse groups: {e}"))
}

/// Save all groups to disk.
pub fn save_groups(groups: &[Group]) -> Result<(), String> {
    let path = groups_path()?;
    let data =
        serde_json::to_string_pretty(groups).map_err(|e| format!("Failed to serialize: {e}"))?;
    std::fs::write(&path, data).map_err(|e| format!("Failed to write groups: {e}"))
}

/// Create a new group and persist it.
pub fn create_group(
    groups: &mut Vec<Group>,
    id: String,
    name: String,
    members: Vec<String>,
    admin: String,
) -> Result<Group, String> {
    let group = Group {
        id,
        name,
        members,
        admin,
        created_at: chrono::Utc::now().timestamp(),
    };
    groups.push(group.clone());
    save_groups(groups)?;
    Ok(group)
}

/// Add a group received via invite.
pub fn add_group_from_invite(groups: &mut Vec<Group>, group: Group) -> Result<(), String> {
    // Don't add duplicates
    if groups.iter().any(|g| g.id == group.id) {
        // Update members list in case it changed
        if let Some(existing) = groups.iter_mut().find(|g| g.id == group.id) {
            existing.members = group.members;
            existing.name = group.name;
        }
    } else {
        groups.push(group);
    }
    save_groups(groups)
}

/// Remove a member from a group.
pub fn remove_member(groups: &mut Vec<Group>, group_id: &str, peer_id: &str) -> Result<(), String> {
    if let Some(group) = groups.iter_mut().find(|g| g.id == group_id) {
        group.members.retain(|m| m != peer_id);
        save_groups(groups)
    } else {
        Err("Group not found".into())
    }
}

/// Remove a group entirely (leave or disband).
pub fn remove_group(groups: &mut Vec<Group>, group_id: &str) -> Result<(), String> {
    groups.retain(|g| g.id != group_id);
    save_groups(groups)
}

/// Rename a group.
pub fn rename_group(groups: &mut Vec<Group>, group_id: &str, new_name: String) -> Result<(), String> {
    if let Some(group) = groups.iter_mut().find(|g| g.id == group_id) {
        group.name = new_name;
        save_groups(groups)
    } else {
        Err("Group not found".into())
    }
}
