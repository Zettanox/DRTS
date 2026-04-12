use base64::{engine::general_purpose::STANDARD as B64, Engine};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Size of each chunk in bytes (256 KB).
pub const CHUNK_SIZE: usize = 256 * 1024;

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
    Complete,
    Failed,
    Cancelled,
}

/// Represents an active file transfer (upload or download).
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
    /// For uploads: all chunks ready to send (base64 encoded)
    pub chunks: Vec<String>,
    /// For downloads: received chunks stored by index
    pub received_chunks: HashMap<u32, Vec<u8>>,
    /// For downloads: where to save the assembled file
    pub dest_path: PathBuf,
}

/// Read a file from disk, compute SHA-256, split into base64-encoded chunks.
pub fn prepare_file_for_transfer(
    path: &Path,
) -> Result<(String, u64, String, Vec<String>), String> {
    let data =
        std::fs::read(path).map_err(|e| format!("Failed to read file: {e}"))?;
    let file_size = data.len() as u64;

    // SHA-256 checksum
    let mut hasher = Sha256::new();
    hasher.update(&data);
    let checksum = hex::encode(hasher.finalize());

    // Split into chunks and base64-encode
    let chunks: Vec<String> = data
        .chunks(CHUNK_SIZE)
        .map(|chunk| B64.encode(chunk))
        .collect();

    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_string();

    Ok((file_name, file_size, checksum, chunks))
}

/// Assemble received chunks into a file, verify checksum, save to disk.
pub fn assemble_and_save(
    transfer: &ActiveTransfer,
) -> Result<PathBuf, String> {
    // Ensure destination directory exists
    if let Some(parent) = transfer.dest_path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create directory: {e}"))?;
    }

    // Assemble chunks in order
    let mut assembled = Vec::with_capacity(transfer.file_size as usize);
    for i in 0..transfer.chunk_count {
        let chunk_data = transfer
            .received_chunks
            .get(&i)
            .ok_or_else(|| format!("Missing chunk {i}"))?;
        assembled.extend_from_slice(chunk_data);
    }

    // Verify checksum
    let mut hasher = Sha256::new();
    hasher.update(&assembled);
    let actual = hex::encode(hasher.finalize());
    if actual != transfer.checksum {
        return Err(format!(
            "Checksum mismatch: expected {}, got {}",
            transfer.checksum, actual
        ));
    }

    // Write to disk
    std::fs::write(&transfer.dest_path, &assembled)
        .map_err(|e| format!("Failed to write file: {e}"))?;

    println!(
        "[Stoa File] Saved {} ({} bytes) to {:?}",
        transfer.file_name,
        assembled.len(),
        transfer.dest_path
    );

    Ok(transfer.dest_path.clone())
}

/// Get the received files directory for a given sender.
pub fn received_dir(sender_peer_id: &str) -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".stoa")
        .join("received")
        .join(sender_peer_id)
}

/// Format file size for display.
pub fn format_size(bytes: u64) -> String {
    if bytes < 1024 {
        format!("{bytes} B")
    } else if bytes < 1024 * 1024 {
        format!("{:.1} KB", bytes as f64 / 1024.0)
    } else if bytes < 1024 * 1024 * 1024 {
        format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0))
    } else {
        format!("{:.2} GB", bytes as f64 / (1024.0 * 1024.0 * 1024.0))
    }
}
