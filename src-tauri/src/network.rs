use crate::contacts::{self, Contact};
use crate::messages::{self, StoredMessage};
use crate::protocol::{StoaRequest, StoaResponse};
use futures::StreamExt;
use libp2p::identity::Keypair;
use libp2p::request_response::{self, ProtocolSupport};
use libp2p::swarm::SwarmEvent;
use libp2p::{mdns, Multiaddr, PeerId, StreamProtocol, Swarm, Transport};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::str::FromStr;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

/// Info about a discovered LAN peer. Sent to the frontend.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NearbyPeer {
    pub peer_id: String,
    pub addresses: Vec<String>,
    /// Display name broadcast by the peer (via NameAnnounce)
    pub name: Option<String>,
}

/// Commands the frontend can send to the network task.
#[derive(Debug)]
pub enum NetworkCommand {
    /// Send a contact request to a peer
    SendContactRequest {
        peer_id: String,
        our_name: String,
        our_peer_id: String,
    },
    /// Send a chat message to a contact
    SendMessage {
        peer_id: String,
        message_id: String,
        content: String,
        sender_name: String,
    },
    /// Shut down the network task
    Shutdown,
}

/// Shared state tracking discovered peers.
pub type NearbyPeersMap = Arc<Mutex<HashMap<String, NearbyPeer>>>;

/// Shared list of known contacts for auto-dialing.
pub type ContactsList = Arc<Mutex<Vec<Contact>>>;

/// The combined network behaviour — mDNS + request-response.
#[derive(libp2p::swarm::NetworkBehaviour)]
struct StoaBehaviour {
    mdns: mdns::tokio::Behaviour,
    messaging: request_response::json::Behaviour<StoaRequest, StoaResponse>,
}

/// A message waiting for a connection to be established.
struct PendingMessage {
    peer_id: PeerId,
    request: StoaRequest,
}

/// Check if an address is routable (not loopback or link-local).
fn is_routable(addr_str: &str) -> bool {
    // Filter out loopback (127.x.x.x) and link-local (169.254.x.x)
    !addr_str.contains("/ip4/127.") && !addr_str.contains("/ip4/169.254.")
}

/// Get a formatted timestamp for log lines.
fn ts() -> String {
    chrono::Local::now().format("%H:%M:%S%.3f").to_string()
}

