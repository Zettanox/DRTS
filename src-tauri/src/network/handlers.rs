use crate::file_transfer::{self, ActiveTransfer, TransferDirection, TransferStatus};
use crate::messages::{self, StoredMessage};
use crate::protocol::{StoaRequest, StoaResponse};
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
    println!("[Stoa Network] Connection established with {pid}");

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
            swarm
                .behaviour_mut()
                .messaging
                .send_request(&pm.peer_id, pm.request);
            println!("[Stoa Network] Flushed queued message to {pid}");
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
    println!("[Stoa Network] Connection closed with {pid}");

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
) {
    match request {
        StoaRequest::WhoAreYou => {
            let pid = peer.to_string();
            println!("[Stoa Network] WhoAreYou from {pid} — replying with '{our_name}'");
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
            println!("[Stoa Network] Contact request from {from_name} ({from_peer_id})");

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
            println!("[Stoa Network] Message from {sender_name}: {content}");

            // Persist incoming message
            let msg = StoredMessage {
                id: id.clone(),
                sender_id: sender_id.clone(),
                content: content.clone(),
                timestamp,
                delivered: true,
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
            sender_name,
        } => {
            let sender_id = peer.to_string();
            println!(
                "[Stoa File] FileOffer from {sender_name}: {} ({} bytes, {} chunks)",
                file_name, file_size, chunk_count
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
                // Determine pipeline window
                let mut window_max = chunk_count;
                if window_max > file_transfer::MAX_WINDOW_SIZE {
                    window_max = file_transfer::MAX_WINDOW_SIZE;
                }
                
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
                if transfer.status == TransferStatus::Transferring {
                    if let Ok(data_b64) = file_transfer::read_chunk(&transfer.file_path, chunk_index) {
                        let response = StoaResponse::FileChunk {
                            transfer_id: transfer_id.clone(),
                            chunk_index,
                            data_b64,
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
                            
                            // DO NOT remove active_transfers yet, because the receiver might retry fetching
                            // the last chunk if the response was dropped. But let's remove it to clean up.
                            active_transfers.remove(&transfer_id);
                        }
                    } else {
                        eprintln!("[Stoa File] Failed to read chunk {chunk_index} for {}", transfer_id);
                    }
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
) {
    match response {
        StoaResponse::PeerIdentity { name } => {
            let pid = peer.to_string();
            println!("[Stoa Network] Peer {pid} identified as '{name}'");

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
            println!("[Stoa Network] Contact accepted by {name} ({pid})");

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
            println!("[Stoa Network] Contact rejected by {pid}");
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
            println!("[Stoa File] FileAccepted for {transfer_id} — awaiting Fetch requests");
            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                transfer.status = TransferStatus::Transferring;
            }
        }
        StoaResponse::FileRejected { transfer_id } => {
            println!("[Stoa File] FileRejected for {transfer_id}");
            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                transfer.status = TransferStatus::Cancelled;
            }
            active_transfers.remove(&transfer_id);
        }
        StoaResponse::FileChunk {
            transfer_id,
            chunk_index,
            data_b64,
        } => {
            let sender_id = peer.to_string();

            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                if let Err(e) = file_transfer::write_chunk(&transfer.file_path, chunk_index, &data_b64) {
                    eprintln!("[Stoa File] Failed to write chunk: {e}");
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
                    
                    println!("[Stoa File] All chunks received for {}. Verifying...", file_name);
                    
                    let app_handle_clone = app_handle.clone();
                    tokio::spawn(async move {
                        match file_transfer::verify_file_off_thread(path.clone(), expected_checksum).await {
                            Ok(true) => {
                                println!("[Stoa File] Transfer complete and verified: {} -> {:?}", file_name, path);
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
                            Ok(false) => eprintln!("[Stoa File] Checksum mismatch for {}", file_name),
                            Err(e) => eprintln!("[Stoa File] Verification failed: {e}"),
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
    }
}

// ─── Utility ─────────────────────────────────────────────────────────────────

/// Dial a peer using its known addresses from the nearby peers map.
pub async fn dial_peer(
    peers_map: &NearbyPeersMap,
    peer_id_str: &str,
    swarm: &mut Swarm<StoaBehaviour>,
) {
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
