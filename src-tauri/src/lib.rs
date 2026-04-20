mod connection_code;
mod contacts;
mod crdt;
mod crypto;
mod file_transfer;
mod groups;
mod identity;
mod messages;
mod network;
mod protocol;
mod relay_config;

use contacts::Contact;
use identity::IdentityInfo;
use libp2p::identity::Keypair;
use messages::StoredMessage;
use network::{ContactsList, NearbyPeer, NearbyPeersMap, NetworkCommand};
use std::sync::{Arc, OnceLock};
use std::path::PathBuf;
use tauri::{Manager, State};
use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

pub static STOA_DIR: OnceLock<PathBuf> = OnceLock::new();

pub fn get_stoa_dir() -> PathBuf {
    // Check if the legacy `~/.stoa` directory exists for backward compatibility on Desktop
    if let Some(home) = dirs::home_dir() {
        let legacy_path = home.join(".stoa");
        if legacy_path.exists() {
            return legacy_path;
        }
    }
    
    STOA_DIR.get().cloned().unwrap_or_else(|| {
        dirs::home_dir().expect("Could not determine home directory").join(".stoa")
    })
}

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

    let path = crate::get_stoa_dir().join("identity.json");

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
async fn show_window(#[allow(unused_variables)] app_handle: tauri::AppHandle) -> Result<(), String> {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        if let Some(window) = app_handle.get_webview_window("main") {
            window
                .show()
                .map_err(|e| format!("Failed to show window: {e}"))?;
        }
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
        contacts::add_contact(&mut cts, peer_id, petname, None)?;
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
    contacts::add_contact(&mut cts, peer_id, petname, None)
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
async fn delete_chat_message(peer_id: String, message_id: String) -> Result<(), String> {
    messages::delete_message(&peer_id, &message_id)
}

#[tauri::command]
async fn delete_chat_messages(peer_id: String, message_ids: Vec<String>) -> Result<(), String> {
    messages::delete_messages(&peer_id, &message_ids)
}

#[tauri::command]
async fn clear_chat(peer_id: String) -> Result<(), String> {
    messages::clear_chat_history(&peer_id)
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

#[tauri::command]
async fn open_file_native(path: String) -> Result<(), String> {
    let path = std::path::PathBuf::from(&path);
    if !path.exists() {
        return Err(format!("File not found: {}", path.display()));
    }

    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(&path)
            .spawn()
            .map_err(|e| format!("Failed to open file: {e}"))?;
    }

    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(&path)
            .spawn()
            .map_err(|e| format!("Failed to open file: {e}"))?;
    }

    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer")
            .arg(&path)
            .spawn()
            .map_err(|e| format!("Failed to open file: {e}"))?;
    }

    Ok(())
}

// ─── Shared Spaces ──────────────────────────────────────────────────────────

#[tauri::command]
async fn open_group_space(group_id: String, state: State<'_, AppState>) -> Result<(), String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::OpenGroupSpace { group_id }).await;
    }
    Ok(())
}

#[tauri::command]
async fn list_space_files(group_id: String) -> Result<Vec<crate::crdt::SpaceFile>, String> {
    crate::crdt::list_files(&group_id).await
}

#[tauri::command]
async fn create_space_file(
    group_id: String,
    file_name: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::CreateSpaceFile {
            group_id,
            file_name,
            content: None,
        }).await;
    }
    Ok(())
}

#[tauri::command]
async fn import_space_file(
    group_id: String,
    file_path: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let path = std::path::Path::new(&file_path);

    // Validate extension
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    if !crate::crdt::ALLOWED_EXTENSIONS.contains(&ext.as_str()) {
        return Err("File type unfit for Shared Spaces! Only text and source code files are supported. Binary files can be shared via group chat.".to_string());
    }

    // Read content (copy — original file is never touched)
    let content = std::fs::read_to_string(&file_path)
        .map_err(|e| format!("Failed to read file: {}", e))?;

    // Check size limit
    if content.len() > crate::crdt::MAX_IMPORT_SIZE {
        return Err(format!(
            "File too large for Shared Spaces. Maximum size is 1 MB, but this file is {} KB.",
            content.len() / 1024
        ));
    }

    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("imported_file")
        .to_string();

    // Send to network handler — it creates and broadcasts
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::CreateSpaceFile {
            group_id,
            file_name,
            content: Some(content),
        }).await;
    }

    Ok(())
}

#[tauri::command]
async fn delete_space_file(
    group_id: String,
    file_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::DeleteSpaceFile { group_id, file_id }).await;
    }
    Ok(())
}

#[tauri::command]
async fn get_space_file_text(group_id: String, file_id: String) -> Result<String, String> {
    crate::crdt::get_file_text(&group_id, &file_id).await
}

#[tauri::command]
async fn export_space_file(
    group_id: String,
    file_id: String,
    export_path: String,
) -> Result<(), String> {
    let content = crate::crdt::get_file_text(&group_id, &file_id).await?;
    std::fs::write(&export_path, &content)
        .map_err(|e| format!("Failed to export file: {}", e))
}

#[tauri::command]
async fn edit_space_file(
    group_id: String,
    file_id: String,
    index: u32,
    delete_count: u32,
    insert_text: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(NetworkCommand::EditGroupSpace {
            group_id,
            file_id,
            index,
            delete_count,
            insert_text,
        }).await;
    }
    Ok(())
}

