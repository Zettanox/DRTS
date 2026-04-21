use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;
use yrs::{Doc, GetString, Map, ReadTxn, StateVector, Text, Transact, Update};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

lazy_static! {
    static ref ACTIVE_DOCS: Mutex<HashMap<String, Arc<Mutex<Doc>>>> = Mutex::new(HashMap::new());
}

/// Metadata for a file within a Shared Space.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpaceFile {
    pub id: String,
    pub name: String,
    pub added_by: String,
    pub timestamp: i64,
    pub deleted: bool,
}

/// Maximum file size for imports (1 MB).
pub const MAX_IMPORT_SIZE: usize = 1_048_576;

/// Allowed text file extensions for import.
pub const ALLOWED_EXTENSIONS: &[&str] = &[
    "txt", "md", "rs", "ts", "js", "py", "json", "toml", "yaml", "yml",
    "css", "html", "xml", "csv", "log", "sh", "c", "cpp", "h", "go",
    "java", "tsx", "jsx", "svg", "sql", "rb", "php", "kt", "swift",
];

fn get_storage_path(group_id: &str) -> PathBuf {
    let mut path = crate::get_stoa_dir();
    path.push("groups");
    fs::create_dir_all(&path).unwrap_or_default();
    path.push(format!("{}.yrs", group_id));
    path
}

/// Load a document from disk or create a new one, keeping it in memory.
/// Performs migration from legacy single-document format if needed.
pub async fn load_or_create_doc(group_id: &str) -> Result<Arc<Mutex<Doc>>, String> {
    let mut docs = ACTIVE_DOCS.lock().await;

    if let Some(doc) = docs.get(group_id) {
        return Ok(doc.clone());
    }

    let path = get_storage_path(group_id);
    let doc = Doc::new();

    if path.exists() {
        if let Ok(data) = fs::read(&path) {
            if let Ok(update) = Update::decode_v1(&data) {
                let mut txn = doc.transact_mut();
                let _ = txn.apply_update(update);
                drop(txn);
            } else {
                eprintln!("[{}] [Stoa CRDT] Failed to decode existing doc for group {}", chrono::Local::now().format("%H:%M:%S"), group_id);
            }
        }

        // Migration: if there's a legacy "content" text but no manifest, migrate it
        migrate_legacy_doc(&doc, group_id);
    } else {
        // New doc — initialize with an empty manifest
        let manifest = doc.get_or_insert_map("manifest");
        let mut txn = doc.transact_mut();
        // Create a default "Untitled Document"
        let file_id = Uuid::new_v4().to_string();
        let meta = SpaceFile {
            id: file_id.clone(),
            name: "Untitled Document".to_string(),
            added_by: "system".to_string(),
            timestamp: chrono::Utc::now().timestamp(),
            deleted: false,
        };
        let meta_json = serde_json::to_string(&meta).unwrap_or_default();
        manifest.insert(&mut txn, file_id.clone(), meta_json);
        drop(txn);

        // Create the YText for this file
        let text = doc.get_or_insert_text(format!("file_{}", file_id));
        let mut txn = doc.transact_mut();
        text.insert(&mut txn, 0, "");
        drop(txn);

        save_snapshot_sync(&doc, group_id);
    }

    let arc_doc = Arc::new(Mutex::new(doc));
    docs.insert(group_id.to_string(), arc_doc.clone());

    Ok(arc_doc)
}