/// Spawn the libp2p swarm on a background Tokio task.
pub fn spawn_network(
    keypair: Keypair,
    app_handle: AppHandle,
    contacts: ContactsList,
    our_name: String,
) -> Result<(mpsc::Sender<NetworkCommand>, NearbyPeersMap, JoinHandle<()>), String> {
    let peer_id = PeerId::from(keypair.public());

    let mdns_config = mdns::Config {
        query_interval: std::time::Duration::from_secs(3),
        ttl: std::time::Duration::from_secs(10),
        ..Default::default()
    };

    let mdns_behaviour = mdns::tokio::Behaviour::new(mdns_config, peer_id)
        .map_err(|e| format!("Failed to create mDNS behaviour: {e}"))?;

    let msg_protocol = StreamProtocol::new("/stoa/msg/1.0.0");
    let msg_behaviour = request_response::json::Behaviour::<StoaRequest, StoaResponse>::new(
        [(msg_protocol, ProtocolSupport::Full)],
        request_response::Config::default(),
    );

    let behaviour = StoaBehaviour {
        mdns: mdns_behaviour,
        messaging: msg_behaviour,
    };

    let mut swarm = Swarm::new(
        libp2p::tcp::tokio::Transport::new(libp2p::tcp::Config::default())
            .upgrade(libp2p::core::upgrade::Version::V1)
            .authenticate(
                libp2p::noise::Config::new(&keypair)
                    .map_err(|e| format!("Noise config error: {e}"))?,
            )
            .multiplex(libp2p::yamux::Config::default())
            .boxed(),
        behaviour,
        peer_id,
        libp2p::swarm::Config::with_tokio_executor()
            // Connections close after 30s idle — saves resources.
            // The pending queue + dial-on-send handles reconnection.
            .with_idle_connection_timeout(std::time::Duration::from_secs(30)),
    );

    swarm
        .listen_on("/ip4/0.0.0.0/tcp/0".parse().unwrap())
        .map_err(|e| format!("Failed to listen: {e}"))?;

    let (cmd_tx, mut cmd_rx) = mpsc::channel::<NetworkCommand>(64);
    let nearby_peers: NearbyPeersMap = Arc::new(Mutex::new(HashMap::new()));
    let peers_clone = nearby_peers.clone();

    let handle = tokio::spawn(async move {
        let mut pending_messages: Vec<PendingMessage> = vec![];

        loop {
            tokio::select! {
                event = swarm.select_next_some() => {
                    match event {
                        // ── mDNS Discovery ──────────────────────────────────
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Mdns(
                            mdns::Event::Discovered(list),
                        )) => {
                            for (discovered_peer, addr) in list {
                                let pid = discovered_peer.to_string();
                                let addr_str = addr.to_string();

                                // Only store routable addresses
                                if !is_routable(&addr_str) {
                                    continue;
                                }

                                let mut peers = peers_clone.lock().await;
                                let entry = peers.entry(pid.clone()).or_insert_with(|| NearbyPeer {
                                    peer_id: pid.clone(),
                                    addresses: vec![],
                                    name: None,
                                });
                                if !entry.addresses.contains(&addr_str) {
                                    entry.addresses.push(addr_str);
                                }
                                let peer_info = entry.clone();
                                drop(peers);

                                let _ = app_handle.emit("peer-discovered", &peer_info);

                                // Auto-dial known contacts — both sides dial,
                                // libp2p handles dedup internally
                                let cts = contacts.lock().await;
                                let is_contact = cts.iter().any(|c| c.peer_id == pid);
                                drop(cts);
                                if is_contact && !swarm.is_connected(&discovered_peer) {
                                    // Add address to the swarm's address book
                                    swarm.add_peer_address(discovered_peer, addr.clone());
                                    // Dial by PeerId — libp2p deduplicates concurrent dials
                                    let _ = swarm.dial(discovered_peer);
                                }
                            }
                        }
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Mdns(
                            mdns::Event::Expired(list),
                        )) => {
                            for (expired_peer, _addr) in list {
                                let pid = expired_peer.to_string();
                                // Don't remove peers that are still connected
                                if swarm.is_connected(&expired_peer) {
                                    continue;
                                }
                                let mut peers = peers_clone.lock().await;
                                peers.remove(&pid);
                                drop(peers);
                                let _ = app_handle.emit("peer-expired", &pid);
                            }
                        }

                        // ── Connection Lifecycle ────────────────────────────
                        SwarmEvent::ConnectionEstablished { peer_id: connected_peer, .. } => {
                            let pid = connected_peer.to_string();
                            println!("[{} Stoa] Connection established with {pid}", ts());

                            // Notify frontend if this is a contact
                            let cts = contacts.lock().await;
                            let is_contact = cts.iter().any(|c| c.peer_id == pid);
                            drop(cts);
                            if is_contact {
                                let _ = app_handle.emit("contact-online", &pid);
                            }

                            // Send our name to the peer
                            swarm.behaviour_mut().messaging.send_request(
                                &connected_peer,
                                StoaRequest::NameAnnounce { name: our_name.clone() },
                            );

                            // Flush pending messages for this peer
                            let mut remaining = vec![];
                            for pm in pending_messages.drain(..) {
                                if pm.peer_id == connected_peer {
                                    swarm.behaviour_mut().messaging.send_request(&pm.peer_id, pm.request);
                                    println!("[{} Stoa] Flushed queued message to {pid}", ts());
                                } else {
                                    remaining.push(pm);
                                }
                            }
                            pending_messages = remaining;
                        }

                        SwarmEvent::ConnectionClosed { peer_id: disconnected_peer, .. } => {
                            let pid = disconnected_peer.to_string();
                            println!("[{} Stoa] Connection closed with {pid}", ts());

                            let cts = contacts.lock().await;
                            let is_contact = cts.iter().any(|c| c.peer_id == pid);
                            drop(cts);
                            if is_contact {
                                let _ = app_handle.emit("contact-offline", &pid);
                            }
                        }

                        SwarmEvent::OutgoingConnectionError { peer_id, error, .. } => {
                            println!("[{} Stoa] Dial failed to {peer_id:?}: {error}", ts());
                            // Remove stale address from nearby map if handshake failed
                            if let Some(pid) = peer_id {
                                let pid_str = pid.to_string();
                                let error_str = format!("{error}");
                                // Extract the failed address from the error message and remove it
                                let mut peers = peers_clone.lock().await;
                                if let Some(peer_info) = peers.get_mut(&pid_str) {
                                    peer_info.addresses.retain(|addr| !error_str.contains(addr));
                                }
                                drop(peers);
                            }
                        }

                        // ── Incoming Messages ───────────────────────────────
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Messaging(
                            request_response::Event::Message { peer, message, .. },
                        )) => {
                            match message {
                                request_response::Message::Request {
                                    request, channel, ..
                                } => {
                                    handle_incoming_request(
                                        &app_handle,
                                        &peer,
                                        request,
                                        channel,
                                        &mut swarm,
                                        &our_name,
                                        &peers_clone,
                                        &contacts,
                                    )
                                    .await;
                                }
                                request_response::Message::Response {
                                    response,
                                    request_id,
                                    ..
                                } => {
                                    handle_incoming_response(
                                        &app_handle,
                                        &peer,
                                        response,
                                        request_id,
                                    )
                                    .await;
                                }
                            }
                        }

                        // ── Send Failures ───────────────────────────────────
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Messaging(
                            request_response::Event::OutboundFailure { peer, error, .. },
                        )) => {
                            println!("[{} Stoa] OutboundFailure to {peer}: {error}", ts());
                        }

                        SwarmEvent::Behaviour(StoaBehaviourEvent::Messaging(
                            request_response::Event::InboundFailure { peer, error, .. },
                        )) => {
                            println!("[{} Stoa] InboundFailure from {peer}: {error}", ts());
                        }

                        SwarmEvent::NewListenAddr { address, .. } => {
                            println!("[{} Stoa] Listening on {address}", ts());
                        }
                        _ => {}
                    }
                }

                // ── Commands from Frontend ──────────────────────────────
                cmd = cmd_rx.recv() => {
                    match cmd {
                        Some(NetworkCommand::SendContactRequest {
                            peer_id,
                            our_name,
                            our_peer_id,
                        }) => {
                            let req = StoaRequest::ContactRequest {
                                from_peer_id: our_peer_id,
                                from_name: our_name,
                            };

                            if let Ok(target) = PeerId::from_str(&peer_id) {
                                if swarm.is_connected(&target) {
                                    swarm.behaviour_mut().messaging.send_request(&target, req);
                                    println!("[{} Stoa] Sent contact request to {peer_id}", ts());
                                } else {
                                    dial_peer(&peers_clone, &peer_id, &mut swarm).await;
                                    pending_messages.push(PendingMessage {
                                        peer_id: target,
                                        request: req,
                                    });
                                    println!("[{} Stoa] Queued contact request for {peer_id} (connecting...)", ts());
                                }
                            }
                        }

                        Some(NetworkCommand::SendMessage {
                            peer_id,
                            message_id,
                            content,
                            sender_name,
                        }) => {
                            let timestamp = chrono::Utc::now().timestamp();
                            let req = StoaRequest::ChatMessage {
                                id: message_id.clone(),
                                content: content.clone(),
                                timestamp,
                                sender_name,
                            };

                            // Persist outgoing message regardless of connection state
                            let msg = StoredMessage {
                                id: message_id.clone(),
                                sender_id: "me".into(),
                                content: content.clone(),
                                timestamp,
                                delivered: false,
                            };
                            let _ = messages::save_message(&peer_id, &msg);

                            if let Ok(target) = PeerId::from_str(&peer_id) {
                                if swarm.is_connected(&target) {
                                    swarm.behaviour_mut().messaging.send_request(&target, req);
                                } else {
                                    // Only dial if we don't already have pending messages for this peer
                                    // (avoids duplicate dial attempts → os error 10048 on Windows)
                                    let already_dialing = pending_messages.iter().any(|pm| pm.peer_id == target);
                                    if !already_dialing {
                                        dial_peer(&peers_clone, &peer_id, &mut swarm).await;
                                    }
                                    pending_messages.push(PendingMessage {
                                        peer_id: target,
                                        request: req,
                                    });
                                    println!("[{} Stoa] Queued message for {peer_id} (connecting...)", ts());
                                }
                            }
                        }

                        Some(NetworkCommand::Shutdown) | None => {
                            println!("[{} Stoa] Shutting down network task.", ts());
                            break;
                        }
                    }
                }
            }
        }
    });

    Ok((cmd_tx, nearby_peers, handle))
}

