pub mod handlers;
pub mod types;

pub use types::{ContactsList, NearbyPeer, NearbyPeersMap, NetworkCommand};

use crate::protocol::{StoaRequest, StoaResponse};
use futures::StreamExt;
use libp2p::identity::Keypair;
use libp2p::request_response::{self, ProtocolSupport};
use libp2p::swarm::SwarmEvent;
use libp2p::{mdns, PeerId, StreamProtocol, Swarm, Transport};
use std::collections::HashMap;
use std::str::FromStr;
use std::sync::Arc;
use tauri::AppHandle;
use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

use crate::messages::{self, StoredMessage};
use types::PendingMessage;

/// The combined network behaviour — mDNS + request-response.
#[derive(libp2p::swarm::NetworkBehaviour)]
pub struct StoaBehaviour {
    mdns: mdns::tokio::Behaviour,
    pub messaging: request_response::json::Behaviour<StoaRequest, StoaResponse>,
}

/// Spawn the libp2p swarm on a background Tokio task.
/// The swarm runs for the lifetime of the app — visibility toggles mDNS processing,
/// not the swarm itself.
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
            .with_idle_connection_timeout(std::time::Duration::from_secs(300)),
    );

    swarm
        .listen_on("/ip4/0.0.0.0/tcp/0".parse().unwrap())
        .map_err(|e| format!("Failed to listen: {e}"))?;

    let (cmd_tx, mut cmd_rx) = mpsc::channel::<NetworkCommand>(64);
    let nearby_peers: NearbyPeersMap = Arc::new(Mutex::new(HashMap::new()));
    let peers_clone = nearby_peers.clone();

    let handle = tokio::spawn(async move {
        let mut pending_messages: Vec<PendingMessage> = vec![];
        let mut lan_visible = true;

        // Reconnection sweep interval — retries cached addresses for offline contacts
        let mut reconnect_interval = tokio::time::interval(std::time::Duration::from_secs(10));
        reconnect_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

        loop {
            tokio::select! {
                event = swarm.select_next_some() => {
                    match event {
                        // ── mDNS Discovery (only when visible) ──────────────
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Mdns(
                            mdns::Event::Discovered(list),
                        )) => {
                            if !lan_visible {
                                continue; // Ignore discovery when invisible
                            }
                            for (discovered_peer, addr) in list {
                                handlers::handle_mdns_discovered(
                                    discovered_peer,
                                    addr,
                                    &peers_clone,
                                    &contacts,
                                    &mut swarm,
                                    &app_handle,
                                ).await;
                            }
                        }
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Mdns(
                            mdns::Event::Expired(list),
                        )) => {
                            if !lan_visible {
                                continue;
                            }
                            for (expired_peer, _addr) in list {
                                handlers::handle_mdns_expired(
                                    expired_peer,
                                    &peers_clone,
                                    &app_handle,
                                ).await;
                            }
                        }

                        // ── Connection Events (always active) ───────────────
                        SwarmEvent::ConnectionEstablished { peer_id: connected_peer, .. } => {
                            handlers::handle_connection_established(
                                connected_peer,
                                &contacts,
                                &mut swarm,
                                &app_handle,
                                &mut pending_messages,
                            ).await;
                        }

                        SwarmEvent::ConnectionClosed { peer_id: disconnected_peer, .. } => {
                            handlers::handle_connection_closed(
                                disconnected_peer,
                                &contacts,
                                &app_handle,
                            ).await;
                        }

                        // ── Messaging (always active) ───────────────────────
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Messaging(
                            request_response::Event::Message { peer, message, .. },
                        )) => {
                            match message {
                                request_response::Message::Request {
                                    request, channel, ..
                                } => {
                                    handlers::handle_incoming_request(
                                        &app_handle,
                                        &peer,
                                        request,
                                        channel,
                                        &mut swarm,
                                        &our_name,
                                    ).await;
                                }
                                request_response::Message::Response {
                                    response,
                                    request_id,
                                    ..
                                } => {
                                    handlers::handle_incoming_response(
                                        &app_handle,
                                        &peer,
                                        response,
                                        request_id,
                                        &peers_clone,
                                    ).await;
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
                        Some(NetworkCommand::SetVisibility(visible)) => {
                            lan_visible = visible;
                            if visible {
                                println!("[Stoa Network] Visibility ON — mDNS active");
                            } else {
                                println!("[Stoa Network] Visibility OFF — mDNS paused, connections kept");
                                // Clear nearby peers (we're not tracking anymore)
                                let mut peers = peers_clone.lock().await;
                                peers.clear();
                                drop(peers);
                            }
                        }

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
                                    handlers::dial_peer(&peers_clone, &peer_id, &mut swarm).await;
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
                                sender_name,
                            };

                            if let Ok(target) = PeerId::from_str(&peer_id) {
                                // Always persist outgoing message
                                let msg = StoredMessage {
                                    id: message_id.clone(),
                                    sender_id: "me".into(),
                                    content: content.clone(),
                                    timestamp,
                                    delivered: false,
                                };
                                let _ = messages::save_message(&peer_id, &msg);

                                if swarm.is_connected(&target) {
                                    swarm.behaviour_mut().messaging.send_request(&target, req);
                                } else {
                                    handlers::dial_peer(&peers_clone, &peer_id, &mut swarm).await;
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

                // ── Reconnection Sweep ──────────────────────────────────
                _ = reconnect_interval.tick() => {
                    let cts = contacts.lock().await;
                    let contact_ids: Vec<String> = cts.iter().map(|c| c.peer_id.clone()).collect();
                    drop(cts);

                    for pid in &contact_ids {
                        if let Ok(target) = PeerId::from_str(pid) {
                            if !swarm.is_connected(&target) {
                                // Try cached addresses
                                handlers::dial_peer(&peers_clone, pid, &mut swarm).await;
                            }
                        }
                    }
                }
            }
        }
    });

    Ok((cmd_tx, nearby_peers, handle))
}
