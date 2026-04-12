use crate::file_transfer::{self, ActiveTransfer, TransferDirection, TransferStatus};
use crate::messages::{self, StoredMessage};
use crate::protocol::{StoaRequest, StoaResponse};
use base64::{engine::general_purpose::STANDARD as B64, Engine};
use libp2p::request_response;
use libp2p::{PeerId, Swarm};
use serde::Serialize;
use std::collections::HashMap;
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
            let transfer = ActiveTransfer {
                transfer_id: transfer_id.clone(),
                peer_id: sender_id.clone(),
                file_name: file_name.clone(),
                file_size,
                checksum,
                chunk_count,
                chunks_done: 0,
                direction: TransferDirection::Download,
                status: TransferStatus::Transferring,
                chunks: vec![],
                received_chunks: HashMap::new(),
                dest_path: dest,
            };
            active_transfers.insert(transfer_id.clone(), transfer);

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
                    transfer_id,
                    peer_id: sender_id,
                    file_name,
                    file_size,
                    direction: "download".into(),
                    chunk_count,
                    sender_name,
                },
            );
        }
        StoaRequest::FileChunk {
            transfer_id,
            chunk_index,
            data_b64,
            is_last,
        } => {
            let sender_id = peer.to_string();

            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                // Decode chunk and store
                if let Ok(data) = B64.decode(&data_b64) {
                    transfer.received_chunks.insert(chunk_index, data);
                    transfer.chunks_done = chunk_index + 1;

                    // Send ack
                    let response = StoaResponse::ChunkAck {
                        transfer_id: transfer_id.clone(),
                        chunk_index,
                    };
                    let _ = swarm
                        .behaviour_mut()
                        .messaging
                        .send_response(channel, response);

                    // Emit progress
                    #[derive(Serialize, Clone)]
                    struct ProgressEvent {
                        transfer_id: String,
                        chunk_index: u32,
                        chunk_count: u32,
                        progress: f64,
                    }
                    let progress = (chunk_index + 1) as f64 / transfer.chunk_count as f64;
                    let _ = app_handle.emit(
                        "file-transfer-progress",
                        &ProgressEvent {
                            transfer_id: transfer_id.clone(),
                            chunk_index,
                            chunk_count: transfer.chunk_count,
                            progress,
                        },
                    );

                    // If last chunk, assemble and save
                    if is_last {
                        match file_transfer::assemble_and_save(transfer) {
                            Ok(path) => {
                                transfer.status = TransferStatus::Complete;
                                println!(
                                    "[Stoa File] Transfer complete: {} -> {:?}",
                                    transfer.file_name, path
                                );

                                #[derive(Serialize, Clone)]
                                struct CompleteEvent {
                                    transfer_id: String,
                                    peer_id: String,
                                    file_name: String,
                                    file_path: String,
                                    file_size: u64,
                                    direction: String,
                                }
                                let _ = app_handle.emit(
                                    "file-transfer-complete",
                                    &CompleteEvent {
                                        transfer_id: transfer_id.clone(),
                                        peer_id: sender_id,
                                        file_name: transfer.file_name.clone(),
                                        file_path: path.to_string_lossy().to_string(),
                                        file_size: transfer.file_size,
                                        direction: "download".into(),
                                    },
                                );
                            }
                            Err(e) => {
                                transfer.status = TransferStatus::Failed;
                                eprintln!("[Stoa File] Assembly failed: {e}");
                            }
                        }
                        // Clean up
                        active_transfers.remove(&transfer_id);
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
            println!("[Stoa File] FileAccepted for {transfer_id} — sending chunks");

            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                transfer.status = TransferStatus::Transferring;
                let target = *peer;

                // Send all chunks sequentially
                let chunk_count = transfer.chunks.len();
                for (i, chunk_b64) in transfer.chunks.iter().enumerate() {
                    let is_last = i == chunk_count - 1;
                    let req = StoaRequest::FileChunk {
                        transfer_id: transfer_id.clone(),
                        chunk_index: i as u32,
                        data_b64: chunk_b64.clone(),
                        is_last,
                    };
                    swarm
                        .behaviour_mut()
                        .messaging
                        .send_request(&target, req);
                }
                println!(
                    "[Stoa File] Queued {} chunks for {}",
                    chunk_count, transfer_id
                );
            }
        }
        StoaResponse::FileRejected { transfer_id } => {
            println!("[Stoa File] FileRejected for {transfer_id}");
            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                transfer.status = TransferStatus::Cancelled;
            }
            active_transfers.remove(&transfer_id);
        }
        StoaResponse::ChunkAck {
            transfer_id,
            chunk_index,
        } => {
            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                transfer.chunks_done = chunk_index + 1;

                // Emit progress
                #[derive(Serialize, Clone)]
                struct ProgressEvent {
                    transfer_id: String,
                    chunk_index: u32,
                    chunk_count: u32,
                    progress: f64,
                }
                let progress = (chunk_index + 1) as f64 / transfer.chunk_count as f64;
                let _ = app_handle.emit(
                    "file-transfer-progress",
                    &ProgressEvent {
                        transfer_id: transfer_id.clone(),
                        chunk_index,
                        chunk_count: transfer.chunk_count,
                        progress,
                    },
                );

                // If all chunks acked, transfer is complete
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

                    active_transfers.remove(&transfer_id);
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
