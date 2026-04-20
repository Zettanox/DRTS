use crate::crypto;
use crate::file_transfer::{self, ActiveTransfer, TransferDirection, TransferStatus};
use crate::groups::{self, Group};
use crate::messages::{self, StoredMessage};
use crate::protocol::{StoaRequest, StoaResponse};
use libp2p::identity::Keypair;
use libp2p::{request_response, PeerId, Swarm};
use serde::Serialize;
use std::collections::HashMap;
use std::str::FromStr;
use tauri::{AppHandle, Emitter};

use super::types::{ContactsList, NearbyPeersMap};
use super::StoaBehaviour;

// ─── Discovery Handlers ──────────────────────────────────────────────────────

/// Handle mDNS discovery of a peer: track, emit, auto-dial.
pub async fn handle_mdns_discovered(
    discovered_peer: PeerId,
    addr: libp2p::Multiaddr,
    peers_map: &NearbyPeersMap,
    contacts: &ContactsList,
    swarm: &mut Swarm<StoaBehaviour>,
    app_handle: &AppHandle,
) {
    let pid = discovered_peer.to_string();
    let addr_str = addr.to_string();

    let mut peers = peers_map.lock().await;
    let is_new = !peers.contains_key(&pid);
    let entry = peers
        .entry(pid.clone())
        .or_insert_with(|| super::types::NearbyPeer {
            peer_id: pid.clone(),
            addresses: vec![],
            display_name: None,
        });
    if !entry.addresses.contains(&addr_str) {
        entry.addresses.push(addr_str);
    }
    let peer_info = entry.clone();
    drop(peers);

    let _ = app_handle.emit("peer-discovered", &peer_info);

    // Auto-dial: new peers (for WhoAreYou) and known contacts
    let cts = contacts.lock().await;
    let is_contact = cts.iter().any(|c| c.peer_id == pid);
    drop(cts);
    // Auto-dial LAN address for new peers/contacts
    if (is_new || is_contact) && !swarm.is_connected(&discovered_peer) {
        let _ = swarm.dial(addr);
    }
}

/// Handle mDNS expiry of a peer.
pub async fn handle_mdns_expired(
    expired_peer: PeerId,
    peers_map: &NearbyPeersMap,
    app_handle: &AppHandle,
) {
    let pid = expired_peer.to_string();
    let mut peers = peers_map.lock().await;
    peers.remove(&pid);
    drop(peers);
    let _ = app_handle.emit("peer-expired", &pid);
}

// ─── Connection Handlers ─────────────────────────────────────────────────────

/// Handle a new connection: send WhoAreYou, emit contact-online, flush pending.
pub async fn handle_connection_established(
    connected_peer: PeerId,
    contacts: &ContactsList,
    swarm: &mut Swarm<StoaBehaviour>,
    app_handle: &AppHandle,
    pending_messages: &mut Vec<super::types::PendingMessage>,
) {
    let pid = connected_peer.to_string();
    // Note: the caller already logs the connection with its type (LAN/Relay)

    // Send WhoAreYou to learn their display name
    swarm
        .behaviour_mut()
        .messaging
        .send_request(&connected_peer, StoaRequest::WhoAreYou);

    // Notify frontend if this is a contact
    let cts = contacts.lock().await;
    let is_contact = cts.iter().any(|c| c.peer_id == pid);
    drop(cts);
    if is_contact {
        let _ = app_handle.emit("contact-online", &pid);
    }

    // Flush pending messages for this peer
    let mut remaining = vec![];
    for pm in pending_messages.drain(..) {
        if pm.peer_id == connected_peer {
            // E2E Encrypt the queued message if a session exists (or wait if we just asked for KeyExchange)
            let encrypted_req = super::maybe_encrypt_request(&pid, pm.request);

            swarm
                .behaviour_mut()
                .messaging
                .send_request(&pm.peer_id, encrypted_req);
            println!("[{}] [Stoa Network] Flushed queued message to {pid}", chrono::Local::now().format("%H:%M:%S"));
        } else {
            remaining.push(pm);
        }
    }
    *pending_messages = remaining;
}

/// Handle a closed connection: emit contact-offline.
pub async fn handle_connection_closed(
    disconnected_peer: PeerId,
    contacts: &ContactsList,
    app_handle: &AppHandle,
) {
    let pid = disconnected_peer.to_string();
    println!("[{}] [Stoa Network] Connection closed with {pid}", chrono::Local::now().format("%H:%M:%S"));

    let cts = contacts.lock().await;
    let is_contact = cts.iter().any(|c| c.peer_id == pid);
    drop(cts);
    if is_contact {
        let _ = app_handle.emit("contact-offline", &pid);
    }
}

// ─── Incoming Request Handlers ───────────────────────────────────────────────

