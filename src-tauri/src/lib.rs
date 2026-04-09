mod identity;
mod network;

use identity::IdentityInfo;
use libp2p::identity::Keypair;
use network::{NearbyPeer, NearbyPeersMap, NetworkCommand};
use std::sync::Arc;
use tauri::{Manager, State};
use tokio::sync::{mpsc, Mutex};

/// Shared application state managed by Tauri.
pub struct AppState {
    pub identity_info: Arc<Mutex<Option<IdentityInfo>>>,
    pub keypair: Arc<Mutex<Option<Keypair>>>,
    pub network_cmd_tx: Arc<Mutex<Option<mpsc::Sender<NetworkCommand>>>>,
    pub nearby_peers: Arc<Mutex<Option<NearbyPeersMap>>>,
    pub lan_visible: Arc<Mutex<bool>>,
}

/// Helper: start the network and store handles in state.
async fn start_network(
    keypair: &Keypair,
    app_handle: &tauri::AppHandle,
    state: &AppState,
) -> Result<(), String> {
    let (cmd_tx, peers_map) = network::spawn_network(keypair.clone(), app_handle.clone())?;
    {
        let mut tx = state.network_cmd_tx.lock().await;
        *tx = Some(cmd_tx);
    }
    {
        let mut np = state.nearby_peers.lock().await;
        *np = Some(peers_map);
    }
    Ok(())
}

/// Helper: stop the network task and clear state.
async fn stop_network(state: &AppState) {
    // Send shutdown command
    let tx = {
        let mut tx_guard = state.network_cmd_tx.lock().await;
        tx_guard.take()
    };
    if let Some(tx) = tx {
        let _ = tx.send(NetworkCommand::Shutdown).await;
    }
    // Clear peers map
    {
        let mut np = state.nearby_peers.lock().await;
        *np = None;
    }
}

// ─── Tauri Commands ───────────────────────────────────────────────────────────

/// Generate (or load existing) identity and start the network node.
#[tauri::command]
async fn generate_identity(
    app_handle: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<IdentityInfo, String> {
    let (keypair, info) = identity::load_or_create_identity()?;

    // Store identity info and keypair
    {
        let mut id = state.identity_info.lock().await;
        *id = Some(info.clone());
    }
    {
        let mut kp = state.keypair.lock().await;
        *kp = Some(keypair.clone());
    }

    // Start network if not already running
    {
        let existing = state.network_cmd_tx.lock().await;
        if existing.is_some() {
            return Ok(info);
        }
    }

    start_network(&keypair, &app_handle, &state).await?;
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
    {
        let mut kp = state.keypair.lock().await;
        *kp = Some(keypair.clone());
    }

    // Start network if not already running
    {
        let existing = state.network_cmd_tx.lock().await;
        if existing.is_none() {
            drop(existing);
            start_network(&keypair, &app_handle, &state).await?;
        }
    }

    Ok(Some(info))
}

/// Export the keypair as a base64 string for cross-platform portability.
#[tauri::command]
async fn export_keypair() -> Result<String, String> {
    identity::export_keypair_base64()
}

/// Toggle LAN visibility by killing or respawning the mDNS network task.
/// OFF = kill the network (stops broadcasting, peers expire via TTL on other devices)
/// ON  = respawn the network (starts broadcasting, discovered instantly by others)
#[tauri::command]
async fn toggle_visibility(
    visible: bool,
    app_handle: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    {
        let mut v = state.lan_visible.lock().await;
        *v = visible;
    }

    if visible {
        // Respawn the network
        let keypair = {
            let kp = state.keypair.lock().await;
            kp.clone().ok_or("No keypair available")?
        };
        // Stop any existing network first
        stop_network(&state).await;
        start_network(&keypair, &app_handle, &state).await?;
        println!("[Stoa Network] Visibility ON — network respawned");
    } else {
        // Kill the network entirely
        stop_network(&state).await;
        println!("[Stoa Network] Visibility OFF — network stopped");
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

/// Show the main window (called by frontend when ready).
#[tauri::command]
async fn show_window(app_handle: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app_handle.get_webview_window("main") {
        window.show().map_err(|e| format!("Failed to show window: {e}"))?;
    }
    Ok(())
}

// ─── App Entry ────────────────────────────────────────────────────────────────

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(AppState {
            identity_info: Arc::new(Mutex::new(None)),
            keypair: Arc::new(Mutex::new(None)),
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
            show_window,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
