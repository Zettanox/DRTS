mod contacts;
mod crypto;
mod file_transfer;
mod groups;
mod identity;
mod messages;
mod network;
mod protocol;

use contacts::Contact;
use identity::IdentityInfo;
use libp2p::identity::Keypair;
use messages::StoredMessage;
use network::{ContactsList, NearbyPeer, NearbyPeersMap, NetworkCommand};
use std::sync::Arc;
use tauri::{Manager, State};
use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

/// Shared application state managed by Tauri.
pub struct AppState {
    pub identity_info: Arc<Mutex<Option<IdentityInfo>>>,
    pub keypair: Arc<Mutex<Option<Keypair>>>,
    pub network_cmd_tx: Arc<Mutex<Option<mpsc::Sender<NetworkCommand>>>>,
    pub network_handle: Arc<Mutex<Option<JoinHandle<()>>>>,
    pub nearby_peers: Arc<Mutex<Option<NearbyPeersMap>>>,
    pub contacts: ContactsList,
    pub lan_visible: Arc<Mutex<bool>>,
}

/// Helper: start the network and store handles in state.
async fn start_network(
    keypair: &Keypair,
    app_handle: &tauri::AppHandle,
    state: &AppState,
) -> Result<(), String> {
    let our_name = {
        let info = state.identity_info.lock().await;
        info.as_ref().map(|i| i.name.clone()).unwrap_or_else(|| "User".to_string())
    };
    let (cmd_tx, peers_map, handle) =
        network::spawn_network(keypair.clone(), app_handle.clone(), state.contacts.clone(), our_name)?;
    {
        let mut tx = state.network_cmd_tx.lock().await;
        *tx = Some(cmd_tx);
    }
    {
        let mut np = state.nearby_peers.lock().await;
        *np = Some(peers_map);
    }
    {
        let mut h = state.network_handle.lock().await;
        *h = Some(handle);
    }
    Ok(())
}

/// Helper: stop the network task and wait for clean shutdown (used on app exit).
#[allow(dead_code)]
async fn stop_network(state: &AppState) {
    // Send shutdown command
    let tx = {
        let mut tx_guard = state.network_cmd_tx.lock().await;
        tx_guard.take()
    };
    if let Some(tx) = tx {
        let _ = tx.send(NetworkCommand::Shutdown).await;
    }

    // Wait for the task to finish (prevents use-after-free on swarm drop)
    let handle = {
        let mut h = state.network_handle.lock().await;
        h.take()
    };
    if let Some(handle) = handle {
        // Give it 2 seconds max to shut down gracefully
        let _ = tokio::time::timeout(
            std::time::Duration::from_secs(2),
            handle,
        ).await;
    }

    {
        let mut np = state.nearby_peers.lock().await;
        *np = None;
    }
}

// ─── Identity Commands ────────────────────────────────────────────────────────

#[tauri::command]
async fn generate_identity(
    app_handle: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<IdentityInfo, String> {
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
        if existing.is_some() {
            return Ok(info);
        }
    }

    start_network(&keypair, &app_handle, &state).await?;
    Ok(info)
}

#[tauri::command]
async fn get_identity(
    app_handle: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<Option<IdentityInfo>, String> {
    {
        let id = state.identity_info.lock().await;
        if id.is_some() {
            return Ok(id.clone());
        }
    }

    let path = dirs::home_dir()
        .ok_or("No home dir")?
        .join(".stoa")
        .join("identity.json");

    if !path.exists() {
        return Ok(None);
    }

    let (keypair, info) = identity::load_or_create_identity()?;

    {
        let mut id = state.identity_info.lock().await;
        *id = Some(info.clone());
    }
    {
        let mut kp = state.keypair.lock().await;
        *kp = Some(keypair.clone());
    }

    {
        let existing = state.network_cmd_tx.lock().await;
        if existing.is_none() {
            drop(existing);
            start_network(&keypair, &app_handle, &state).await?;
        }
    }

    Ok(Some(info))
}

#[tauri::command]
async fn export_keypair() -> Result<String, String> {
    identity::export_keypair_base64()
}

// ─── Visibility Commands ──────────────────────────────────────────────────────

#[tauri::command]
async fn toggle_visibility(
    visible: bool,
    state: State<'_, AppState>,
) -> Result<(), String> {
    {
        let mut v = state.lan_visible.lock().await;
        *v = visible;
    }

    // Send visibility command to the running network task
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        tx.send(NetworkCommand::SetVisibility(visible))
            .await
            .map_err(|e| format!("Failed to send visibility command: {e}"))?;
    }

    Ok(())
}

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

#[tauri::command]
async fn get_visibility(state: State<'_, AppState>) -> Result<bool, String> {
    let v = state.lan_visible.lock().await;
    Ok(*v)
}

#[tauri::command]
async fn show_window(app_handle: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app_handle.get_webview_window("main") {
        window
            .show()
            .map_err(|e| format!("Failed to show window: {e}"))?;
    }
    Ok(())
}

// ─── Contact Commands ─────────────────────────────────────────────────────────

#[tauri::command]
async fn get_contacts(state: State<'_, AppState>) -> Result<Vec<Contact>, String> {
    let cts = state.contacts.lock().await;
    Ok(cts.clone())
}

#[tauri::command]
async fn send_contact_request(
    peer_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let (our_peer_id, our_name) = {
        let info = state.identity_info.lock().await;
        let info = info.as_ref().ok_or("No identity")?;
        (info.peer_id.clone(), info.name.clone())
    };

    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        tx.send(NetworkCommand::SendContactRequest {
            peer_id,
            our_name,
            our_peer_id,
        })
        .await
        .map_err(|e| format!("Failed to send contact request: {e}"))?;
    }
    Ok(())
}