/// Handle an incoming request from a remote peer.
async fn handle_incoming_request(
    app_handle: &AppHandle,
    peer: &PeerId,
    request: StoaRequest,
    channel: request_response::ResponseChannel<StoaResponse>,
    swarm: &mut Swarm<StoaBehaviour>,
    our_name: &str,
    peers_map: &NearbyPeersMap,
    contacts_list: &ContactsList,
) {
    match request {
        StoaRequest::NameAnnounce { name } => {
            let pid = peer.to_string();
            println!("[{} Stoa] Name announce from {pid}: {name}", ts());

            // Update the nearby peers map with the broadcast name
            let mut peers = peers_map.lock().await;
            if let Some(peer_info) = peers.get_mut(&pid) {
                peer_info.name = Some(name.clone());
                let updated = peer_info.clone();
                drop(peers);
                let _ = app_handle.emit("peer-discovered", &updated);
            } else {
                drop(peers);
            }

            // Update contact broadcast name if they're a contact
            let mut cts = contacts_list.lock().await;
            let _ = contacts::update_broadcast_name(&mut cts, &pid, name);
            drop(cts);

            let _ = swarm
                .behaviour_mut()
                .messaging
                .send_response(channel, StoaResponse::NameAck);
        }
        StoaRequest::ContactRequest {
            from_peer_id,
            from_name,
        } => {
            println!("[{} Stoa] Contact request from {from_name} ({from_peer_id})", ts());

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
            println!("[{} Stoa] Message from {sender_name}: {content}", ts());

            let msg = StoredMessage {
                id: id.clone(),
                sender_id: sender_id.clone(),
                content: content.clone(),
                timestamp,
                delivered: true,
            };
            let _ = messages::save_message(&sender_id, &msg);

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

            let response = StoaResponse::MessageAck { id };
            let _ = swarm
                .behaviour_mut()
                .messaging
                .send_response(channel, response);
        }
    }
}

