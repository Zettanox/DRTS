use crate::contacts::Contact;
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
#[derive(Debug)]
struct PendingMessage {
    peer_id: PeerId,
    request: StoaRequest,
    /// Original peer_id string for persistence
    peer_id_str: String,
    /// Message ID for tracking (if chat message)
    message_id: Option<String>,
    /// Content for persistence (if chat message)
    content: Option<String>,
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
        // Query every 3 seconds — fast enough for discovery
        query_interval: std::time::Duration::from_secs(3),
        // 10 second TTL — prevents blinking from missed mDNS packets
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
            // Keep idle connections alive for 5 minutes
            .with_idle_connection_timeout(std::time::Duration::from_secs(300)),
    );

    // Listen on all interfaces, OS-assigned port
    swarm
        .listen_on("/ip4/0.0.0.0/tcp/0".parse().unwrap())
        .map_err(|e| format!("Failed to listen: {e}"))?;

    let (cmd_tx, mut cmd_rx) = mpsc::channel::<NetworkCommand>(64);
    let nearby_peers: NearbyPeersMap = Arc::new(Mutex::new(HashMap::new()));
    let peers_clone = nearby_peers.clone();

    let handle = tokio::spawn(async move {
        // Pending messages waiting for connection establishment
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

                                // Track peer
                                let mut peers = peers_clone.lock().await;
                                let entry = peers.entry(pid.clone()).or_insert_with(|| NearbyPeer {
                                    peer_id: pid.clone(),
                                    addresses: vec![],
                                });
                                if !entry.addresses.contains(&addr_str) {
                                    entry.addresses.push(addr_str);
                                }
                                let peer_info = entry.clone();
                                drop(peers);

                                let _ = app_handle.emit("peer-discovered", &peer_info);

                                // Auto-dial known contacts (connection events handle online status)
                                let cts = contacts.lock().await;
                                let is_contact = cts.iter().any(|c| c.peer_id == pid);
                                drop(cts);
                                if is_contact && !swarm.is_connected(&discovered_peer) {
                                    let _ = swarm.dial(addr);
                                }
                            }
                        }
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Mdns(
                            mdns::Event::Expired(list),
                        )) => {
                            for (expired_peer, _addr) in list {
                                let pid = expired_peer.to_string();
                                let mut peers = peers_clone.lock().await;
                                peers.remove(&pid);
                                drop(peers);
                                let _ = app_handle.emit("peer-expired", &pid);
                            }
                        }

                        // ── Connection Events ───────────────────────────────
                        SwarmEvent::ConnectionEstablished { peer_id: connected_peer, .. } => {
                            let pid = connected_peer.to_string();
                            println!("[Stoa Network] Connection established with {pid}");

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
                                    swarm.behaviour_mut().messaging.send_request(&pm.peer_id, pm.request);
                                    println!("[Stoa Network] Flushed queued message to {pid}");
                                } else {
                                    remaining.push(pm);
                                }
                            }
                            pending_messages = remaining;
                        }

                        SwarmEvent::ConnectionClosed { peer_id: disconnected_peer, .. } => {
                            let pid = disconnected_peer.to_string();
                            println!("[Stoa Network] Connection closed with {pid}");

                            let cts = contacts.lock().await;
                            let is_contact = cts.iter().any(|c| c.peer_id == pid);
                            drop(cts);
                            if is_contact {
                                let _ = app_handle.emit("contact-offline", &pid);
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

                        SwarmEvent::NewListenAddr { address, .. } => {
                            println!("[Stoa Network] Listening on {address}");
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
                                    println!("[Stoa Network] Sent contact request to {peer_id}");
                                } else {
                                    // Dial and queue
                                    dial_peer(&peers_clone, &peer_id, &mut swarm).await;
                                    pending_messages.push(PendingMessage {
                                        peer_id: target,
                                        request: req,
                                        peer_id_str: peer_id.clone(),
                                        message_id: None,
                                        content: None,
                                    });
                                    println!("[Stoa Network] Queued contact request for {peer_id} (connecting...)");
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
                                sender_name: sender_name.clone(),
                            };

                            if let Ok(target) = PeerId::from_str(&peer_id) {
                                if swarm.is_connected(&target) {
                                    swarm.behaviour_mut().messaging.send_request(&target, req);
                                    // Persist outgoing message
                                    let msg = StoredMessage {
                                        id: message_id,
                                        sender_id: "me".into(),
                                        content,
                                        timestamp,
                                        delivered: false,
                                    };
                                    let _ = messages::save_message(&peer_id, &msg);
                                } else {
                                    // Persist and queue
                                    let msg = StoredMessage {
                                        id: message_id.clone(),
                                        sender_id: "me".into(),
                                        content: content.clone(),
                                        timestamp,
                                        delivered: false,
                                    };
                                    let _ = messages::save_message(&peer_id, &msg);

                                    dial_peer(&peers_clone, &peer_id, &mut swarm).await;
                                    pending_messages.push(PendingMessage {
                                        peer_id: target,
                                        request: req,
                                        peer_id_str: peer_id.clone(),
                                        message_id: Some(message_id),
                                        content: Some(content),
                                    });
                                    println!("[Stoa Network] Queued message for {peer_id} (connecting...)");
                                }
                            }
                        }

                        Some(NetworkCommand::Shutdown) | None => {
                            println!("[Stoa Network] Shutting down network task.");
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
) {
    match request {
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
            // Mark message as delivered
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

/// Dial a peer using its known addresses from the nearby peers map.
async fn dial_peer(
    peers_map: &NearbyPeersMap,
    peer_id_str: &str,
    swarm: &mut Swarm<StoaBehaviour>,
) {
    let peers = peers_map.lock().await;
    if let Some(peer_info) = peers.get(peer_id_str) {
        for addr_str in &peer_info.addresses {
            if let Ok(addr) = addr_str.parse::<Multiaddr>() {
                let _ = swarm.dial(addr);
            }
        }
    }
    drop(peers);
}