// ─── Relay Config ──────────────────────────────────────────────────────────────

#[tauri::command]
async fn get_relay_config() -> Result<relay_config::RelayConfig, String> {
    Ok(relay_config::RelayConfig::load())
}

#[tauri::command]
async fn set_relay_config(config: relay_config::RelayConfig) -> Result<(), String> {
    config.save()
}

// ─── Connection Codes ──────────────────────────────────────────────────────────

/// Returns our own connection code string and QR code SVG (base64) so the UI
/// can display them in the Settings panel for sharing with contacts.
#[tauri::command]
async fn get_my_connection_code(state: State<'_, AppState>) -> Result<serde_json::Value, String> {
    let kp_guard = state.keypair.lock().await;
    let keypair = kp_guard
        .as_ref()
        .ok_or("No identity — generate one first")?;

    let relay_cfg = relay_config::RelayConfig::load();
    let relay_addrs = relay_cfg.enabled_addresses();

    let code_str = connection_code::build_our_code(keypair, relay_addrs)?;
    let qr_b64 = connection_code::ConnectionCode::decode(&code_str)?.to_qr_base64()?;

    Ok(serde_json::json!({
        "code": code_str,
        "qr_svg_b64": qr_b64,
    }))
}

/// Decode a peer's connection code string and return their PeerID + relay addrs.
#[tauri::command]
async fn parse_connection_code(code: String) -> Result<serde_json::Value, String> {
    let (peer_id, relay_addrs) = connection_code::parse_peer_code(&code)?;
    Ok(serde_json::json!({
        "peer_id": peer_id,
        "relay_addrs": relay_addrs,
    }))
}

/// Add a contact from their connection code in one step.
/// Decodes the code, dials via relay address, sends a contact request,
/// and adds them to the local contacts list.
#[tauri::command]
async fn add_contact_from_code(
    code: String,
    petname: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let (peer_id_str, relay_addrs) = connection_code::parse_peer_code(&code)?;

    // Add to contacts list first
    {
        let mut cts = state.contacts.lock().await;
        contacts::add_contact(&mut cts, peer_id_str.clone(), petname, Some(relay_addrs.clone()))
            .map_err(|e| format!("Failed to save contact: {e}"))?;
    }

    // Dial the peer via their relay, then send contact request
    let tx = state.network_cmd_tx.lock().await;
    if let Some(tx) = tx.as_ref() {
        let _ = tx.send(network::NetworkCommand::DialPeer {
            peer_id: peer_id_str.clone(),
            relay_addrs,
        }).await;

        let id_guard = state.identity_info.lock().await;
        let our_name = id_guard
            .as_ref()
            .map(|i| i.name.clone())
            .unwrap_or_else(|| "Stoa User".to_string());
        let our_peer_id = id_guard
            .as_ref()
            .map(|i| i.peer_id.clone())
            .unwrap_or_default();
        drop(id_guard);

        let _ = tx.send(network::NetworkCommand::SendContactRequest {
            peer_id: peer_id_str,
            our_name,
            our_peer_id,
        }).await;
    }

    Ok(())
}


#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let data_dir = app.path().app_data_dir().unwrap_or_else(|_| {
                dirs::home_dir().expect("fallback").join(".stoa")
            });
            std::fs::create_dir_all(&data_dir).ok();
            STOA_DIR.set(data_dir).ok();
            
            let initial_contacts = contacts::load_contacts().unwrap_or_default();
            let state = app.state::<AppState>();
            *state.contacts.blocking_lock() = initial_contacts;
            
            Ok(())
        })
        .manage(AppState {
            identity_info: Arc::new(Mutex::new(None)),
            keypair: Arc::new(Mutex::new(None)),
            network_cmd_tx: Arc::new(Mutex::new(None)),
            network_handle: Arc::new(Mutex::new(None)),
            nearby_peers: Arc::new(Mutex::new(None)),
            contacts: Arc::new(Mutex::new(Vec::new())),
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
            open_file_native,
            open_group_space,
            list_space_files,
            create_space_file,
            import_space_file,
            delete_space_file,
            get_space_file_text,
            export_space_file,
            edit_space_file,
            get_relay_config,
            set_relay_config,
            get_my_connection_code,
            parse_connection_code,
            add_contact_from_code,
            delete_chat_message,
            delete_chat_messages,
            clear_chat,
        ])
        .on_window_event(|window, event| {
            // Gracefully shut down the network task before the window closes,
            // preventing the "corrupted double-linked list" glibc error from
            // libp2p's crypto resources being freed in an unclean order.
            if let tauri::WindowEvent::Destroyed = event {
                let app_state = window.state::<AppState>();
                let tx = app_state.network_cmd_tx.clone();
                let handle = app_state.network_handle.clone();
                tauri::async_runtime::block_on(async {
                    if let Some(tx) = tx.lock().await.take() {
                        let _ = tx.send(NetworkCommand::Shutdown).await;
                    }
                    if let Some(handle) = handle.lock().await.take() {
                        // Give the task a moment to finish
                        let _ = tokio::time::timeout(
                            std::time::Duration::from_millis(500),
                            handle,
                        ).await;
                    }
                });
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
