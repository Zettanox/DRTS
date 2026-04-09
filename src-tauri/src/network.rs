use futures::StreamExt;
use libp2p::identity::Keypair;
use libp2p::swarm::SwarmEvent;
use libp2p::{mdns, PeerId, Swarm, Transport};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tokio::sync::{mpsc, Mutex};

/// Info about a discovered LAN peer. Sent to the frontend.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NearbyPeer {
    pub peer_id: String,
    pub addresses: Vec<String>,
}

/// Commands the frontend can send to the network task.
#[derive(Debug)]
pub enum NetworkCommand {
    /// Toggle mDNS visibility (true = discoverable, false = hidden)
    SetVisibility(bool),
    /// Shut down the network task
    Shutdown,
}

/// Shared state tracking discovered peers.
pub type NearbyPeersMap = Arc<Mutex<HashMap<String, NearbyPeer>>>;

/// The mDNS network behaviour — kept minimal for Phase 1.
#[derive(libp2p::swarm::NetworkBehaviour)]
struct StoapBehaviour {
    mdns: mdns::tokio::Behaviour,
}

/// Spawn the libp2p swarm on a background Tokio task.
/// Returns a command sender and the shared nearby-peers map.
pub fn spawn_network(
    keypair: Keypair,
    app_handle: AppHandle,
) -> Result<(mpsc::Sender<NetworkCommand>, NearbyPeersMap), String> {
    let peer_id = PeerId::from(keypair.public());

    let mdns_config = mdns::Config {
        // Query every 3 seconds for fast discovery
        query_interval: std::time::Duration::from_secs(3),
        // Peers expire quickly when they stop responding
        ttl: std::time::Duration::from_secs(8),
        ..Default::default()
    };

    let mdns_behaviour = mdns::tokio::Behaviour::new(mdns_config, peer_id)
        .map_err(|e| format!("Failed to create mDNS behaviour: {e}"))?;

    let behaviour = StoapBehaviour {
        mdns: mdns_behaviour,
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
        libp2p::swarm::Config::with_tokio_executor(),
    );

    // Listen on all interfaces, OS-assigned port
    swarm
        .listen_on("/ip4/0.0.0.0/tcp/0".parse().unwrap())
        .map_err(|e| format!("Failed to listen: {e}"))?;

    let (cmd_tx, mut cmd_rx) = mpsc::channel::<NetworkCommand>(32);
    let nearby_peers: NearbyPeersMap = Arc::new(Mutex::new(HashMap::new()));
    let peers_clone = nearby_peers.clone();

    tokio::spawn(async move {
        let mut frontend_visible = true;

        loop {
            tokio::select! {
                // Process swarm events — ALWAYS, regardless of visibility flag
                event = swarm.select_next_some() => {
                    match event {
                        SwarmEvent::Behaviour(StoapBehaviourEvent::Mdns(
                            mdns::Event::Discovered(list),
                        )) => {
                            for (peer_id, addr) in list {
                                let pid = peer_id.to_string();
                                let addr_str = addr.to_string();

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

                                // Only notify frontend if visible
                                if frontend_visible {
                                    let _ = app_handle.emit("peer-discovered", &peer_info);
                                }
                            }
                        }
                        SwarmEvent::Behaviour(StoapBehaviourEvent::Mdns(
                            mdns::Event::Expired(list),
                        )) => {
                            for (peer_id, _addr) in list {
                                let pid = peer_id.to_string();
                                let mut peers = peers_clone.lock().await;
                                peers.remove(&pid);
                                drop(peers);

                                // Only notify frontend if visible
                                if frontend_visible {
                                    let _ = app_handle.emit("peer-expired", &pid);
                                }
                            }
                        }
                        SwarmEvent::NewListenAddr { address, .. } => {
                            println!("[Stoa Network] Listening on {address}");
                        }
                        _ => {}
                    }
                }

                // Process commands from frontend
                cmd = cmd_rx.recv() => {
                    match cmd {
                        Some(NetworkCommand::SetVisibility(visible)) => {
                            frontend_visible = visible;
                            if visible {
                                // Re-emit all currently known peers to the frontend
                                let peers = peers_clone.lock().await;
                                for peer_info in peers.values() {
                                    let _ = app_handle.emit("peer-discovered", peer_info);
                                }
                                drop(peers);
                            } else {
                                // Tell frontend to clear all peers
                                let peers = peers_clone.lock().await;
                                let peer_ids: Vec<String> = peers.keys().cloned().collect();
                                drop(peers);
                                for pid in peer_ids {
                                    let _ = app_handle.emit("peer-expired", &pid);
                                }
                            }
                            println!("[Stoa Network] Visibility set to: {visible}");
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

    Ok((cmd_tx, nearby_peers))
}