/// Handle an incoming request from a remote peer.
pub async fn handle_incoming_request(
    app_handle: &AppHandle,
    peer: &PeerId,
    request: StoaRequest,
    channel: request_response::ResponseChannel<StoaResponse>,
    swarm: &mut Swarm<StoaBehaviour>,
    our_name: &str,
    active_transfers: &mut HashMap<String, ActiveTransfer>,
    our_keypair: &Keypair,
    groups: &mut Vec<Group>,
    our_peer_id: &str,
) {
    match request {
        StoaRequest::WhoAreYou => {
            let pid = peer.to_string();
            println!("[{}] [Stoa Network] WhoAreYou from {pid} — replying with '{our_name}'", chrono::Local::now().format("%H:%M:%S"));
            let response = StoaResponse::PeerIdentity {
                name: our_name.to_string(),
            };
            let _ = swarm
                .behaviour_mut()
                .messaging
                .send_response(channel, response);
        }
        StoaRequest::ContactRequest {
            from_peer_id,
            from_name,
        } => {
            println!("[{}] [Stoa Network] Contact request from {from_name} ({from_peer_id})", chrono::Local::now().format("%H:%M:%S"));

            #[derive(Serialize, Clone)]
            struct ContactRequestEvent {
                from_peer_id: String,
                from_name: String,
            }

            let _ = app_handle.emit(
                "contact-request",
                &ContactRequestEvent {
                    from_peer_id,
                    from_name,
                },
            );

            // Auto-accept and send our real name back
            let response = StoaResponse::ContactAccepted {
                name: our_name.to_string(),
            };
            let _ = swarm
                .behaviour_mut()
                .messaging
                .send_response(channel, response);
        }
        StoaRequest::ChatMessage {
            id,
            content,
            timestamp,
            sender_name,
        } => {
            let sender_id = peer.to_string();
            println!("[{}] [Stoa Network] Message from {sender_name}: {content}", chrono::Local::now().format("%H:%M:%S"));

            // Persist incoming message
            let msg = StoredMessage {
                id: id.clone(),
                sender_id: sender_id.clone(),
                content: content.clone(),
                timestamp,
                delivered: true,
                file_info: None,
            };
            let _ = messages::save_message(&sender_id, &msg);

            // Notify frontend
            #[derive(Serialize, Clone)]
            struct ChatMessageEvent {
                id: String,
                sender_id: String,
                sender_name: String,
                content: String,
                timestamp: i64,
            }

            let _ = app_handle.emit(
                "chat-message",
                &ChatMessageEvent {
                    id: id.clone(),
                    sender_id,
                    sender_name,
                    content,
                    timestamp,
                },
            );

            // Send ack
            let response = StoaResponse::MessageAck { id };
            let _ = swarm
                .behaviour_mut()
                .messaging
                .send_response(channel, response);
        }
        StoaRequest::FileOffer {
            transfer_id,
            file_name,
            file_size,
            checksum,
            chunk_count,
            chunk_size,
            sender_name,
        } => {
            let sender_id = peer.to_string();
            let chunk_size_usize = chunk_size as usize;
            println!(
                "[Stoa File] FileOffer from {sender_name}: {} ({} bytes, {} chunks @ {}KB)",
                file_name, file_size, chunk_count, chunk_size / 1024
            );

            // Auto-accept: create download transfer
            let dest = file_transfer::received_dir(&sender_id).join(&file_name);
            let mut transfer = ActiveTransfer {
                transfer_id: transfer_id.clone(),
                peer_id: sender_id.clone(),
                file_name: file_name.clone(),
                file_size,
                checksum,
                chunk_count,
                chunks_done: 0,
                direction: TransferDirection::Download,
                status: TransferStatus::Transferring,
                file_path: dest,
                received_chunks_set: std::collections::HashSet::new(),
                last_requested_chunk: None,
                group_id: None,
                chunk_size: chunk_size_usize,
            };
            
            // Accept the offer
            let response = StoaResponse::FileAccepted {
                transfer_id: transfer_id.clone(),
            };
            let _ = swarm
                .behaviour_mut()
                .messaging
                .send_response(channel, response);

            // Notify frontend
            #[derive(Serialize, Clone)]
            struct FileOfferEvent {
                transfer_id: String,
                peer_id: String,
                file_name: String,
                file_size: u64,
                direction: String,
                chunk_count: u32,
                sender_name: String,
            }
            let _ = app_handle.emit(
                "file-transfer-started",
                &FileOfferEvent {
                    transfer_id: transfer_id.clone(),
                    peer_id: sender_id.clone(),
                    file_name,
                    file_size,
                    direction: "download".into(),
                    chunk_count,
                    sender_name,
                },
            );

            // If empty file, just complete it
            if chunk_count == 0 {
                transfer.status = TransferStatus::Complete;
                if let Some(parent) = transfer.file_path.parent() {
                    let _ = std::fs::create_dir_all(parent);
                }
                let _ = std::fs::write(&transfer.file_path, b"");
                let _ = app_handle.emit(
                    "file-transfer-complete",
                    &serde_json::json!({
                        "transfer_id": transfer_id,
                        "peer_id": sender_id,
                        "file_name": transfer.file_name,
                        "file_path": transfer.file_path.to_string_lossy().to_string(),
                        "file_size": transfer.file_size,
                        "direction": "download"
                    }),
                );
                active_transfers.insert(transfer_id.clone(), transfer);
            } else {
                // Window size based on chunk size: large chunks → smaller window
                let window_size = if chunk_size_usize >= file_transfer::LAN_CHUNK_SIZE {
                    file_transfer::LAN_WINDOW_SIZE
                } else {
                    file_transfer::RELAY_WINDOW_SIZE
                };
                let window_max = chunk_count.min(window_size);
                transfer.last_requested_chunk = Some(window_max - 1);
                active_transfers.insert(transfer_id.clone(), transfer);
                
                if let Ok(target) = PeerId::from_str(&sender_id) {
                    for i in 0..window_max {
                        let fetch_req = StoaRequest::FetchChunk {
                            transfer_id: transfer_id.clone(),
                            chunk_index: i,
                        };
                        swarm.behaviour_mut().messaging.send_request(&target, fetch_req);
                    }
                }
            }
        }


        StoaRequest::FetchChunk {
            transfer_id,
            chunk_index,
        } => {
            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                if transfer.status == TransferStatus::Transferring
                    || transfer.status == TransferStatus::Offering {
                    // Also mark as Transferring now that we know the receiver is pulling
                    transfer.status = TransferStatus::Transferring;
                    let cs = transfer.chunk_size;
                    if let Ok(data_b64) = file_transfer::read_chunk(&transfer.file_path, chunk_index, cs) {
                        // Encrypt chunk data if we have a session with the peer
                        let peer_id_str = transfer.peer_id.clone();
                        let (final_data, final_nonce) = if crypto::has_session(&peer_id_str) {
                            // Decode the b64 chunk, encrypt raw bytes, re-encode
                            match crypto::encrypt_for_peer(&peer_id_str, data_b64.as_bytes()) {
                                Ok(Some((ct, nonce))) => (ct, Some(nonce)),
                                _ => (data_b64, None),
                            }
                        } else {
                            (data_b64, None)
                        };
                        let response = StoaResponse::FileChunk {
                            transfer_id: transfer_id.clone(),
                            chunk_index,
                            data_b64: final_data,
                            nonce_b64: final_nonce,
                        };
                        let _ = swarm
                            .behaviour_mut()
                            .messaging
                            .send_response(channel, response);
                            
                        // Update sender progress
                        transfer.received_chunks_set.insert(chunk_index);
                        transfer.chunks_done = transfer.received_chunks_set.len() as u32;

                        #[derive(Serialize, Clone)]
                        struct ProgressEvent {
                            transfer_id: String,
                            chunk_index: u32,
                            chunk_count: u32,
                            progress: f64,
                        }
                        let progress = transfer.chunks_done as f64 / transfer.chunk_count as f64;
                        let _ = app_handle.emit(
                            "file-transfer-progress",
                            &ProgressEvent {
                                transfer_id: transfer_id.clone(),
                                chunk_index,
                                chunk_count: transfer.chunk_count,
                                progress,
                            },
                        );

                        // If all chunks sent, mark complete for sender
                        if transfer.chunks_done >= transfer.chunk_count {
                            transfer.status = TransferStatus::Complete;
                            println!(
                                "[Stoa File] Upload complete: {} ({} chunks)",
                                transfer.file_name, transfer.chunk_count
                            );

                            // Persist file message — use group key if this is a group transfer
                            let persist_key = if let Some(ref gid) = transfer.group_id {
                                format!("group_{}", gid)
                            } else {
                                transfer.peer_id.clone()
                            };
                            let file_msg = messages::StoredMessage {
                                id: format!("file-{}", transfer_id),
                                sender_id: "me".into(),
                                content: format!("📎 {}", transfer.file_name),
                                timestamp: chrono::Utc::now().timestamp(),
                                delivered: true,
                                file_info: Some(messages::StoredFileInfo {
                                    transfer_id: transfer_id.clone(),
                                    file_name: transfer.file_name.clone(),
                                    file_size: transfer.file_size,
                                    direction: "upload".into(),
                                    status: "complete".into(),
                                    file_path: Some(transfer.file_path.to_string_lossy().to_string()),
                                }),
                            };
                            let _ = messages::save_message(&persist_key, &file_msg);

                            #[derive(Serialize, Clone)]
                            struct CompleteEvent {
                                transfer_id: String,
                                peer_id: String,
                                file_name: String,
                                file_size: u64,
                                direction: String,
                            }
                            let _ = app_handle.emit(
                                "file-transfer-complete",
                                &CompleteEvent {
                                    transfer_id: transfer_id.clone(),
                                    peer_id: transfer.peer_id.clone(),
                                    file_name: transfer.file_name.clone(),
                                    file_size: transfer.file_size,
                                    direction: "upload".into(),
                                },
                            );
                            
                            active_transfers.remove(&transfer_id);
                        }
                    } else {
                        eprintln!("[{}] [Stoa File] Failed to read chunk {chunk_index} for {}", chrono::Local::now().format("%H:%M:%S"), transfer_id);
                    }
                }
            }
        }
        StoaRequest::KeyExchange {
            x25519_public_key_hex,
        } => {
            let pid = peer.to_string();
            println!("[{}] [Stoa Crypto] KeyExchange from {pid}", chrono::Local::now().format("%H:%M:%S"));

            match crypto::compute_shared_secret(our_keypair, &x25519_public_key_hex) {
                Ok(shared_secret) => {
                    if let Err(e) = crypto::save_session(&pid, &shared_secret) {
                        eprintln!("[{}] [Stoa Crypto] Failed to save session: {e}", chrono::Local::now().format("%H:%M:%S"));
                    } else {
                        println!("[{}] [Stoa Crypto] Session established with {pid}", chrono::Local::now().format("%H:%M:%S"));
                    }

                    // Respond with our X25519 public key
                    match crypto::our_x25519_public_key_hex(our_keypair) {
                        Ok(our_pk_hex) => {
                            let response = StoaResponse::KeyExchangeAck {
                                x25519_public_key_hex: our_pk_hex,
                            };
                            let _ = swarm
                                .behaviour_mut()
                                .messaging
                                .send_response(channel, response);
                        }
                        Err(e) => eprintln!("[{}] [Stoa Crypto] Failed to derive our X25519 key: {e}", chrono::Local::now().format("%H:%M:%S")),
                    }
                }
                Err(e) => eprintln!("[{}] [Stoa Crypto] ECDH failed: {e}", chrono::Local::now().format("%H:%M:%S")),
            }
        }
        StoaRequest::EncryptedEnvelope {
            id: _,
            ciphertext_b64,
            nonce_b64,
        } => {
            let pid = peer.to_string();
            match crypto::decrypt_from_peer(&pid, &ciphertext_b64, &nonce_b64) {
                Ok(Some(plaintext)) => {
                    // Deserialize the inner message and dispatch
                    match serde_json::from_slice::<StoaRequest>(&plaintext) {
                        Ok(inner_request) => {
                            println!("[{}] [Stoa Crypto] Decrypted envelope from {pid}", chrono::Local::now().format("%H:%M:%S"));
                            // Recursively handle the decrypted inner request.
                            // We create a dummy channel situation — the inner request
                            // should use the original channel for its response.
                            // For simplicity, we use Box::pin for the recursive call.
                            Box::pin(handle_incoming_request(
                                app_handle,
                                peer,
                                inner_request,
                                channel,
                                swarm,
                                our_name,
                                active_transfers,
                                our_keypair,
                                groups,
                                our_peer_id,
                            ))
                            .await;
                        }
                        Err(e) => {
                            eprintln!("[{}] [Stoa Crypto] Failed to deserialize decrypted payload: {e}", chrono::Local::now().format("%H:%M:%S"));
                        }
                    }
                }
                Ok(None) => {
                    eprintln!("[{}] [Stoa Crypto] No session for {pid} — cannot decrypt envelope", chrono::Local::now().format("%H:%M:%S"));
                }
                Err(e) => {
                    eprintln!("[{}] [Stoa Crypto] Decryption failed from {pid}: {e}", chrono::Local::now().format("%H:%M:%S"));
                }
            }
        }
        // ─── Group Request Handlers ──────────────────────────────────────────
        StoaRequest::GroupInvite {
            group_id,
            group_name,
            members,
            admin,
            inviter_name,
        } => {
            let pid = peer.to_string();
            println!("[{}] [Stoa Group] GroupInvite from {inviter_name}: '{group_name}' ({group_id})", chrono::Local::now().format("%H:%M:%S"));

            let group = Group {
                id: group_id.clone(),
                name: group_name.clone(),
                members: members.clone(),
                admin: admin.clone(),
                created_at: chrono::Utc::now().timestamp(),
            };

            if let Err(e) = groups::add_group_from_invite(groups, group) {
                eprintln!("[{}] [Stoa Group] Failed to save group: {e}", chrono::Local::now().format("%H:%M:%S"));
            }

            // Notify frontend
            #[derive(Serialize, Clone)]
            struct GroupInviteEvent {
                group_id: String,
                group_name: String,
                members: Vec<String>,
                admin: String,
                inviter_name: String,
            }
            let _ = app_handle.emit(
                "group-invite",
                &GroupInviteEvent {
                    group_id,
                    group_name,
                    members,
                    admin,
                    inviter_name,
                },
            );

            // Ack
            let response = StoaResponse::MessageAck {
                id: "group-invite-ack".into(),
            };
            let _ = swarm
                .behaviour_mut()
                .messaging
                .send_response(channel, response);
        }
        StoaRequest::GroupMessage {
            group_id,
            id,
            content,
            timestamp,
            sender_name,
        } => {
            let sender_id = peer.to_string();
            println!("[{}] [Stoa Group] Message in '{group_id}' from {sender_name}: {content}", chrono::Local::now().format("%H:%M:%S"));

            // Check if we know this group; if not, it may be stale
            let known = groups.iter().any(|g| g.id == group_id);
            if !known {
                println!("[{}] [Stoa Group] Unknown group {group_id} — ignoring", chrono::Local::now().format("%H:%M:%S"));
                let response = StoaResponse::MessageAck { id };
                let _ = swarm
                    .behaviour_mut()
                    .messaging
                    .send_response(channel, response);
                return;
            }

            // Persist to group message store
            let group_key = format!("group_{group_id}");
            let msg = StoredMessage {
                id: id.clone(),
                sender_id: sender_id.clone(),
                content: content.clone(),
                timestamp,
                delivered: true,
                file_info: None,
            };
            let _ = messages::save_message(&group_key, &msg);

            // Notify frontend
            #[derive(Serialize, Clone)]
            struct GroupMessageEvent {
                group_id: String,
                id: String,
                sender_id: String,
                sender_name: String,
                content: String,
                timestamp: i64,
            }
            let _ = app_handle.emit(
                "group-message",
                &GroupMessageEvent {
                    group_id: group_id.clone(),
                    id: id.clone(),
                    sender_id,
                    sender_name,
                    content,
                    timestamp,
                },
            );

            // Ack
            let response = StoaResponse::GroupAck {
                group_id,
                message_id: id,
            };
            let _ = swarm
                .behaviour_mut()
                .messaging
                .send_response(channel, response);
        }
        StoaRequest::GroupFileOffer {
            group_id,
            transfer_id,
            file_name,
            file_size,
            checksum,
            chunk_count,
            chunk_size,
            sender_name,
        } => {
            let sender_id = peer.to_string();
            let chunk_size_usize = chunk_size as usize;
            println!(
                "[Stoa Group] FileOffer in '{group_id}' from {sender_name}: {} ({} bytes, {}KB chunks)",
                file_name, file_size, chunk_size / 1024
            );

            // Reuse the DM file offer logic — the file is pulled individually
            let dest = file_transfer::received_dir(&sender_id).join(&file_name);
            let mut transfer = ActiveTransfer {
                transfer_id: transfer_id.clone(),
                peer_id: sender_id.clone(),
                file_name: file_name.clone(),
                file_size,
                checksum,
                chunk_count,
                chunks_done: 0,
                direction: TransferDirection::Download,
                status: TransferStatus::Transferring,
                file_path: dest,
                received_chunks_set: std::collections::HashSet::new(),
                last_requested_chunk: None,
                group_id: Some(group_id.clone()),
                chunk_size: chunk_size_usize,
            };

            let response = StoaResponse::FileAccepted {
                transfer_id: transfer_id.clone(),
            };
            let _ = swarm
                .behaviour_mut()
                .messaging
                .send_response(channel, response);

            // Notify frontend with group context
            #[derive(Serialize, Clone)]
            struct GroupFileEvent {
                group_id: String,
                transfer_id: String,
                peer_id: String,
                file_name: String,
                file_size: u64,
                direction: String,
                chunk_count: u32,
                sender_name: String,
            }
            let _ = app_handle.emit(
                "group-file-transfer-started",
                &GroupFileEvent {
                    group_id,
                    transfer_id: transfer_id.clone(),
                    peer_id: sender_id.clone(),
                    file_name,
                    file_size,
                    direction: "download".into(),
                    chunk_count,
                    sender_name,
                },
            );

            if chunk_count == 0 {
                transfer.status = TransferStatus::Complete;
                if let Some(parent) = transfer.file_path.parent() {
                    let _ = std::fs::create_dir_all(parent);
                }
                let _ = std::fs::write(&transfer.file_path, b"");
                active_transfers.insert(transfer_id, transfer);
            } else {
                let window_size = if chunk_size_usize >= file_transfer::LAN_CHUNK_SIZE {
                    file_transfer::LAN_WINDOW_SIZE
                } else {
                    file_transfer::RELAY_WINDOW_SIZE
                };
                let window_max = chunk_count.min(window_size);
                transfer.last_requested_chunk = Some(window_max - 1);
                active_transfers.insert(transfer_id.clone(), transfer);

                if let Ok(target) = PeerId::from_str(&sender_id) {
                    for i in 0..window_max {
                        let fetch_req = StoaRequest::FetchChunk {
                            transfer_id: transfer_id.clone(),
                            chunk_index: i,
                        };
                        swarm.behaviour_mut().messaging.send_request(&target, fetch_req);
                    }
                }
            }
        }
        StoaRequest::MemberRemoved {
            group_id,
            removed_peer_id,
        } => {
            println!("[{}] [Stoa Group] MemberRemoved: {removed_peer_id} from {group_id}", chrono::Local::now().format("%H:%M:%S"));
            if removed_peer_id == our_peer_id {
                // We were removed
                let _ = groups::remove_group(groups, &group_id);
                let _ = app_handle.emit("group-removed", &serde_json::json!({
                    "group_id": group_id,
                    "reason": "removed",
                }));
            } else {
                let _ = groups::remove_member(groups, &group_id, &removed_peer_id);
                let _ = app_handle.emit("group-member-update", &serde_json::json!({
                    "group_id": group_id,
                    "removed": removed_peer_id,
                }));
            }
            let response = StoaResponse::MessageAck { id: "member-removed-ack".into() };
            let _ = swarm.behaviour_mut().messaging.send_response(channel, response);
        }
        StoaRequest::MemberLeft {
            group_id,
            peer_id,
        } => {
            println!("[{}] [Stoa Group] MemberLeft: {peer_id} from {group_id}", chrono::Local::now().format("%H:%M:%S"));
            let _ = groups::remove_member(groups, &group_id, &peer_id);
            let _ = app_handle.emit("group-member-update", &serde_json::json!({
                "group_id": group_id,
                "removed": peer_id,
            }));
            let response = StoaResponse::MessageAck { id: "member-left-ack".into() };
            let _ = swarm.behaviour_mut().messaging.send_response(channel, response);
        }
        StoaRequest::GroupDisbanded { group_id } => {
            println!("[{}] [Stoa Group] GroupDisbanded: {group_id}", chrono::Local::now().format("%H:%M:%S"));
            let _ = groups::remove_group(groups, &group_id);
            let _ = app_handle.emit("group-removed", &serde_json::json!({
                "group_id": group_id,
                "reason": "disbanded",
            }));
            let response = StoaResponse::MessageAck { id: "disbanded-ack".into() };
            let _ = swarm.behaviour_mut().messaging.send_response(channel, response);
        }
        StoaRequest::GroupSpaceSync { group_id, state_vector_b64 } => {
            println!("[{}] [Stoa Space] Sync request from {} for {}", chrono::Local::now().format("%H:%M:%S"), peer.to_string(), group_id);
            if let Ok(sv_bytes) = base64::decode(&state_vector_b64) {
                if let Ok(update_bytes) = crate::crdt::encode_diff(&group_id, &sv_bytes).await {
                    let response = StoaResponse::GroupSpaceSyncReply {
                        group_id: group_id.clone(),
                        update_b64: base64::encode(&update_bytes),
                    };
                    let _ = swarm.behaviour_mut().messaging.send_response(channel, response);
                }
            }
        }
        StoaRequest::GroupSpaceUpdate { group_id, update_b64 } => {
            println!("[{}] [Stoa Space] Live update from {} for {}", chrono::Local::now().format("%H:%M:%S"), peer.to_string(), group_id);
            if let Ok(update_bytes) = base64::decode(&update_b64) {
                if let Ok(_) = crate::crdt::apply_remote_update(&group_id, &update_bytes).await {
                    let _ = app_handle.emit("space-remote-update", &serde_json::json!({
                        "group_id": group_id,
                    }));
                    let response = StoaResponse::GroupSpaceUpdateAck {
                        group_id: group_id.clone(),
                    };
                    let _ = swarm.behaviour_mut().messaging.send_response(channel, response);
                }
            }
        }
    }
}

