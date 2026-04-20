use base64::{engine::general_purpose::STANDARD as B64, Engine};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

/// Size of each chunk in bytes (64 KB — relay-friendly).
pub const CHUNK_SIZE: usize = 64 * 1024;

/// Maximum number of chunks to fetch concurrently (the pipeline window).
/// Kept small for reliable relay circuit transfers.
pub const MAX_WINDOW_SIZE: u32 = 4;

/// Direction of a file transfer.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TransferDirection {
    Upload,
    Download,
}

/// Status of a file transfer.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TransferStatus {
    Offering,
    Transferring,
    Paused,
    Complete,
    Failed,
    Cancelled,
}

/// Represents an active file transfer stream without loading it fully into RAM.
#[derive(Debug, Clone)]
pub struct ActiveTransfer {
    pub transfer_id: String,
    pub peer_id: String,
    pub file_name: String,
    pub file_size: u64,
    pub checksum: String,
    pub chunk_count: u32,
    pub chunks_done: u32,
    pub direction: TransferDirection,
    pub status: TransferStatus,
    /// Path to read from (Sender) or write to (Receiver)
    pub file_path: PathBuf,
    /// For downloads: keep track of exactly which chunks are written to disk
    pub received_chunks_set: HashSet<u32>,
    /// For pipelining logic
    pub last_requested_chunk: Option<u32>,
    /// If set, this transfer belongs to a group
    pub group_id: Option<String>,
}

/// Prepares a file for transfer by calculating its checksum without freezing the main thread.
pub async fn prepare_file_off_thread(
    path: PathBuf,
) -> Result<(String, u64, String, u32), String> {
    tokio::task::spawn_blocking(move || {
        let file = File::open(&path).map_err(|e| format!("Failed to open file: {e}"))?;
        let metadata = file.metadata().map_err(|e| format!("Failed to read metadata: {e}"))?;
        let file_size = metadata.len();
        
        let file_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();

        let chunk_count = if file_size == 0 {
            0
        } else {
            ((file_size + (CHUNK_SIZE as u64) - 1) / (CHUNK_SIZE as u64)) as u32
        };

        // Compute SHA-256 streamingly
        let mut hasher = Sha256::new();
        let mut f = file;
        let mut buffer = vec![0u8; 1024 * 1024]; // 1MB buffer for hashing
        loop {
            let n = f.read(&mut buffer).map_err(|e| format!("Read error: {e}"))?;
            if n == 0 {
                break;
            }
            hasher.update(&buffer[..n]);
        }
        let checksum = hex::encode(hasher.finalize());

        Ok((file_name, file_size, checksum, chunk_count))
    })
    .await
    .map_err(|e| format!("Task failed: {e}"))?
}

/// Verify a file's SHA-256 checksum after download is complete.
pub async fn verify_file_off_thread(
    path: PathBuf,
    expected_checksum: String,
) -> Result<bool, String> {
    tokio::task::spawn_blocking(move || {
        let mut file = File::open(&path).map_err(|e| format!("Failed to open file: {e}"))?;
        let mut hasher = Sha256::new();
        let mut buffer = vec![0u8; 1024 * 1024];
        loop {
            let n = file.read(&mut buffer).map_err(|e| format!("Read error: {e}"))?;
            if n == 0 {
                break;
            }
            hasher.update(&buffer[..n]);
        }
        let actual = hex::encode(hasher.finalize());
        Ok(actual == expected_checksum)
    })
    .await
    .map_err(|e| format!("Task failed: {e}"))?
}

/// Read exactly one chunk from disk and base64-encode it (Sender).
pub fn read_chunk(path: &Path, chunk_index: u32) -> Result<String, String> {
    let mut file = File::open(path).map_err(|e| format!("Cannot open file: {e}"))?;
    let offset = (chunk_index as u64) * (CHUNK_SIZE as u64);
    file.seek(SeekFrom::Start(offset)).map_err(|e| format!("Seek failed: {e}"))?;

    let mut buffer = vec![0u8; CHUNK_SIZE];
    let n = file.read(&mut buffer).map_err(|e| format!("Read chunk failed: {e}"))?;
    
    buffer.truncate(n);
    Ok(B64.encode(&buffer))
}

/// Write exactly one chunk to disk and ensure directories exist (Receiver).
pub fn write_chunk(path: &Path, chunk_index: u32, data_b64: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create directory: {e}"))?;
    }

    let data = B64.decode(data_b64).map_err(|e| format!("Decode failed: {e}"))?;
    let mut file = OpenOptions::new()
        .write(true)
        .create(true) // will create sparse file on linux
        .open(path)
        .map_err(|e| format!("Failed to open dest file: {e}"))?;
        
    let offset = (chunk_index as u64) * (CHUNK_SIZE as u64);
    file.seek(SeekFrom::Start(offset)).map_err(|e| format!("Seek failed: {e}"))?;
    file.write_all(&data).map_err(|e| format!("Write failed: {e}"))?;
    
    Ok(())
}

/// Get the received files directory for a given sender.
pub fn received_dir(sender_peer_id: &str) -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".stoa")
        .join("received")
        .join(sender_peer_id)
}