/// Migrate a legacy single-document space to multi-file format.
fn migrate_legacy_doc(doc: &Doc, group_id: &str) {
    let manifest = doc.get_or_insert_map("manifest");
    let txn = doc.transact();

    // Check if manifest already has entries
    if manifest.len(&txn) > 0 {
        return; // Already migrated
    }
    drop(txn);

    // Check if there's legacy "content" text with data
    let content = doc.get_or_insert_text("content");
    let txn = doc.transact();
    let text = content.get_string(&txn);
    drop(txn);

    if text.is_empty() {
        // No legacy data, just create a default file
        let file_id = Uuid::new_v4().to_string();
        let meta = SpaceFile {
            id: file_id.clone(),
            name: "Untitled Document".to_string(),
            added_by: "system".to_string(),
            timestamp: chrono::Utc::now().timestamp(),
            deleted: false,
        };
        let meta_json = serde_json::to_string(&meta).unwrap_or_default();
        let mut txn = doc.transact_mut();
        manifest.insert(&mut txn, file_id.clone(), meta_json);
        drop(txn);

        // Create empty YText for the new file
        let new_text = doc.get_or_insert_text(format!("file_{}", file_id));
        let mut txn = doc.transact_mut();
        new_text.insert(&mut txn, 0, "");
        drop(txn);
    } else {
        // Migrate existing content to a named file
        let file_id = Uuid::new_v4().to_string();
        let meta = SpaceFile {
            id: file_id.clone(),
            name: "Untitled Document".to_string(),
            added_by: "system".to_string(),
            timestamp: chrono::Utc::now().timestamp(),
            deleted: false,
        };
        let meta_json = serde_json::to_string(&meta).unwrap_or_default();
        let mut txn = doc.transact_mut();
        manifest.insert(&mut txn, file_id.clone(), meta_json);
        drop(txn);

        // Copy the legacy content into a new file_ YText
        let new_text = doc.get_or_insert_text(format!("file_{}", file_id));
        let mut txn = doc.transact_mut();
        new_text.insert(&mut txn, 0, &text);
        drop(txn);
    }

    save_snapshot_sync(doc, group_id);
    println!("[{}] [Stoa CRDT] Migrated legacy doc for group {} to multi-file format", chrono::Local::now().format("%H:%M:%S"), group_id);
}

fn save_snapshot_sync(doc: &Doc, group_id: &str) {
    let path = get_storage_path(group_id);
    let txn = doc.transact();
    let sv = StateVector::default(); // empty sv returns full document
    let data = txn.encode_diff_v1(&sv);
    if let Err(e) = fs::write(&path, data) {
        eprintln!("[{}] [Stoa CRDT] Failed to save snapshot for {}: {}", chrono::Local::now().format("%H:%M:%S"), group_id, e);
    }
}

// ─── Multi-File Operations ──────────────────────────────────────────────────

/// List all files in the space (including deleted ones — frontend filters).
pub async fn list_files(group_id: &str) -> Result<Vec<SpaceFile>, String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;
    let manifest = doc.get_or_insert_map("manifest");
    let txn = doc.transact();

    let mut files = Vec::new();
    for (key, value) in manifest.iter(&txn) {
        if let yrs::Out::Any(yrs::Any::String(json_str)) = value {
            if let Ok(meta) = serde_json::from_str::<SpaceFile>(json_str.as_ref()) {
                files.push(meta);
            }
        }
        // Fallback: try to parse from the key if value is different
        let _ = key; // consumed by iterator
    }

    // Sort by timestamp ascending (oldest first)
    files.sort_by_key(|f| f.timestamp);
    Ok(files)
}

/// Create a new empty text file in the space.
pub async fn create_file(
    group_id: &str,
    file_name: &str,
    added_by: &str,
) -> Result<(String, Vec<u8>), String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;

    let manifest = doc.get_or_insert_map("manifest");
    let file_id = Uuid::new_v4().to_string();
    let meta = SpaceFile {
        id: file_id.clone(),
        name: file_name.to_string(),
        added_by: added_by.to_string(),
        timestamp: chrono::Utc::now().timestamp(),
        deleted: false,
    };
    let meta_json = serde_json::to_string(&meta)
        .map_err(|e| format!("Serialization error: {}", e))?;

    let sv_before = doc.transact().state_vector();

    let mut txn = doc.transact_mut();
    manifest.insert(&mut txn, file_id.clone(), meta_json);
    drop(txn);

    // Create YText for the new file
    let text = doc.get_or_insert_text(format!("file_{}", file_id));
    let mut txn = doc.transact_mut();
    text.insert(&mut txn, 0, "");

    let update = txn.encode_diff_v1(&sv_before);
    drop(txn);

    save_snapshot_sync(&doc, group_id);
    Ok((file_id, update))
}