// ─── Incoming Response Handlers ──────────────────────────────────────────────

/// Handle an incoming response to our request.
pub async fn handle_incoming_response(
    app_handle: &AppHandle,
    peer: &PeerId,
    response: StoaResponse,
    _request_id: request_response::OutboundRequestId,
    peers_map: &NearbyPeersMap,
    active_transfers: &mut HashMap<String, ActiveTransfer>,
    swarm: &mut Swarm<StoaBehaviour>,
    our_keypair: &Keypair,
) {
    match response {
        StoaResponse::PeerIdentity { name } => {
            let pid = peer.to_string();
            println!("[{}] [Stoa Network] Peer {pid} identified as '{name}'", chrono::Local::now().format("%H:%M:%S"));

            let mut peers = peers_map.lock().await;
            let entry = peers
                .entry(pid.clone())
                .or_insert_with(|| super::types::NearbyPeer {
                    peer_id: pid.clone(),
                    addresses: vec![],
                    display_name: None,
                });
            entry.display_name = Some(name);
            let updated = entry.clone();
            drop(peers);
            let _ = app_handle.emit("peer-discovered", &updated);
        }
        StoaResponse::ContactAccepted { name } => {
            let pid = peer.to_string();
            println!("[{}] [Stoa Network] Contact accepted by {name} ({pid})", chrono::Local::now().format("%H:%M:%S"));

            #[derive(Serialize, Clone)]
            struct ContactAcceptedEvent {
                peer_id: String,
                name: String,
            }

            let _ = app_handle.emit(
                "contact-accepted",
                &ContactAcceptedEvent {
                    peer_id: pid,
                    name,
                },
            );
        }
        StoaResponse::ContactRejected => {
            let pid = peer.to_string();
            println!("[{}] [Stoa Network] Contact rejected by {pid}", chrono::Local::now().format("%H:%M:%S"));
            let _ = app_handle.emit("contact-rejected", &pid);
        }
        StoaResponse::MessageAck { id } => {
            let pid = peer.to_string();
            let _ = messages::mark_delivered(&pid, &id);

            #[derive(Serialize, Clone)]
            struct MessageAckEvent {
                peer_id: String,
                message_id: String,
            }

            let _ = app_handle.emit(
                "message-ack",
                &MessageAckEvent {
                    peer_id: pid,
                    message_id: id,
                },
            );
        }
        StoaResponse::FileAccepted { transfer_id } => {
            println!("[{}] [Stoa File] FileAccepted for {transfer_id} — awaiting Fetch requests", chrono::Local::now().format("%H:%M:%S"));
            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                transfer.status = TransferStatus::Transferring;
            }
        }
        StoaResponse::FileRejected { transfer_id } => {
            println!("[{}] [Stoa File] FileRejected for {transfer_id}", chrono::Local::now().format("%H:%M:%S"));
            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                transfer.status = TransferStatus::Cancelled;
            }
            active_transfers.remove(&transfer_id);
        }
        StoaResponse::FileChunk {
            transfer_id,
            chunk_index,
            data_b64,
            nonce_b64: encrypted_nonce,
        } => {
            let sender_id = peer.to_string();

            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                // Decrypt chunk data if it was encrypted
                let actual_data_b64 = if let Some(ref nonce) = encrypted_nonce {
                    match crypto::decrypt_from_peer(&sender_id, &data_b64, nonce) {
                        Ok(Some(decrypted_bytes)) => {
                            // decrypted_bytes are the original b64 string bytes
                            String::from_utf8(decrypted_bytes).unwrap_or_else(|_| data_b64.clone())
                        }
                        Ok(None) => {
                            eprintln!("[{}] [Stoa Crypto] No session to decrypt chunk from {sender_id}", chrono::Local::now().format("%H:%M:%S"));
                            data_b64.clone()
                        }
                        Err(e) => {
                            eprintln!("[{}] [Stoa Crypto] Chunk decryption failed: {e}", chrono::Local::now().format("%H:%M:%S"));
                            transfer.status = TransferStatus::Failed;
                            return;
                        }
                    }
                } else {
                    data_b64
                };

                let cs = transfer.chunk_size;
                if let Err(e) = file_transfer::write_chunk(&transfer.file_path, chunk_index, &actual_data_b64, cs) {
                    eprintln!("[{}] [Stoa File] Failed to write chunk: {e}", chrono::Local::now().format("%H:%M:%S"));
                    transfer.status = TransferStatus::Failed;
                    return;
                }

                transfer.received_chunks_set.insert(chunk_index);
                transfer.chunks_done = transfer.received_chunks_set.len() as u32;

                // Emit progress
                #[derive(Serialize, Clone)]
                struct ProgressEvent {
                    transfer_id: String,
                    chunk_index: u32,
                    chunk_count: u32,
                    progress: f64,
                }
                let progress = transfer.chunks_done as f64 / transfer.chunk_count as f64;
                let _ = app_handle.emit(
                    "file-transfer-progress",
                    &ProgressEvent {
                        transfer_id: transfer_id.clone(),
                        chunk_index,
                        chunk_count: transfer.chunk_count,
                        progress,
                    },
                );

                // Check completion
                if transfer.chunks_done >= transfer.chunk_count {
                    transfer.status = TransferStatus::Complete;
                    let path = transfer.file_path.clone();
                    let expected_checksum = transfer.checksum.clone();
                    let file_name = transfer.file_name.clone();
                    let file_size = transfer.file_size;
                    let transfer_id_clone = transfer_id.clone();
                    let transfer_group_id = transfer.group_id.clone();
                    
                    println!("[{}] [Stoa File] All chunks received for {}. Verifying...", chrono::Local::now().format("%H:%M:%S"), file_name);
                    
                    let app_handle_clone = app_handle.clone();
                    tokio::spawn(async move {
                        match file_transfer::verify_file_off_thread(path.clone(), expected_checksum).await {
                            Ok(true) => {
                                println!("[{}] [Stoa File] Transfer complete and verified: {} -> {:?}", chrono::Local::now().format("%H:%M:%S"), file_name, path);

                                // Persist file message — use group key if this is a group transfer
                                let persist_key = if let Some(ref gid) = transfer_group_id {
                                    format!("group_{}", gid)
                                } else {
                                    sender_id.clone()
                                };
                                let file_msg = messages::StoredMessage {
                                    id: format!("file-{}", transfer_id_clone),
                                    sender_id: sender_id.clone(),
                                    content: format!("📎 {}", file_name),
                                    timestamp: chrono::Utc::now().timestamp(),
                                    delivered: true,
                                    file_info: Some(messages::StoredFileInfo {
                                        transfer_id: transfer_id_clone.clone(),
                                        file_name: file_name.clone(),
                                        file_size,
                                        direction: "download".into(),
                                        status: "complete".into(),
                                        file_path: Some(path.to_string_lossy().to_string()),
                                    }),
                                };
                                let _ = messages::save_message(&persist_key, &file_msg);

                                let _ = app_handle_clone.emit(
                                    "file-transfer-complete",
                                    &serde_json::json!({
                                        "transfer_id": transfer_id_clone,
                                        "peer_id": sender_id,
                                        "file_name": file_name,
                                        "file_path": path.to_string_lossy().to_string(),
                                        "file_size": file_size,
                                        "direction": "download"
                                    }),
                                );
                            }
                            Ok(false) => eprintln!("[{}] [Stoa File] Checksum mismatch for {}", chrono::Local::now().format("%H:%M:%S"), file_name),
                            Err(e) => eprintln!("[{}] [Stoa File] Verification failed: {e}", chrono::Local::now().format("%H:%M:%S")),
                        }
                    });
                    
                    active_transfers.remove(&transfer_id);
                } else if transfer.status == TransferStatus::Transferring {
                    // Fetch next chunk to keep pipeline full
                    if let Some(mut last) = transfer.last_requested_chunk {
                        if last + 1 < transfer.chunk_count {
                            last += 1;
                            transfer.last_requested_chunk = Some(last);
                            if let Ok(target) = PeerId::from_str(&transfer.peer_id) {
                                let req = StoaRequest::FetchChunk {
                                    transfer_id: transfer_id.clone(),
                                    chunk_index: last,
                                };
                                swarm.behaviour_mut().messaging.send_request(&target, req);
                            }
                        }
                    }
                }
            }
        }
        StoaResponse::KeyExchangeAck {
            x25519_public_key_hex,
        } => {
            let pid = peer.to_string();
            println!("[{}] [Stoa Crypto] KeyExchangeAck from {pid}", chrono::Local::now().format("%H:%M:%S"));

            match crypto::compute_shared_secret(our_keypair, &x25519_public_key_hex) {
                Ok(shared_secret) => {
                    if let Err(e) = crypto::save_session(&pid, &shared_secret) {
                        eprintln!("[{}] [Stoa Crypto] Failed to save session: {e}", chrono::Local::now().format("%H:%M:%S"));
                    } else {
                        println!("[{}] [Stoa Crypto] Session established with {pid} (via ack)", chrono::Local::now().format("%H:%M:%S"));
                        let _ = app_handle.emit(
                            "e2e-session-established",
                            &serde_json::json!({ "peer_id": pid }),
                        );
                    }
                }
                Err(e) => eprintln!("[{}] [Stoa Crypto] ECDH failed: {e}", chrono::Local::now().format("%H:%M:%S")),
            }
        }
        StoaResponse::GroupAck {
            group_id,
            message_id,
        } => {
            println!("[{}] [Stoa Group] GroupAck for message {message_id} in {group_id}", chrono::Local::now().format("%H:%M:%S"));
        }
        StoaResponse::GroupSpaceSyncReply { group_id, update_b64 } => {
            println!("[{}] [Stoa Space] Sync reply from {} for {}", chrono::Local::now().format("%H:%M:%S"), peer.to_string(), group_id);
            if let Ok(update_bytes) = base64::decode(&update_b64) {
                if let Ok(_) = crate::crdt::apply_remote_update(&group_id, &update_bytes).await {
                    let _ = app_handle.emit("space-remote-update", &serde_json::json!({
                        "group_id": group_id,
                    }));
                }
            }
        }
        StoaResponse::GroupSpaceUpdateAck { group_id: _ } => {
            // Can be used for "Synced ✓" indicator in UI later
        }
    }
}

