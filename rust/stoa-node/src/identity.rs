use anyhow::Result;
use iroh::SecretKey;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::RwLock;
use tracing::info;

const KEY_FILENAME: &str = "stoa_identity.key";
const PROFILE_FILENAME: &str = "stoa_profile.json";

/// Persistent identity for a Stoa node.
/// Manages the Ed25519 keypair and user profile.
/// Interior-mutable so it can live behind an Arc.
pub struct StoaIdentity {
    secret_key: SecretKey,
    display_name: RwLock<String>,
    data_dir: PathBuf,
}

impl StoaIdentity {
    /// Load an existing identity from `data_dir`, or generate a new one.
    pub fn load_or_create(data_dir: &Path) -> Result<Self> {
        fs::create_dir_all(data_dir)?;
        let key_path = data_dir.join(KEY_FILENAME);
        let profile_path = data_dir.join(PROFILE_FILENAME);

        // Load or generate secret key
        let secret_key = if key_path.exists() {
            let bytes = fs::read(&key_path)?;
            if bytes.len() != 32 {
                anyhow::bail!("Corrupt identity file: expected 32 bytes, got {}", bytes.len());
            }
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&bytes);
            let key = SecretKey::from_bytes(&arr);
            info!("Loaded existing identity: {}", key.public());
            key
        } else {
            let key = SecretKey::generate(&mut rand::rng());
            fs::write(&key_path, key.to_bytes())?;
            info!("Generated new identity: {}", key.public());
            key
        };

        // Load or create profile
        let display_name = if profile_path.exists() {
            let json = fs::read_to_string(&profile_path)?;
            let profile: Profile = serde_json::from_str(&json)
                .unwrap_or(Profile { display_name: String::new() });
            profile.display_name
        } else {
            String::new()
        };

        Ok(Self {
            secret_key,
            display_name: RwLock::new(display_name),
            data_dir: data_dir.to_path_buf(),
        })
    }

    pub fn secret_key(&self) -> &SecretKey {
        &self.secret_key
    }

    pub fn node_id(&self) -> String {
        self.secret_key.public().to_string()
    }

    pub fn display_name(&self) -> String {
        self.display_name.read()
            .map(|n| n.clone())
            .unwrap_or_default()
    }

    /// Set the display name. Persists to disk immediately.
    pub fn set_display_name(&self, name: String) -> Result<()> {
        let profile = Profile { display_name: name.clone() };
        let json = serde_json::to_string_pretty(&profile)?;
        fs::write(self.data_dir.join(PROFILE_FILENAME), json)?;
        let mut guard = self.display_name.write()
            .map_err(|e| anyhow::anyhow!("Lock poisoned: {e}"))?;
        *guard = name;
        Ok(())
    }
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Profile {
    display_name: String,
}