/// Create a new text file with imported content.
pub async fn create_file_with_content(
    group_id: &str,
    file_name: &str,
    content: &str,
    added_by: &str,
) -> Result<(String, Vec<u8>), String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;

    let manifest = doc.get_or_insert_map("manifest");
    let file_id = Uuid::new_v4().to_string();
    let meta = SpaceFile {
        id: file_id.clone(),
        name: file_name.to_string(),
        added_by: added_by.to_string(),
        timestamp: chrono::Utc::now().timestamp(),
        deleted: false,
    };
    let meta_json = serde_json::to_string(&meta)
        .map_err(|e| format!("Serialization error: {}", e))?;

    let sv_before = doc.transact().state_vector();

    let mut txn = doc.transact_mut();
    manifest.insert(&mut txn, file_id.clone(), meta_json);
    drop(txn);

    // Create YText and populate with content
    let text = doc.get_or_insert_text(format!("file_{}", file_id));
    let mut txn = doc.transact_mut();
    text.insert(&mut txn, 0, content);

    let update = txn.encode_diff_v1(&sv_before);
    drop(txn);

    save_snapshot_sync(&doc, group_id);
    Ok((file_id, update))
}

/// Mark a file as deleted in the manifest.
pub async fn delete_file(group_id: &str, file_id: &str) -> Result<Vec<u8>, String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;

    let manifest = doc.get_or_insert_map("manifest");

    // Read current metadata
    let txn = doc.transact();
    let current = manifest.get(&txn, file_id);
    drop(txn);

    let mut meta: SpaceFile = match current {
        Some(yrs::Out::Any(yrs::Any::String(json_str))) => {
            serde_json::from_str(json_str.as_ref())
                .map_err(|e| format!("Failed to parse file metadata: {}", e))?
        }
        _ => return Err(format!("File {} not found in manifest", file_id)),
    };

    meta.deleted = true;
    let meta_json = serde_json::to_string(&meta)
        .map_err(|e| format!("Serialization error: {}", e))?;

    let sv_before = doc.transact().state_vector();
    let mut txn = doc.transact_mut();
    manifest.insert(&mut txn, file_id, meta_json);
    let update = txn.encode_diff_v1(&sv_before);
    drop(txn);

    save_snapshot_sync(&doc, group_id);
    Ok(update)
}

/// Get the text content of a specific file.
pub async fn get_file_text(group_id: &str, file_id: &str) -> Result<String, String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;
    let text = doc.get_or_insert_text(format!("file_{}", file_id));
    let result = text.get_string(&doc.transact());
    Ok(result)
}

/// Apply a local edit to a specific file and return the incremental update blob.
pub async fn apply_file_edit(
    group_id: &str,
    file_id: &str,
    index: u32,
    delete_count: u32,
    insert_text: &str,
) -> Result<Vec<u8>, String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;

    let text = doc.get_or_insert_text(format!("file_{}", file_id));
    let mut txn = doc.transact_mut();

    let sv_before = txn.state_vector();

    if delete_count > 0 {
        text.remove_range(&mut txn, index, delete_count);
    }
    if !insert_text.is_empty() {
        text.insert(&mut txn, index, insert_text);
    }

    let update = txn.encode_diff_v1(&sv_before);
    drop(txn);

    save_snapshot_sync(&doc, group_id);

    Ok(update)
}

/// Apply a remote update to the document and save.
pub async fn apply_remote_update(group_id: &str, update_bytes: &[u8]) -> Result<(), String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;

    match Update::decode_v1(update_bytes) {
        Ok(update) => {
            let mut txn = doc.transact_mut();
            let _ = txn.apply_update(update);
            drop(txn);
            save_snapshot_sync(&doc, group_id);
            Ok(())
        }
        Err(e) => Err(format!("Failed to decode update: {:?}", e)),
    }
}

/// Encode the state vector to send to peers (Sync Step 1)
pub async fn encode_state_vector(group_id: &str) -> Result<Vec<u8>, String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;
    let txn = doc.transact();
    Ok(txn.state_vector().encode_v1())
}

/// Encode the missing differences based on a remote peer's state vector (Sync Step 2)
pub async fn encode_diff(group_id: &str, remote_sv_bytes: &[u8]) -> Result<Vec<u8>, String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;

    match StateVector::decode_v1(remote_sv_bytes) {
        Ok(sv) => {
            let txn = doc.transact();
            Ok(txn.encode_diff_v1(&sv))
        }
        Err(e) => Err(format!("Failed to decode state vector: {:?}", e)),
    }
}