// ─── Utility ─────────────────────────────────────────────────────────────────

/// Dial a peer: always try LAN first (if discovered), always try relay for contacts.
/// Both paths can run simultaneously — LAN wins on speed, relay is the safety net.
pub async fn dial_peer(
    peers_map: &NearbyPeersMap,
    contacts: &super::types::ContactsList,
    peer_id_str: &str,
    swarm: &mut Swarm<StoaBehaviour>,
) {
    let Ok(target_peer_id) = peer_id_str.parse::<libp2p::PeerId>() else { return };
    let already_connected = swarm.is_connected(&target_peer_id);

    // 1. Try LAN addresses only if not already connected (prevents EADDRINUSE on Windows)
    if !already_connected {
        let peers = peers_map.lock().await;
        if let Some(peer_info) = peers.get(peer_id_str) {
            for addr_str in &peer_info.addresses {
                if let Ok(addr) = addr_str.parse::<libp2p::Multiaddr>() {
                    let _ = swarm.dial(addr);
                }
            }
        }
        drop(peers);
    }

    // 2. Try relay only if not already connected (prevents oneshot-canceled errors)
    if !already_connected {
        let cts = contacts.lock().await;
        if let Some(contact) = cts.iter().find(|c| c.peer_id == peer_id_str) {
            if let Some(addrs) = &contact.known_addrs {
                for addr_str in addrs {
                    let circuit_addr = format!("{}/p2p-circuit/p2p/{}", addr_str, peer_id_str);
                    if let Ok(maddr) = circuit_addr.parse::<libp2p::Multiaddr>() {
                        let _ = swarm.dial(maddr);
                    }
                }
            }
        }
        drop(cts);
    }
}