#[tauri::command]
async fn respond_contact_request(
    peer_id: String,
    accept: bool,
    petname: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    if accept {
        let mut cts = state.contacts.lock().await;
        contacts::add_contact(&mut cts, peer_id, petname)?;
    }
    Ok(())
}

#[tauri::command]
async fn add_contact_from_request(
    peer_id: String,
    petname: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let mut cts = state.contacts.lock().await;
    contacts::add_contact(&mut cts, peer_id, petname)
}

#[tauri::command]
async fn rename_contact(
    peer_id: String,
    new_name: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let mut cts = state.contacts.lock().await;
    contacts::rename_contact(&mut cts, &peer_id, new_name)
}

#[tauri::command]
async fn remove_contact_cmd(
    peer_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let mut cts = state.contacts.lock().await;
    contacts::remove_contact(&mut cts, &peer_id)
}

// ─── Messaging Commands ──────────────────────────────────────────────────────

#[tauri::command]
async fn send_message(
    peer_id: String,
    content: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let message_id = uuid::Uuid::new_v4().to_string();
    let sender_name = {
        let info = state.identity_info.lock().await;
        info.as_ref().map(|i| i.name.clone()).unwrap_or_default()
    };

    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        tx.send(NetworkCommand::SendMessage {
            peer_id,
            message_id: message_id.clone(),
            content,
            sender_name,
        })
        .await
        .map_err(|e| format!("Failed to send message: {e}"))?;
    }
    Ok(message_id)
}

#[tauri::command]
async fn get_chat_history(peer_id: String) -> Result<Vec<StoredMessage>, String> {
    messages::get_chat_history(&peer_id)
}

#[tauri::command]
async fn set_username(
    new_name: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let info = identity::update_identity_name(&new_name)?;
    {
        let mut id = state.identity_info.lock().await;
        *id = Some(info.clone());
    }
    Ok(info.name)
}

// ─── File Transfer Commands ───────────────────────────────────────────────────

#[tauri::command]
async fn send_file(
    peer_id: String,
    file_path: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let sender_name = {
        let info = state.identity_info.lock().await;
        info.as_ref().map(|i| i.name.clone()).unwrap_or_default()
    };

    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        tx.send(NetworkCommand::SendFile {
            peer_id,
            file_path,
            sender_name,
        })
        .await
        .map_err(|e| format!("Failed to send file: {e}"))?;
    }
    Ok(())
}

#[tauri::command]
async fn pause_transfer(
    transfer_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::PauseTransfer { transfer_id }).await;
    }
    Ok(())
}

#[tauri::command]
async fn resume_transfer(
    transfer_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::ResumeTransfer { transfer_id }).await;
    }
    Ok(())
}

// ─── Group Commands ──────────────────────────────────────────────────────────

#[tauri::command]
async fn create_group(
    name: String,
    member_ids: Vec<String>,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        tx.send(NetworkCommand::CreateGroup { name, member_ids })
            .await
            .map_err(|e| format!("Failed to create group: {e}"))?;
    }
    Ok("ok".into())
}

#[tauri::command]
async fn get_groups() -> Result<Vec<groups::Group>, String> {
    groups::load_groups()
}

#[tauri::command]
async fn send_group_message(
    group_id: String,
    content: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let message_id = uuid::Uuid::new_v4().to_string();
    let sender_name = {
        let info = state.identity_info.lock().await;
        info.as_ref().map(|i| i.name.clone()).unwrap_or_default()
    };

    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        tx.send(NetworkCommand::SendGroupMessage {
            group_id,
            message_id: message_id.clone(),
            content,
            sender_name,
        })
        .await
        .map_err(|e| format!("Failed to send group message: {e}"))?;
    }
    Ok(message_id)
}

#[tauri::command]
async fn send_group_file(
    group_id: String,
    file_path: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let sender_name = {
        let info = state.identity_info.lock().await;
        info.as_ref().map(|i| i.name.clone()).unwrap_or_default()
    };

    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        tx.send(NetworkCommand::SendGroupFile {
            group_id,
            file_path,
            sender_name,
        })
        .await
        .map_err(|e| format!("Failed to send group file: {e}"))?;
    }
    Ok(())
}

#[tauri::command]
async fn get_group_history(
    group_id: String,
) -> Result<Vec<StoredMessage>, String> {
    let group_key = format!("group_{group_id}");
    messages::load_messages(&group_key)
}

#[tauri::command]
async fn leave_group(
    group_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::LeaveGroup { group_id }).await;
    }
    Ok(())
}

#[tauri::command]
async fn remove_group_member(
    group_id: String,
    peer_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::RemoveGroupMember { group_id, peer_id }).await;
    }
    Ok(())
}

#[tauri::command]
async fn disband_group(
    group_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::DisbandGroup { group_id }).await;
    }
    Ok(())
}

// ─── App Entry ────────────────────────────────────────────────────────────────

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let initial_contacts = contacts::load_contacts().unwrap_or_default();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState {
            identity_info: Arc::new(Mutex::new(None)),
            keypair: Arc::new(Mutex::new(None)),
            network_cmd_tx: Arc::new(Mutex::new(None)),
            network_handle: Arc::new(Mutex::new(None)),
            nearby_peers: Arc::new(Mutex::new(None)),
            contacts: Arc::new(Mutex::new(initial_contacts)),
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
            get_contacts,
            send_contact_request,
            respond_contact_request,
            add_contact_from_request,
            rename_contact,
            remove_contact_cmd,
            send_message,
            get_chat_history,
            set_username,
            send_file,
            pause_transfer,
            resume_transfer,
            create_group,
            get_groups,
            send_group_message,
            send_group_file,
            get_group_history,
            leave_group,
            remove_group_member,
            disband_group,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
