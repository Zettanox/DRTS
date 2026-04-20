use base64::{engine::general_purpose::STANDARD as B64, Engine};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

// ─── Transfer Parameters ──────────────────────────────────────────────────────

/// LAN transfers: fast direct TCP, aggressive pipeline.
pub const LAN_CHUNK_SIZE: usize = 256 * 1024;   // 256 KB (original, proven stable for 3GB+ files)
pub const LAN_WINDOW_SIZE: u32 = 20;

/// Relay transfers: conservative, circuit-friendly.
pub const RELAY_CHUNK_SIZE: usize = 64 * 1024;   // 64 KB
pub const RELAY_WINDOW_SIZE: u32 = 4;

// ─── Transfer Types ───────────────────────────────────────────────────────────

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
    /// Chunk size in bytes as negotiated in the FileOffer
    pub chunk_size: usize,
}

// ─── File Preparation ─────────────────────────────────────────────────────────

/// Prepares a file for transfer by calculating its checksum without freezing the main thread.
/// `chunk_size` determines the chunk granularity (LAN or Relay).
pub async fn prepare_file_off_thread(
    path: PathBuf,
    chunk_size: usize,
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
            ((file_size + (chunk_size as u64) - 1) / (chunk_size as u64)) as u32
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

// ─── Chunk I/O ────────────────────────────────────────────────────────────────

/// Read exactly one chunk from disk and base64-encode it (Sender).
pub fn read_chunk(path: &Path, chunk_index: u32, chunk_size: usize) -> Result<String, String> {
    let mut file = File::open(path).map_err(|e| format!("Cannot open file: {e}"))?;
    let offset = (chunk_index as u64) * (chunk_size as u64);
    file.seek(SeekFrom::Start(offset)).map_err(|e| format!("Seek failed: {e}"))?;

    let mut buffer = vec![0u8; chunk_size];
    let n = file.read(&mut buffer).map_err(|e| format!("Read chunk failed: {e}"))?;
    
    buffer.truncate(n);
    Ok(B64.encode(&buffer))
}

/// Write exactly one chunk to disk and ensure directories exist (Receiver).
pub fn write_chunk(path: &Path, chunk_index: u32, data_b64: &str, chunk_size: usize) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create directory: {e}"))?;
    }

    let data = B64.decode(data_b64).map_err(|e| format!("Decode failed: {e}"))?;
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false) // CRITICAL: must not truncate — we write chunks out-of-order
        .open(path)
        .map_err(|e| format!("Failed to open dest file: {e}"))?;
        
    let offset = (chunk_index as u64) * (chunk_size as u64);
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