/// Handle an outbound request failure.
///
/// When the request-response layer fails to deliver a request we sent
/// (e.g. a FetchChunk from the receiver side), the pipeline stalls because
/// the sender never receives the request and never sends that chunk back.
///
/// This re-issues the first missing chunk window to restart the pipeline.
pub async fn handle_outbound_failure(
    peer: &PeerId,
    active_transfers: &mut HashMap<String, ActiveTransfer>,
    swarm: &mut Swarm<StoaBehaviour>,
) {
    let pid = peer.to_string();

    // Collect stalled download transfer IDs (avoid borrow conflicts on active_transfers)
    let stalled: Vec<String> = active_transfers
        .iter()
        .filter(|(_, t)| {
            t.peer_id == pid
                && t.direction == file_transfer::TransferDirection::Download
                && (t.status == file_transfer::TransferStatus::Transferring
                    || t.status == file_transfer::TransferStatus::Offering)
        })
        .map(|(id, _)| id.clone())
        .collect();

    for transfer_id in stalled {
        if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
            // Find first missing chunk and re-open the pipeline window
            if let Some(first_missing) = (0..transfer.chunk_count)
                .find(|i| !transfer.received_chunks_set.contains(i))
            {
                if let Ok(target) = PeerId::from_str(&transfer.peer_id) {
                    let window_size = if transfer.chunk_size >= file_transfer::LAN_CHUNK_SIZE {
                        file_transfer::LAN_WINDOW_SIZE
                    } else {
                        file_transfer::RELAY_WINDOW_SIZE
                    };

                    let mut sent = 0u32;
                    let mut last_sent = first_missing;
                    for i in first_missing..transfer.chunk_count {
                        if sent >= window_size { break; }
                        if !transfer.received_chunks_set.contains(&i) {
                            swarm.behaviour_mut().messaging.send_request(
                                &target,
                                crate::protocol::StoaRequest::FetchChunk {
                                    transfer_id: transfer_id.clone(),
                                    chunk_index: i,
                                },
                            );
                            last_sent = i;
                            sent += 1;
                        }
                    }
                    transfer.last_requested_chunk = Some(last_sent);
                    eprintln!("[{}] [Stoa File] ↺ Re-requesting {} chunks for stalled transfer {} (from chunk {})",
                        chrono::Local::now().format("%H:%M:%S"), sent, &transfer_id[..8], first_missing);
                }
            }
        }
    }
}
