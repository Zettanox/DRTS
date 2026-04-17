use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;
use yrs::{Doc, GetString, ReadTxn, StateVector, Text, Transact, Update};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use lazy_static::lazy_static;

lazy_static! {
    static ref ACTIVE_DOCS: Mutex<HashMap<String, Arc<Mutex<Doc>>>> = Mutex::new(HashMap::new());
}

fn get_storage_path(group_id: &str) -> PathBuf {
    let mut path = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
    path.push(".stoa");
    path.push("groups");
    fs::create_dir_all(&path).unwrap_or_default();
    path.push(format!("{}.yrs", group_id));
    path
}

/// Load a document from disk or create a new one, keeping it in memory.
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
                txn.apply_update(update);
            } else {
                eprintln!("[Stoa CRDT] Failed to decode existing doc for group {}", group_id);
            }
        }
    } else {
        // Initialize with empty text if it's new
        let text = doc.get_or_insert_text("content");
        let mut txn = doc.transact_mut();
        text.insert(&mut txn, 0, "");
        drop(txn);
        save_snapshot_sync(&doc, group_id);
    }

    let arc_doc = Arc::new(Mutex::new(doc));
    docs.insert(group_id.to_string(), arc_doc.clone());

    Ok(arc_doc)
}

/// Save a document snapshot to disk.
pub async fn save_snapshot(group_id: &str) {
    let docs = ACTIVE_DOCS.lock().await;
    if let Some(doc_mutex) = docs.get(group_id) {
        let doc = doc_mutex.lock().await;
        save_snapshot_sync(&doc, group_id);
    }
}

fn save_snapshot_sync(doc: &Doc, group_id: &str) {
    let path = get_storage_path(group_id);
    let txn = doc.transact();
    let sv = StateVector::default(); // empty sv returns full document
    let data = txn.encode_diff_v1(&sv);
    if let Err(e) = fs::write(&path, data) {
        eprintln!("[Stoa CRDT] Failed to save snapshot for {}: {}", group_id, e);
    }
}

/// Apply a remote update to the document and save.
pub async fn apply_remote_update(group_id: &str, update_bytes: &[u8]) -> Result<(), String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;

    match Update::decode_v1(update_bytes) {
        Ok(update) => {
            let mut txn = doc.transact_mut();
            txn.apply_update(update);
            drop(txn);
            save_snapshot_sync(&doc, group_id);
            Ok(())
        }
        Err(e) => Err(format!("Failed to decode update: {:?}", e)),
    }
}

/// Get the current text of the document.
pub async fn get_text(group_id: &str) -> Result<String, String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;
    let text = doc.get_or_insert_text("content");
    let result = text.get_string(&doc.transact());
    Ok(result)
}

/// Apply a local edit (insert/delete) and return the incremental update blob.
pub async fn apply_local_edit(
    group_id: &str,
    index: u32,
    delete_count: u32,
    insert_text: &str,
) -> Result<Vec<u8>, String> {
    let doc_mutex = load_or_create_doc(group_id).await?;
    let doc = doc_mutex.lock().await;

    let text = doc.get_or_insert_text("content");
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
