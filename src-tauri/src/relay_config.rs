//! relay_config.rs — Relay server configuration: load, save, and default relay management.
//!
//! Config is persisted at ~/.stoa/relay_config.json. On first run the file is created
//! with a single hard-coded default relay entry so users work out of the box.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// The default relay address built into the app.
/// Replace this with your actual deployed relay multiaddr + PeerId.
/// Format: /ip4/<HOST>/tcp/<PORT>/p2p/<PEERID>
pub const DEFAULT_RELAY: &str =
    "/ip4/129.159.17.16/tcp/38291/p2p/12D3KooWDQHjWkGS9pxUQQeii7prryA5T1LzZP6cMMU128cas658";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelayEntry {
    /// Human-readable label (e.g. "Default Stoa Relay")
    pub label: String,
    /// Full multiaddr including /p2p/<PeerID>
    pub address: String,
    /// Whether to auto-connect to this relay on startup
    pub enabled: bool,
}

impl RelayEntry {
    pub fn new(label: impl Into<String>, address: impl Into<String>) -> Self {
        Self {
            label: label.into(),
            address: address.into(),
            enabled: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelayConfig {
    pub relays: Vec<RelayEntry>,
}

impl Default for RelayConfig {
    fn default() -> Self {
        Self {
            relays: vec![RelayEntry::new("Default Stoa Relay", DEFAULT_RELAY)],
        }
    }
}

fn config_path() -> PathBuf {
    crate::get_stoa_dir().join("relay_config.json")
}

impl RelayConfig {
    pub fn load() -> Self {
        let path = config_path();
        if path.exists() {
            if let Ok(data) = std::fs::read_to_string(&path) {
                if let Ok(mut cfg) = serde_json::from_str::<RelayConfig>(&data) {
                    // Auto-migrate the old default relay port if the user already has a saved config
                    let old_relay = "/ip4/129.159.17.16/tcp/4001/p2p/12D3KooWDQHjWkGS9pxUQQeii7prryA5T1LzZP6cMMU128cas658";
                    let mut migrated = false;
                    for r in &mut cfg.relays {
                        if r.address == old_relay {
                            r.address = DEFAULT_RELAY.to_string();
                            migrated = true;
                        }
                    }
                    if migrated {
                        let _ = cfg.save();
                    }
                    return cfg;
                }
            }
        }
        // First run or corrupt file — return defaults and persist them
        let cfg = RelayConfig::default();
        let _ = cfg.save(); // best-effort
        cfg
    }

    pub fn save(&self) -> Result<(), String> {
        let path = config_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create config dir: {e}"))?;
        }
        let json = serde_json::to_string_pretty(self)
            .map_err(|e| format!("Failed to serialize relay config: {e}"))?;
        std::fs::write(&path, json).map_err(|e| format!("Failed to write relay config: {e}"))
    }

    /// Return multiaddrs of all enabled relay entries.
    pub fn enabled_addresses(&self) -> Vec<String> {
        self.relays
            .iter()
            .filter(|r| r.enabled && !r.address.is_empty())
            .map(|r| r.address.clone())
            .collect()
    }
}
