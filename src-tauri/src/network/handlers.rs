use crate::messages::{self, StoredMessage};
use crate::protocol::{StoaRequest, StoaResponse};
use libp2p::request_response;
use libp2p::{PeerId, Swarm};
use serde::Serialize;
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
) {
    match response {
        StoaResponse::PeerIdentity { name } => {
            let pid = peer.to_string();
            println!("[Stoa Network] Peer {pid} identified as '{name}'");

            // Update nearby peers map with display name
            let mut peers = peers_map.lock().await;
            if let Some(peer_info) = peers.get_mut(&pid) {
                peer_info.display_name = Some(name);
                let updated = peer_info.clone();
                drop(peers);
                let _ = app_handle.emit("peer-discovered", &updated);
            }
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
