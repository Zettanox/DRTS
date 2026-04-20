pub mod handlers;
pub mod types;

pub use types::{ContactsList, NearbyPeer, NearbyPeersMap, NetworkCommand, PeerConnectionMap, PeerConnectionType};

use crate::protocol::{StoaRequest, StoaResponse};
use futures::StreamExt;
use libp2p::identity::Keypair;
use libp2p::request_response::{self, ProtocolSupport};
use libp2p::swarm::SwarmEvent;
use libp2p::{dcutr, identify, mdns, relay, PeerId, StreamProtocol, Swarm, Transport};
use std::collections::HashMap;
use std::str::FromStr;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

use crate::crypto;
use crate::file_transfer::{self, ActiveTransfer, TransferDirection, TransferStatus};
use crate::groups::{self, Group};
use crate::messages::{self, StoredMessage};
use crate::relay_config::RelayConfig;
use types::PendingMessage;

/// The combined network behaviour — mDNS + request-response + relay + dcutr + identify.
#[derive(libp2p::swarm::NetworkBehaviour)]
pub struct StoaBehaviour {
    mdns: mdns::tokio::Behaviour,
    pub messaging: request_response::json::Behaviour<StoaRequest, StoaResponse>,
    relay_client: relay::client::Behaviour,
    dcutr: dcutr::Behaviour,
    identify: identify::Behaviour,
    ping: libp2p::ping::Behaviour,
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
        request_response::Config::default()
            .with_request_timeout(std::time::Duration::from_secs(120)),
    );

    // Build relay client transport.
    // The relay::client::Transport wraps plain TCP so that dialing a relay circuit
    // address (/p2p-circuit/…) is handled transparently by the swarm.
    let (relay_transport, relay_client) = relay::client::new(peer_id);

    let transport = {
        use libp2p::core::{transport::OrTransport, upgrade};
        use libp2p::dns;

        let base_tcp = libp2p::tcp::tokio::Transport::new(libp2p::tcp::Config::default());
        let dns_tcp = dns::tokio::Transport::system(base_tcp)
            .map_err(|e| format!("DNS transport error: {e}"))?;

        // Combine: relay transport for circuit addresses | DNS/TCP for direct connections
        OrTransport::new(relay_transport, dns_tcp)
            .upgrade(upgrade::Version::V1)
            .authenticate(
                libp2p::noise::Config::new(&keypair)
                    .map_err(|e| format!("Noise config error: {e}"))?,
            )
            .multiplex(libp2p::yamux::Config::default())
            .boxed()
    };

    let identify_behaviour = identify::Behaviour::new(
        identify::Config::new("/stoa/1.0.0".to_string(), keypair.public())
            .with_push_listen_addr_updates(true),
    );

    let ping_config = libp2p::ping::Config::new()
        .with_interval(std::time::Duration::from_secs(15));
    let ping_behaviour = libp2p::ping::Behaviour::new(ping_config);

    let behaviour = StoaBehaviour {
        mdns: mdns_behaviour,
        messaging: msg_behaviour,
        relay_client,
        dcutr: dcutr::Behaviour::new(peer_id),
        identify: identify_behaviour,
        ping: ping_behaviour,
    };

    let mut swarm = Swarm::new(
        transport,
        behaviour,
        peer_id,
        libp2p::swarm::Config::with_tokio_executor()
            .with_idle_connection_timeout(std::time::Duration::from_secs(300)),
    );

    swarm
        .listen_on("/ip4/0.0.0.0/tcp/0".parse().unwrap())
        .map_err(|e| format!("Failed to listen: {e}"))?;

    // Load relay configuration and dial each enabled relay
    let relay_cfg = RelayConfig::load();
    let relay_addresses = relay_cfg.enabled_addresses();
    for addr_str in &relay_addresses {
        match addr_str.parse::<libp2p::Multiaddr>() {
            Ok(mut addr) => {
                println!("[{}] [Stoa Network] Requesting relay reservation: {addr}", chrono::Local::now().format("%H:%M:%S"));
                addr.push(libp2p::multiaddr::Protocol::P2pCircuit);
                if let Err(e) = swarm.listen_on(addr) {
                    eprintln!("[{}] [Stoa Network] Failed to request relay reservation: {e}", chrono::Local::now().format("%H:%M:%S"));
                }
            }
            Err(e) => {
                eprintln!("[{}] [Stoa Network] Invalid relay address '{addr_str}': {e}", chrono::Local::now().format("%H:%M:%S"));
            }
        }
    }

    let (cmd_tx, mut cmd_rx) = mpsc::channel::<NetworkCommand>(64);
    let nearby_peers: NearbyPeersMap = Arc::new(Mutex::new(HashMap::new()));
    let peers_clone = nearby_peers.clone();

    let cmd_tx_for_loop = cmd_tx.clone();
    let handle = tokio::spawn(async move {
        let mut pending_messages: Vec<PendingMessage> = vec![];
        let mut active_connections: HashMap<String, Vec<(libp2p::core::ConnectedPoint, libp2p::swarm::ConnectionId)>> = HashMap::new();
        let mut lan_visible = true;
        let mut active_transfers: HashMap<String, ActiveTransfer> = HashMap::new();
        let mut local_groups: Vec<Group> = groups::load_groups().unwrap_or_default();
        let our_peer_id_str = peer_id.to_string();
        let conn_types: PeerConnectionMap = Arc::new(Mutex::new(HashMap::new()));

        // Reconnection sweep — retries disconnected contacts every 60s.
        let reconnect_start = tokio::time::Instant::now() + std::time::Duration::from_secs(15);
        let mut reconnect_interval = tokio::time::interval_at(reconnect_start, std::time::Duration::from_secs(60));
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
                                let pid_str = discovered_peer.to_string();
                                // mDNS confirmation overrides any earlier Relay classification
                                conn_types.lock().await.insert(pid_str, PeerConnectionType::Lan);
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
                                // Downgrade to Relay — they may still be reachable via relay circuit
                                conn_types.lock().await.insert(
                                    expired_peer.to_string(),
                                    PeerConnectionType::Relay,
                                );
                                handlers::handle_mdns_expired(
                                    expired_peer,
                                    &peers_clone,
                                    &app_handle,
                                ).await;
                            }
                        }

                        // ── Connection Events (always active) ───────────────
                        SwarmEvent::ConnectionEstablished {
                            peer_id: connected_peer,
                            connection_id,
                            endpoint,
                            num_established,
                            ..
                        } => {
                            let pid_str = connected_peer.to_string();
                            let is_relay = match &endpoint {
                                libp2p::core::ConnectedPoint::Dialer { address, .. } => {
                                    address.to_string().contains("p2p-circuit")
                                }
                                libp2p::core::ConnectedPoint::Listener { local_addr, send_back_addr } => {
                                    local_addr.to_string().contains("p2p-circuit")
                                        || send_back_addr.to_string().contains("p2p-circuit")
                                }
                            };
                            let conn_type = if is_relay { PeerConnectionType::Relay } else { PeerConnectionType::Lan };

                            // ── Dual-connection guard ──────────────────────────
                            // libp2p round-robins requests across ALL connections to a peer.
                            // dcutr creates a second (direct) connection while the relay one
                            // is still open — this causes every-other-message to be sent on
                            // the in-progress direct connection which hasn't negotiated our
                            // messaging protocol yet → UnsupportedProtocols → silent drop.
                            //
                            // Fix: keep exactly ONE connection per peer.
                            //  • New connection is relay  + already have relay/direct → close NEW one
                            //  • New connection is direct + only relay exists        → close OLD relay
                            let entry = active_connections.entry(pid_str.clone()).or_insert_with(Vec::new);

                            if num_established.get() > 1 {
                                if !is_relay {
                                    // New direct (LAN / hole-punched) connection while relay exists.
                                    // Close all OTHER connections to this peer that are relays; keep this direct one.
                                    println!("[{}] [Stoa Network] ⚡ Direct connection to {pid_str} — closing any prior relay circuits",
                                        chrono::Local::now().format("%H:%M:%S"));
                                    for (old_ep, old_id) in entry.iter() {
                                        let old_is_relay = match old_ep {
                                            libp2p::core::ConnectedPoint::Dialer { address, .. } => address.to_string().contains("p2p-circuit"),
                                            libp2p::core::ConnectedPoint::Listener { local_addr, send_back_addr } => local_addr.to_string().contains("p2p-circuit") || send_back_addr.to_string().contains("p2p-circuit"),
                                        };
                                        if old_is_relay {
                                            swarm.close_connection(*old_id);
                                        }
                                    }
                                } else {
                                    // A new Relay connection when we already have a connection (Relay or Direct).
                                    // To prevent "Mutual Annihilation" where both peers drop the connection,
                                    // we deterministically assign the "killer" role to the peer with the greater PeerId.
                                    if our_peer_id_str > pid_str {
                                        println!("[{}] [Stoa Network] Closing redundant relay connection to {pid_str} (Tie-breaker won)",
                                            chrono::Local::now().format("%H:%M:%S"));
                                        swarm.close_connection(connection_id);
                                        continue;
                                    }
                                }
                            }

                            entry.push((endpoint.clone(), connection_id));

                            println!("[{}] [Stoa Network] Connection established with {pid_str} ({})",
                                chrono::Local::now().format("%H:%M:%S"),
                                if !is_relay { "LAN" } else { "Relay" });
                            conn_types.lock().await.insert(pid_str, conn_type);

                            handlers::handle_connection_established(
                                connected_peer,
                                &contacts,
                                &mut swarm,
                                &app_handle,
                                &mut pending_messages,
                            ).await;

                            // Auto-initiate E2E key exchange for contacts without a session
                            let pid = connected_peer.to_string();
                            let cts = contacts.lock().await;
                            let is_contact = cts.iter().any(|c| c.peer_id == pid);
                            drop(cts);
                            if is_contact && !crypto::has_session(&pid) {
                                if let Ok(our_pk_hex) = crypto::our_x25519_public_key_hex(&keypair) {
                                    println!("[{}] [Stoa Crypto] Initiating key exchange with {pid}", chrono::Local::now().format("%H:%M:%S"));
                                    swarm.behaviour_mut().messaging.send_request(
                                        &connected_peer,
                                        StoaRequest::KeyExchange {
                                            x25519_public_key_hex: our_pk_hex,
                                        },
                                    );
                                }
                            }
                        }


                        SwarmEvent::ConnectionClosed { peer_id: disconnected_peer, connection_id, endpoint, num_established, cause } => {
                            let pid_str = disconnected_peer.to_string();
                            if let Some(conns) = active_connections.get_mut(&pid_str) {
                                conns.retain(|(_, id)| *id != connection_id);
                                if conns.is_empty() {
                                    active_connections.remove(&pid_str);
                                }
                            }

                            if num_established == 0 {
                                conn_types.lock().await.remove(&pid_str);
                                handlers::handle_connection_closed(
                                    disconnected_peer,
                                    &contacts,
                                    &app_handle,
                                ).await;

                                // Auto-reconnect proactively for seamless Internet <-> LAN handoffs
                                let cts = contacts.lock().await;
                                let is_contact = cts.iter().any(|c| c.peer_id == pid_str);
                                drop(cts);
                                if is_contact {
                                    println!("[{}] [Stoa Network] Graceful handoff: Proactively redialing contact {pid_str} after disconnect", chrono::Local::now().format("%H:%M:%S"));
                                    handlers::dial_peer(&peers_clone, &contacts, &pid_str, &mut swarm).await;
                                }
                            }
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
                                        &mut active_transfers,
                                        &keypair,
                                        &mut local_groups,
                                        &our_peer_id_str,
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
                                        &mut active_transfers,
                                        &mut swarm,
                                        &keypair,
                                    ).await;
                                }
                            }
                        }

                        // ── Request/Response Failures ───────────────────────
                        // OutboundFailure: a request WE SENT failed to deliver.
                        // This is the root cause of stalled file transfers:
                        // FetchChunk requests sent by the receiver can fail silently
                        // over relay substreams, causing the sender to never respond.
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Messaging(
                            request_response::Event::OutboundFailure { peer, error, .. },
                        )) => {
                            eprintln!("[{}] [Stoa Network] ⚠ Outbound request to {} failed ({error:?}) — checking for stalled transfers",
                                chrono::Local::now().format("%H:%M:%S"), peer);
                            handlers::handle_outbound_failure(
                                &peer,
                                &mut active_transfers,
                                &mut swarm,
                            ).await;
                        }

                        // InboundFailure: a response WE SENT back failed to reach the requester.
                        // Log only — the requester's OutboundFailure will handle retry.
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Messaging(
                            request_response::Event::InboundFailure { peer, error, .. },
                        )) => {
                            eprintln!("[{}] [Stoa Network] ⚠ Inbound request from {} failed ({error:?})",
                                chrono::Local::now().format("%H:%M:%S"), peer);
                        }

                        // ── Relay Client Events ─────────────────────────────
                        SwarmEvent::Behaviour(StoaBehaviourEvent::RelayClient(
                            relay::client::Event::ReservationReqAccepted { relay_peer_id, .. },
                        )) => {
                            println!("[{}] [Stoa Network] Relay reservation accepted from {relay_peer_id}", chrono::Local::now().format("%H:%M:%S"));
                            let _ = app_handle.emit("relay-connected", relay_peer_id.to_string());
                        }
                        SwarmEvent::Behaviour(StoaBehaviourEvent::RelayClient(event)) => {
                            // covers OutboundCircuitEstablished, InboundCircuitEstablished, etc.
                            println!("[{}] [Stoa Network] Relay client event: {event:?}", chrono::Local::now().format("%H:%M:%S"));
                        }

                        // ── DCUtR Hole Punching Events ──────────────────────
                        // dcutr::Event is a struct: { remote_peer_id, result: Result<ConnectionId, Error> }
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Dcutr(event)) => {
                            match event.result {
                                Ok(_) => {
                                    println!("[{}] [Stoa Network] ⚡ Hole punch succeeded with {}", chrono::Local::now().format("%H:%M:%S"), event.remote_peer_id);
                                    let _ = app_handle.emit("peer-direct-connection", event.remote_peer_id.to_string());
                                }
                                Err(e) => {
                                    println!("[{}] [Stoa Network] Hole punch failed with {} ({e:?}) — staying on relay", chrono::Local::now().format("%H:%M:%S"), event.remote_peer_id);
                                }
                            }
                        }

                        // ── Identify Events (required by relay + dcutr) ─────
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Identify(
                            identify::Event::Received { peer_id: identified_peer, info, .. },
                        )) => {
                            // Only add relay-circuit addresses to the address book.
                            // Adding LAN or raw NAT'd IPs causes direct-dial attempts that usually fail over the internet.
                            for addr in &info.listen_addrs {
                                let addr_str = addr.to_string();
                                if addr_str.contains("p2p-circuit") {
                                    swarm.add_peer_address(identified_peer, addr.clone());
                                }
                            }
                        }
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Identify(_)) => {}
                        SwarmEvent::Behaviour(StoaBehaviourEvent::Ping(_)) => {}

                        SwarmEvent::NewListenAddr { address, .. } => {
                            println!("[{}] [Stoa Network] Listening on {address}", chrono::Local::now().format("%H:%M:%S"));
                        }
                        SwarmEvent::OutgoingConnectionError { peer_id, error, .. } => {
                            // Suppress hole-punch failures for already-connected peers — dcutr
                            // automatically tries to upgrade relay→direct and failing is normal.
                            let is_connected = peer_id
                                .and_then(|p| if swarm.is_connected(&p) { Some(()) } else { None })
                                .is_some();
                            if !is_connected {
                                eprintln!("[{}] [Stoa Network] ❌ Connection failed to {:?}: {error}",
                                    chrono::Local::now().format("%H:%M:%S"), peer_id);
                            }
                        }
                        SwarmEvent::IncomingConnectionError { error, .. } => {
                            eprintln!("[{}] [Stoa Network] ❌ Incoming connection error: {error}", chrono::Local::now().format("%H:%M:%S"));
                        }
                        SwarmEvent::ListenerError { listener_id, error } => {
                            eprintln!("[{}] [Stoa Network] ❌ Listener {listener_id:?} error: {error}", chrono::Local::now().format("%H:%M:%S"));
                        }
                        SwarmEvent::ListenerClosed { listener_id, reason, .. } => {
                            eprintln!("[{}] [Stoa Network] ⚠ Listener {listener_id:?} closed: {reason:?}", chrono::Local::now().format("%H:%M:%S"));
                        }
                        SwarmEvent::Dialing { peer_id, .. } => {
                            println!("[{}] [Stoa Network] 📡 Dialing {:?}...", chrono::Local::now().format("%H:%M:%S"), peer_id);
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
                                println!("[{}] [Stoa Network] Visibility ON — mDNS active", chrono::Local::now().format("%H:%M:%S"));

                                // Repopulate nearby peers from currently connected peers
                                // (mDNS won't re-fire for peers it already knows about internally)
                                let connected: Vec<PeerId> = swarm.connected_peers().cloned().collect();
                                for cp in &connected {
                                    let pid = cp.to_string();
                                    let mut peers = peers_clone.lock().await;
                                    if !peers.contains_key(&pid) {
                                        // Get addresses from the swarm's address book
                                        let addrs: Vec<String> = swarm
                                            .external_addresses()
                                            .map(|a| a.to_string())
                                            .collect();
                                        peers.insert(pid.clone(), NearbyPeer {
                                            peer_id: pid.clone(),
                                            addresses: addrs,
                                            display_name: None,
                                        });
                                    }
                                    drop(peers);

                                    // Re-send WhoAreYou to refresh display names
                                    swarm.behaviour_mut().messaging.send_request(
                                        cp,
                                        StoaRequest::WhoAreYou,
                                    );
                                }
                            } else {
                                println!("[{}] [Stoa Network] Visibility OFF — mDNS paused, connections kept", chrono::Local::now().format("%H:%M:%S"));
                                // Clear nearby peers (we're not tracking anymore)
                                let mut peers = peers_clone.lock().await;
                                peers.clear();
                                drop(peers);
                            }
                        }

                        Some(NetworkCommand::DialPeer { peer_id, relay_addrs }) => {
                            if let Ok(target) = PeerId::from_str(&peer_id) {
                                if !swarm.is_connected(&target) {
                                    println!("[{}] [Stoa Network] Initiating circuit relay dial to {peer_id}", chrono::Local::now().format("%H:%M:%S"));
                                    for addr_str in relay_addrs {
                                        // A valid circuit relay address looks like: /ip4/.../tcp/4001/p2p/{relay_id}/p2p-circuit/p2p/{peer_id}
                                        let circuit_addr = format!("{}/p2p-circuit/p2p/{}", addr_str, peer_id);
                                        if let Ok(maddr) = circuit_addr.parse::<libp2p::Multiaddr>() {
                                            println!("[{}] [Stoa Network] Dialing relay circuit: {}", chrono::Local::now().format("%H:%M:%S"), circuit_addr);
                                            let _ = swarm.dial(maddr);
                                        }
                                    }
                                }
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
                                    println!("[{}] [Stoa Network] Sent contact request to {peer_id}", chrono::Local::now().format("%H:%M:%S"));
                                } else {
                                    handlers::dial_peer(&peers_clone, &contacts, &peer_id, &mut swarm).await;
                                    pending_messages.push(PendingMessage {
                                        peer_id: target,
                                        request: req,
                                        peer_id_str: peer_id.clone(),
                                        message_id: None,
                                        content: None,
                                    });
                                    println!("[{}] [Stoa Network] Queued contact request for {peer_id} (connecting...)", chrono::Local::now().format("%H:%M:%S"));
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
                                    file_info: None,
                                };
                                let _ = messages::save_message(&peer_id, &msg);

                                if swarm.is_connected(&target) {
                                    let encrypted_req = maybe_encrypt_request(&peer_id, req);
                                    swarm.behaviour_mut().messaging.send_request(&target, encrypted_req);
                                } else {
                                    handlers::dial_peer(&peers_clone, &contacts, &peer_id, &mut swarm).await;
                                    pending_messages.push(PendingMessage {
                                        peer_id: target,
                                        request: req,
                                        peer_id_str: peer_id.clone(),
                                        message_id: Some(message_id),
                                        content: Some(content),
                                    });
                                    println!("[{}] [Stoa Network] Queued message for {peer_id} (connecting...)", chrono::Local::now().format("%H:%M:%S"));
                                }
                            }
                        }

                        Some(NetworkCommand::SendFile {
                            peer_id,
                            file_path,
                            sender_name,
                        }) => {
                            let tx = cmd_tx_for_loop.clone();
                            let path = std::path::PathBuf::from(file_path.clone());
                            // Determine chunk size based on connection type
                            let ct = conn_types.lock().await;
                            let chunk_size = if ct.get(&peer_id) == Some(&PeerConnectionType::Lan) {
                                file_transfer::LAN_CHUNK_SIZE
                            } else {
                                file_transfer::RELAY_CHUNK_SIZE
                            };
                            drop(ct);
                            // Spawn a task so hashing doesn't block the network event loop
                            tokio::spawn(async move {
                                println!("[{}] [Stoa File] Hashing file: {file_path} (chunk_size={}KB)", chrono::Local::now().format("%H:%M:%S"), chunk_size / 1024);
                                match file_transfer::prepare_file_off_thread(path.clone(), chunk_size).await {
                                    Ok((file_name, file_size, checksum, chunk_count)) => {
                                        let _ = tx.send(NetworkCommand::FilePrepared {
                                            peer_id,
                                            file_path,
                                            file_name,
                                            file_size,
                                            checksum,
                                            chunk_count,
                                            chunk_size: chunk_size as u32,
                                            sender_name,
                                        }).await;
                                    }
                                    Err(e) => {
                                        eprintln!("[{}] [Stoa File] File prep error: {e}", chrono::Local::now().format("%H:%M:%S"));
                                    }
                                }
                            });
                        }

                        Some(NetworkCommand::FilePrepared {
                            peer_id,
                            file_path,
                            file_name,
                            file_size,
                            checksum,
                            chunk_count,
                            chunk_size,
                            sender_name,
                        }) => {
                            let transfer_id = uuid::Uuid::new_v4().to_string();

                            println!(
                                "[Stoa File] Offering {} ({} bytes, {} chunks @ {}KB) to {}",
                                file_name, file_size, chunk_count, chunk_size / 1024, peer_id
                            );

                            let transfer = ActiveTransfer {
                                transfer_id: transfer_id.clone(),
                                peer_id: peer_id.clone(),
                                file_name: file_name.clone(),
                                file_size,
                                checksum: checksum.clone(),
                                chunk_count,
                                chunks_done: 0,
                                direction: TransferDirection::Upload,
                                status: TransferStatus::Offering,
                                file_path: std::path::PathBuf::from(file_path),
                                received_chunks_set: std::collections::HashSet::new(),
                                last_requested_chunk: None,
                                group_id: None,
                                chunk_size: chunk_size as usize,
                            };
                            active_transfers.insert(transfer_id.clone(), transfer);

                            let offer = StoaRequest::FileOffer {
                                transfer_id: transfer_id.clone(),
                                file_name: file_name.clone(),
                                file_size,
                                checksum,
                                chunk_count,
                                chunk_size,
                                sender_name,
                            };

                            if let Ok(target) = PeerId::from_str(&peer_id) {
                                if swarm.is_connected(&target) {
                                    let encrypted_offer = maybe_encrypt_request(&peer_id, offer);
                                    swarm.behaviour_mut().messaging.send_request(&target, encrypted_offer);
                                } else {
                                    handlers::dial_peer(&peers_clone, &contacts, &peer_id, &mut swarm).await;
                                    pending_messages.push(PendingMessage {
                                        peer_id: target,
                                        request: offer,
                                        peer_id_str: peer_id.clone(),
                                        message_id: None,
                                        content: None,
                                    });
                                }
                            }

                            // Emit transfer-started event
                            use serde::Serialize;
                            #[derive(Serialize, Clone)]
                            struct TransferEvent {
                                transfer_id: String,
                                peer_id: String,
                                file_name: String,
                                file_size: u64,
                                direction: String,
                                chunk_count: u32,
                            }
                            let _ = app_handle.emit("file-transfer-started", &TransferEvent {
                                transfer_id,
                                peer_id,
                                file_name,
                                file_size,
                                direction: "upload".into(),
                                chunk_count,
                            });
                        }

                        Some(NetworkCommand::PauseTransfer { transfer_id }) => {
                            if let Some(t) = active_transfers.get_mut(&transfer_id) {
                                t.status = TransferStatus::Paused;
                                println!("[{}] [Stoa File] Paused transfer {}", chrono::Local::now().format("%H:%M:%S"), transfer_id);
                            }
                        }

                        Some(NetworkCommand::ResumeTransfer { transfer_id }) => {
                            if let Some(transfer) = active_transfers.get_mut(&transfer_id) {
                                transfer.status = TransferStatus::Transferring;
                                println!("[{}] [Stoa File] Resumed transfer {}", chrono::Local::now().format("%H:%M:%S"), transfer_id);
                                let target = PeerId::from_str(&transfer.peer_id).unwrap();
                                // Find the first missing chunk index
                                let first_missing = (0..transfer.chunk_count)
                                    .find(|i| !transfer.received_chunks_set.contains(i))
                                    .unwrap_or(0);

                                // Restore the full pipeline window based on chunk size
                                let window_size = if transfer.chunk_size >= file_transfer::LAN_CHUNK_SIZE {
                                    file_transfer::LAN_WINDOW_SIZE
                                } else {
                                    file_transfer::RELAY_WINDOW_SIZE
                                };

                                // Request as many missing chunks as the window allows
                                let mut last_sent = first_missing;
                                let mut count = 0u32;
                                for i in first_missing..transfer.chunk_count {
                                    if count >= window_size { break; }
                                    if !transfer.received_chunks_set.contains(&i) {
                                        swarm.behaviour_mut().messaging.send_request(&target, StoaRequest::FetchChunk {
                                            transfer_id: transfer_id.clone(),
                                            chunk_index: i,
                                        });
                                        last_sent = i;
                                        count += 1;
                                    }
                                }
                                transfer.last_requested_chunk = Some(last_sent);
                            }
                        }

                        // ── Group Commands ──────────────────────────────────
                        Some(NetworkCommand::CreateGroup { name, member_ids }) => {
                            let group_id = uuid::Uuid::new_v4().to_string();
                            let mut all_members = vec![our_peer_id_str.clone()];
                            all_members.extend(member_ids.clone());

                            match groups::create_group(
                                &mut local_groups,
                                group_id.clone(),
                                name.clone(),
                                all_members.clone(),
                                our_peer_id_str.clone(),
                            ) {
                                Ok(group) => {
                                    println!("[{}] [Stoa Group] Created group '{}' ({})", chrono::Local::now().format("%H:%M:%S"), name, group_id);

                                    // Fan-out GroupInvite to all members
                                    for mid in &member_ids {
                                        if let Ok(target) = PeerId::from_str(mid) {
                                            let invite = StoaRequest::GroupInvite {
                                                group_id: group_id.clone(),
                                                group_name: name.clone(),
                                                members: all_members.clone(),
                                                admin: our_peer_id_str.clone(),
                                                inviter_name: our_name.clone(),
                                            };
                                            let encrypted_invite = maybe_encrypt_request(mid, invite.clone());
                                            if swarm.is_connected(&target) {
                                                swarm.behaviour_mut().messaging.send_request(&target, encrypted_invite);
                                            } else {
                                                println!("[{}] [Stoa Group] Member {mid} offline, queueing invite and dialing...", chrono::Local::now().format("%H:%M:%S"));
                                                handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                                pending_messages.push(PendingMessage {
                                                    peer_id: target,
                                                    request: invite,
                                                    peer_id_str: mid.clone(),
                                                    message_id: None,
                                                    content: None,
                                                });
                                            }
                                        }
                                    }

                                    // Notify frontend
                                    let _ = app_handle.emit("group-created", &serde_json::json!({
                                        "id": group_id,
                                        "name": name,
                                        "members": all_members,
                                        "admin": our_peer_id_str,
                                        "created_at": group.created_at,
                                    }));
                                }
                                Err(e) => eprintln!("[{}] [Stoa Group] Create failed: {e}", chrono::Local::now().format("%H:%M:%S")),
                            }
                        }

                        Some(NetworkCommand::SendGroupMessage {
                            group_id,
                            message_id,
                            content,
                            sender_name,
                        }) => {
                            let timestamp = chrono::Utc::now().timestamp();

                            // Persist our own message
                            let group_key = format!("group_{group_id}");
                            let msg = StoredMessage {
                                id: message_id.clone(),
                                sender_id: "me".into(),
                                content: content.clone(),
                                timestamp,
                                delivered: false,
                                file_info: None,
                            };
                            let _ = messages::save_message(&group_key, &msg);

                            // Fan-out to all members
                            if let Some(group) = local_groups.iter().find(|g| g.id == group_id) {
                                let members: Vec<String> = group.members.clone();
                                for mid in &members {
                                    if *mid == our_peer_id_str { continue; }
                                    if let Ok(target) = PeerId::from_str(mid) {
                                        let req = StoaRequest::GroupMessage {
                                            group_id: group_id.clone(),
                                            id: message_id.clone(),
                                            content: content.clone(),
                                            timestamp,
                                            sender_name: sender_name.clone(),
                                        };
                                        let encrypted_req = maybe_encrypt_request(mid, req.clone());
                                        if swarm.is_connected(&target) {
                                            swarm.behaviour_mut().messaging.send_request(&target, encrypted_req);
                                        } else {
                                            handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                            pending_messages.push(PendingMessage {
                                                peer_id: target,
                                                request: req,
                                                peer_id_str: mid.clone(),
                                                message_id: None,
                                                content: None,
                                            });
                                        }
                                    }
                                }
                            }
                        }

                        Some(NetworkCommand::SendGroupFile {
                            group_id,
                            file_path,
                            sender_name,
                        }) => {
                            // Use same pattern as DM files: connection-type-aware chunk size
                            // For groups, use the minimum (most conservative) chunk size among all members
                            // to ensure all members can receive. If any member is on relay, use relay.
                            let path = std::path::PathBuf::from(file_path.clone());
                            let group_chunk_size = if let Some(group) = local_groups.iter().find(|g| g.id == group_id) {
                                let ct = conn_types.lock().await;
                                let all_lan = group.members.iter()
                                    .filter(|m| **m != our_peer_id_str)
                                    .all(|m| ct.get(m) == Some(&PeerConnectionType::Lan));
                                drop(ct);
                                if all_lan { file_transfer::LAN_CHUNK_SIZE } else { file_transfer::RELAY_CHUNK_SIZE }
                            } else {
                                file_transfer::RELAY_CHUNK_SIZE
                            };
                            match file_transfer::prepare_file_off_thread(path, group_chunk_size).await {
                                Ok((file_name, file_size, checksum, chunk_count)) => {
                                    println!(
                                        "[Stoa Group] Offering {} ({} bytes, {} chunks @ {}KB) to group {}",
                                        file_name, file_size, chunk_count, group_chunk_size / 1024, group_id
                                    );

                                    // Emit once for the sender's UI
                                    let first_transfer_id = uuid::Uuid::new_v4().to_string();
                                    let _ = app_handle.emit(
                                        "group-file-transfer-started",
                                        &serde_json::json!({
                                            "group_id": group_id,
                                            "transfer_id": first_transfer_id,
                                            "peer_id": our_peer_id_str,
                                            "file_name": file_name,
                                            "file_size": file_size,
                                            "direction": "upload",
                                            "chunk_count": chunk_count,
                                            "sender_name": sender_name,
                                        }),
                                    );

                                    if let Some(group) = local_groups.iter().find(|g| g.id == group_id) {
                                        let members: Vec<String> = group.members.clone();
                                        for mid in &members {
                                            if *mid == our_peer_id_str { continue; }

                                            let transfer_id = uuid::Uuid::new_v4().to_string();
                                            let transfer = ActiveTransfer {
                                                transfer_id: transfer_id.clone(),
                                                peer_id: mid.clone(),
                                                file_name: file_name.clone(),
                                                file_size,
                                                checksum: checksum.clone(),
                                                chunk_count,
                                                chunks_done: 0,
                                                direction: TransferDirection::Upload,
                                                status: TransferStatus::Transferring,
                                                file_path: std::path::PathBuf::from(&file_path),
                                                received_chunks_set: std::collections::HashSet::new(),
                                                last_requested_chunk: None,
                                                group_id: Some(group_id.clone()),
                                                chunk_size: group_chunk_size,
                                            };
                                            active_transfers.insert(transfer_id.clone(), transfer);

                                            if let Ok(target) = PeerId::from_str(mid) {
                                                let offer = StoaRequest::GroupFileOffer {
                                                    group_id: group_id.clone(),
                                                    transfer_id: transfer_id.clone(),
                                                    file_name: file_name.clone(),
                                                    file_size,
                                                    checksum: checksum.clone(),
                                                    chunk_count,
                                                    chunk_size: group_chunk_size as u32,
                                                    sender_name: sender_name.clone(),
                                                };
                                                let offer_clone = offer.clone();
                                                let encrypted_offer = maybe_encrypt_request(mid, offer);
                                                if swarm.is_connected(&target) {
                                                    swarm.behaviour_mut().messaging.send_request(&target, encrypted_offer);
                                                } else {
                                                    handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                                    pending_messages.push(PendingMessage {
                                                        peer_id: target,
                                                        request: offer_clone,
                                                        peer_id_str: mid.clone(),
                                                        message_id: None,
                                                        content: None,
                                                    });
                                                }
                                            }
                                        }
                                    }
                                }
                                Err(e) => eprintln!("[{}] [Stoa Group] Failed to prepare file: {e}", chrono::Local::now().format("%H:%M:%S")),
                            }
                        }

                        Some(NetworkCommand::LeaveGroup { group_id }) => {
                            println!("[{}] [Stoa Group] Leaving group {group_id}", chrono::Local::now().format("%H:%M:%S"));
                            if let Some(group) = local_groups.iter().find(|g| g.id == group_id).cloned() {
                                for mid in &group.members {
                                    if *mid == our_peer_id_str { continue; }
                                    if let Ok(target) = PeerId::from_str(mid) {
                                        let req = StoaRequest::MemberLeft {
                                            group_id: group_id.clone(),
                                            peer_id: our_peer_id_str.clone(),
                                        };
                                        let encrypted_req = maybe_encrypt_request(mid, req.clone());
                                        if swarm.is_connected(&target) {
                                            swarm.behaviour_mut().messaging.send_request(&target, encrypted_req);
                                        } else {
                                            handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                            pending_messages.push(PendingMessage {
                                                peer_id: target,
                                                request: req,
                                                peer_id_str: mid.clone(),
                                                message_id: None,
                                                content: None,
                                            });
                                        }
                                    }
                                }
                                let _ = groups::remove_group(&mut local_groups, &group_id);
                            }
                        }

                        Some(NetworkCommand::RemoveGroupMember { group_id, peer_id: remove_pid }) => {
                            println!("[{}] [Stoa Group] Admin removing {remove_pid} from {group_id}", chrono::Local::now().format("%H:%M:%S"));
                            if let Some(group) = local_groups.iter().find(|g| g.id == group_id).cloned() {
                                if group.admin != our_peer_id_str {
                                    eprintln!("[{}] [Stoa Group] Not admin, cannot remove member", chrono::Local::now().format("%H:%M:%S"));
                                    continue;
                                }
                                for mid in &group.members {
                                    if *mid == our_peer_id_str { continue; }
                                    if let Ok(target) = PeerId::from_str(mid) {
                                        let req = StoaRequest::MemberRemoved {
                                            group_id: group_id.clone(),
                                            removed_peer_id: remove_pid.clone(),
                                        };
                                        let encrypted_req = maybe_encrypt_request(mid, req.clone());
                                        if swarm.is_connected(&target) {
                                            swarm.behaviour_mut().messaging.send_request(&target, encrypted_req);
                                        } else {
                                            handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                            pending_messages.push(PendingMessage {
                                                peer_id: target,
                                                request: req,
                                                peer_id_str: mid.clone(),
                                                message_id: None,
                                                content: None,
                                            });
                                        }
                                    }
                                }
                                let _ = groups::remove_member(&mut local_groups, &group_id, &remove_pid);
                            }
                        }

                        Some(NetworkCommand::DisbandGroup { group_id }) => {
                            println!("[{}] [Stoa Group] Admin disbanding group {group_id}", chrono::Local::now().format("%H:%M:%S"));
                            if let Some(group) = local_groups.iter().find(|g| g.id == group_id).cloned() {
                                if group.admin != our_peer_id_str {
                                    eprintln!("[{}] [Stoa Group] Not admin, cannot disband", chrono::Local::now().format("%H:%M:%S"));
                                    continue;
                                }
                                for mid in &group.members {
                                    if *mid == our_peer_id_str { continue; }
                                    if let Ok(target) = PeerId::from_str(mid) {
                                        let req = StoaRequest::GroupDisbanded {
                                            group_id: group_id.clone(),
                                        };
                                        let encrypted_req = maybe_encrypt_request(mid, req.clone());
                                        if swarm.is_connected(&target) {
                                            swarm.behaviour_mut().messaging.send_request(&target, encrypted_req);
                                        } else {
                                            handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                            pending_messages.push(PendingMessage {
                                                peer_id: target,
                                                request: req,
                                                peer_id_str: mid.clone(),
                                                message_id: None,
                                                content: None,
                                            });
                                        }
                                    }
                                }
                                let _ = groups::remove_group(&mut local_groups, &group_id);
                            }
                        }

                        Some(NetworkCommand::OpenGroupSpace { group_id }) => {
                            println!("[{}] [Stoa Space] Opening space for group {}", chrono::Local::now().format("%H:%M:%S"), group_id);
                            if let Some(group) = local_groups.iter().find(|g| g.id == group_id).cloned() {
                                if let Ok(sv_bytes) = crate::crdt::encode_state_vector(&group_id).await {
                                    let sv_b64 = base64::encode(&sv_bytes);
                                    for mid in &group.members {
                                        if *mid == our_peer_id_str { continue; }
                                        if let Ok(target) = PeerId::from_str(mid) {
                                            let req = StoaRequest::GroupSpaceSync {
                                                group_id: group_id.clone(),
                                                state_vector_b64: sv_b64.clone(),
                                            };
                                            let encrypted_req = maybe_encrypt_request(mid, req.clone());
                                            if swarm.is_connected(&target) {
                                                swarm.behaviour_mut().messaging.send_request(&target, encrypted_req);
                                            } else {
                                                handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                                pending_messages.push(PendingMessage {
                                                    peer_id: target,
                                                    request: req,
                                                    peer_id_str: mid.clone(),
                                                    message_id: None,
                                                    content: None,
                                                });
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Some(NetworkCommand::EditGroupSpace { group_id, file_id, index, delete_count, insert_text }) => {
                            if let Ok(update_bytes) = crate::crdt::apply_file_edit(&group_id, &file_id, index, delete_count, &insert_text).await {
                                let update_b64 = base64::encode(&update_bytes);
                                if let Some(group) = local_groups.iter().find(|g| g.id == group_id).cloned() {
                                    for mid in &group.members {
                                        if *mid == our_peer_id_str { continue; }
                                        if let Ok(target) = PeerId::from_str(mid) {
                                            let req = StoaRequest::GroupSpaceUpdate {
                                                group_id: group_id.clone(),
                                                update_b64: update_b64.clone(),
                                            };
                                            let encrypted_req = maybe_encrypt_request(mid, req.clone());
                                            if swarm.is_connected(&target) {
                                                swarm.behaviour_mut().messaging.send_request(&target, encrypted_req);
                                            } else {
                                                handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                                pending_messages.push(PendingMessage {
                                                    peer_id: target,
                                                    request: req,
                                                    peer_id_str: mid.clone(),
                                                    message_id: None,
                                                    content: None,
                                                });
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Some(NetworkCommand::CreateSpaceFile { group_id, file_name, content }) => {
                            println!("[{}] [Stoa Space] Creating file '{}' in group {}", chrono::Local::now().format("%H:%M:%S"), file_name, group_id);
                            let result = if let Some(text) = content {
                                crate::crdt::create_file_with_content(&group_id, &file_name, &text, &our_peer_id_str).await
                            } else {
                                crate::crdt::create_file(&group_id, &file_name, &our_peer_id_str).await
                            };
                            if let Ok((_file_id, update_bytes)) = result {
                                let update_b64 = base64::encode(&update_bytes);
                                if let Some(group) = local_groups.iter().find(|g| g.id == group_id).cloned() {
                                    for mid in &group.members {
                                        if *mid == our_peer_id_str { continue; }
                                        if let Ok(target) = PeerId::from_str(mid) {
                                            let req = StoaRequest::GroupSpaceUpdate {
                                                group_id: group_id.clone(),
                                                update_b64: update_b64.clone(),
                                            };
                                            let encrypted_req = maybe_encrypt_request(mid, req.clone());
                                            if swarm.is_connected(&target) {
                                                swarm.behaviour_mut().messaging.send_request(&target, encrypted_req);
                                            } else {
                                                handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                                pending_messages.push(PendingMessage {
                                                    peer_id: target,
                                                    request: req,
                                                    peer_id_str: mid.clone(),
                                                    message_id: None,
                                                    content: None,
                                                });
                                            }
                                        }
                                    }
                                }
                                // Notify our own frontend
                                let _ = app_handle.emit("space-remote-update", &serde_json::json!({
                                    "group_id": group_id,
                                }));
                            }
                        }

                        Some(NetworkCommand::DeleteSpaceFile { group_id, file_id }) => {
                            println!("[{}] [Stoa Space] Deleting file {} in group {}", chrono::Local::now().format("%H:%M:%S"), file_id, group_id);
                            if let Ok(update_bytes) = crate::crdt::delete_file(&group_id, &file_id).await {
                                let update_b64 = base64::encode(&update_bytes);
                                if let Some(group) = local_groups.iter().find(|g| g.id == group_id).cloned() {
                                    for mid in &group.members {
                                        if *mid == our_peer_id_str { continue; }
                                        if let Ok(target) = PeerId::from_str(mid) {
                                            let req = StoaRequest::GroupSpaceUpdate {
                                                group_id: group_id.clone(),
                                                update_b64: update_b64.clone(),
                                            };
                                            let encrypted_req = maybe_encrypt_request(mid, req.clone());
                                            if swarm.is_connected(&target) {
                                                swarm.behaviour_mut().messaging.send_request(&target, encrypted_req);
                                            } else {
                                                handlers::dial_peer(&peers_clone, &contacts, mid, &mut swarm).await;
                                                pending_messages.push(PendingMessage {
                                                    peer_id: target,
                                                    request: req,
                                                    peer_id_str: mid.clone(),
                                                    message_id: None,
                                                    content: None,
                                                });
                                            }
                                        }
                                    }
                                }
                                // Notify our own frontend
                                let _ = app_handle.emit("space-remote-update", &serde_json::json!({
                                    "group_id": group_id,
                                }));
                            }
                        }

                        Some(NetworkCommand::Shutdown) | None => {
                            println!("[{}] [Stoa Network] Shutting down network task.", chrono::Local::now().format("%H:%M:%S"));
                            break;
                        }
                    }
                }

                // ── Reconnection Sweep ──────────────────────────────────
                _ = reconnect_interval.tick() => {
                    let cts = contacts.lock().await;
                    let contact_ids: Vec<String> = cts.iter().map(|c| c.peer_id.clone()).collect();
                    drop(cts);

                    for pid in contact_ids {
                        if let Ok(target) = PeerId::from_str(&pid) {
                            if !swarm.is_connected(&target) {
                                // Peer is offline — try both LAN and relay
                                handlers::dial_peer(&peers_clone, &contacts, &pid, &mut swarm).await;
                            }
                        }
                    }
                }
            }
        }
    });

    Ok((cmd_tx, nearby_peers, handle))
}

/// Encrypt a request for a peer if a session exists, otherwise return it as-is.
/// This is the single point where outgoing messages get encrypted.
pub fn maybe_encrypt_request(peer_id: &str, req: StoaRequest) -> StoaRequest {
    if !crypto::has_session(peer_id) {
        return req;
    }

    let plaintext = match serde_json::to_vec(&req) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("[{}] [Stoa Crypto] Failed to serialize for encryption: {e}", chrono::Local::now().format("%H:%M:%S"));
            return req;
        }
    };

    match crypto::encrypt_for_peer(peer_id, &plaintext) {
        Ok(Some((ciphertext_b64, nonce_b64))) => {
            println!("[{}] [Stoa Crypto] Encrypting message for {peer_id}", chrono::Local::now().format("%H:%M:%S"));
            StoaRequest::EncryptedEnvelope {
                id: uuid::Uuid::new_v4().to_string(),
                ciphertext_b64,
                nonce_b64,
            }
        }
        Ok(None) => req,
        Err(e) => {
            eprintln!("[{}] [Stoa Crypto] Encryption failed, sending plaintext: {e}", chrono::Local::now().format("%H:%M:%S"));
            req
        }
    }
}
