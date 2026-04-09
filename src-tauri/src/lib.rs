mod identity;
mod network;

use identity::IdentityInfo;
use network::{NearbyPeer, NearbyPeersMap, NetworkCommand};
use std::sync::Arc;
use tauri::State;
use tokio::sync::{mpsc, Mutex};

/// Shared application state managed by Tauri.
pub struct AppState {
    pub identity_info: Arc<Mutex<Option<IdentityInfo>>>,
    pub network_cmd_tx: Arc<Mutex<Option<mpsc::Sender<NetworkCommand>>>>,
    pub nearby_peers: Arc<Mutex<Option<NearbyPeersMap>>>,
    pub lan_visible: Arc<Mutex<bool>>,
}

// ─── Tauri Commands ───────────────────────────────────────────────────────────

/// Generate (or load existing) identity and start the network node.
#[tauri::command]
async fn generate_identity(
    app_handle: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<IdentityInfo, String> {
    let (keypair, info) = identity::load_or_create_identity()?;

    // Store identity info
    {
        let mut id = state.identity_info.lock().await;
        *id = Some(info.clone());
    }

    // Start network if not already running
    {
        let existing = state.network_cmd_tx.lock().await;
        if existing.is_some() {
            return Ok(info);
        }
    }

    let (cmd_tx, peers_map) = network::spawn_network(keypair, app_handle)?;

    {
        let mut tx = state.network_cmd_tx.lock().await;
        *tx = Some(cmd_tx);
    }
    {
        let mut np = state.nearby_peers.lock().await;
        *np = Some(peers_map);
    }

    Ok(info)
}

/// Get the current identity info (if generated). Tries disk if not in memory.
#[tauri::command]
async fn get_identity(
    app_handle: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<Option<IdentityInfo>, String> {
    // Check in-memory first
    {
        let id = state.identity_info.lock().await;
        if id.is_some() {
            return Ok(id.clone());
        }
    }

    // Try loading from disk
    let path = dirs::home_dir()
        .ok_or("No home dir")?
        .join(".stoa")
        .join("identity.json");

    if !path.exists() {
        return Ok(None);
    }

    // Load identity and start network
    let (keypair, info) = identity::load_or_create_identity()?;

    {
        let mut id = state.identity_info.lock().await;
        *id = Some(info.clone());
    }

    // Start network if not already running
    {
        let existing = state.network_cmd_tx.lock().await;
        if existing.is_none() {
            drop(existing);
            let (cmd_tx, peers_map) = network::spawn_network(keypair, app_handle)?;
            {
                let mut tx = state.network_cmd_tx.lock().await;
                *tx = Some(cmd_tx);
            }
            {
                let mut np = state.nearby_peers.lock().await;
                *np = Some(peers_map);
            }
        }
    }

    Ok(Some(info))
}

/// Export the keypair as a base64 string for cross-platform portability.
#[tauri::command]
async fn export_keypair() -> Result<String, String> {
    identity::export_keypair_base64()
}

/// Toggle LAN visibility (mDNS on/off).
#[tauri::command]
async fn toggle_visibility(
    visible: bool,
    state: State<'_, AppState>,
) -> Result<(), String> {
    {
        let mut v = state.lan_visible.lock().await;
        *v = visible;
    }

    let tx_guard = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx_guard.as_ref() {
        tx.send(NetworkCommand::SetVisibility(visible))
            .await
            .map_err(|e| format!("Failed to send visibility command: {e}"))?;
    }
    Ok(())
}

/// Get the current list of nearby LAN peers.
#[tauri::command]
async fn get_nearby_peers(state: State<'_, AppState>) -> Result<Vec<NearbyPeer>, String> {
    let np_guard = state.nearby_peers.lock().await;
    if let Some(peers_map) = np_guard.as_ref() {
        let peers = peers_map.lock().await;
        Ok(peers.values().cloned().collect())
    } else {
        Ok(vec![])
    }
}

/// Get current LAN visibility status.
#[tauri::command]
async fn get_visibility(state: State<'_, AppState>) -> Result<bool, String> {
    let v = state.lan_visible.lock().await;
    Ok(*v)
}

// ─── App Entry ────────────────────────────────────────────────────────────────

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(AppState {
            identity_info: Arc::new(Mutex::new(None)),
            network_cmd_tx: Arc::new(Mutex::new(None)),
            nearby_peers: Arc::new(Mutex::new(None)),
            lan_visible: Arc::new(Mutex::new(true)),
        })
        .invoke_handler(tauri::generate_handler![
            generate_identity,
            get_identity,
            export_keypair,
            toggle_visibility,
            get_visibility,
            get_nearby_peers,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