/// Handle an incoming response to our request.
async fn handle_incoming_response(
    app_handle: &AppHandle,
    peer: &PeerId,
    response: StoaResponse,
    _request_id: request_response::OutboundRequestId,
) {
    match response {
        StoaResponse::ContactAccepted { name } => {
            let pid = peer.to_string();
            println!("[{} Stoa] Contact accepted by {name} ({pid})", ts());

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
            println!("[{} Stoa] Contact rejected by {pid}", ts());
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
        StoaResponse::NameAck => {
            // Name announce acknowledged, nothing to do
        }
    }
}

/// Dial a peer using only routable addresses from the nearby peers map.
/// Adds addresses to the swarm's address book and dials by PeerId,
/// letting libp2p handle dedup and connection management.
async fn dial_peer(
    peers_map: &NearbyPeersMap,
    peer_id_str: &str,
    swarm: &mut Swarm<StoaBehaviour>,
) {
    if let Ok(target) = PeerId::from_str(peer_id_str) {
        let peers = peers_map.lock().await;
        if let Some(peer_info) = peers.get(peer_id_str) {
            for addr_str in &peer_info.addresses {
                if is_routable(addr_str) {
                    if let Ok(addr) = addr_str.parse::<Multiaddr>() {
                        swarm.add_peer_address(target, addr);
                    }
                }
            }
        }
        drop(peers);
        // Dial by PeerId — libp2p picks the best address and deduplicates
        let _ = swarm.dial(target);
    }
}
