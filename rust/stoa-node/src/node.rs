use anyhow::Result;
use bytes::Bytes;
use iroh::address_lookup::{DiscoveryEvent, MdnsAddressLookup};
use iroh::protocol::Router;
use iroh::{Endpoint, Watcher};
use iroh_gossip::net::Gossip;
use iroh_gossip::ALPN;
use n0_future::StreamExt;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::info;

use crate::identity::StoaIdentity;

pub use iroh_gossip::proto::TopicId;

/// A message received from the gossip network.
#[derive(Debug, Clone)]
pub struct GossipMessage {
    pub content: Vec<u8>,
    pub delivered_from: String,
}

/// Information about a discovered peer on the LAN.
#[derive(Debug, Clone)]
pub struct DiscoveredPeer {
    pub peer_id: String,
}

/// The core Stoa networking node.
/// Manages the iroh Endpoint, Router, Gossip actor, mDNS discovery, and persistent identity.
pub struct StoaNode {
    endpoint: Endpoint,
    gossip: Gossip,
    identity: StoaIdentity,
    mdns: MdnsAddressLookup,
    _router: Router,
}

impl StoaNode {
    /// Create a new Stoa node with persistent identity, gossip, and LAN discovery.
    pub async fn new(data_dir: &Path) -> Result<Self> {
        // Load or create persistent identity
        let identity = StoaIdentity::load_or_create(data_dir)?;

        info!("Initializing Stoa Iroh Endpoint with N0 preset + mDNS...");
        // N0 preset enables Relay mode and DNS lookup/publishing.
        // We bind to a fixed port (54321) to make it easier to open in firewalls.
        let endpoint = Endpoint::builder(iroh::endpoint::presets::N0)
            .secret_key(identity.secret_key().clone())
            .bind_addr(SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 54321))?
            .bind()
            .await?;

        // Watch for address changes and log them.
        // This helps verify that the node has detected its local/public IPs.
        let lp_endpoint = endpoint.clone();
        tokio::spawn(async move {
            let mut watcher = lp_endpoint.watch_addr();
            info!("Local Node ID: {}", lp_endpoint.id());
            
            loop {
                let addr = watcher.get();
                info!("Local Addresses: {:?}", addr);
                // In n0_watcher 0.6, the method is called .updated()
                if watcher.updated().await.is_err() {
                    break;
                }
            }
        });

        // Set up mDNS for LAN peer discovery
        let mdns = MdnsAddressLookup::builder()
            .build(endpoint.id())
            .map_err(|e| anyhow::anyhow!("Failed to create mDNS: {e}"))?;

        // Register mDNS with the endpoint's address lookup system
        endpoint
            .address_lookup()
            .map_err(|e| anyhow::anyhow!("Endpoint closed: {e}"))?
            .add(mdns.clone());

        // Spawn the gossip actor
        let gossip = Gossip::builder().spawn(endpoint.clone());

        // Register gossip on the router
        let router = Router::builder(endpoint.clone())
            .accept(ALPN, gossip.clone())
            .spawn();

        info!("Stoa Node started! Node ID: {} (mDNS active)", endpoint.id());

        Ok(Self {
            endpoint,
            gossip,
            identity,
            mdns,
            _router: router,
        })
    }

    pub fn node_id(&self) -> String {
        self.endpoint.id().to_string()
    }

    pub fn display_name(&self) -> String {
        self.identity.display_name()
    }

    pub fn set_display_name(&self, name: String) -> Result<()> {
        self.identity.set_display_name(name)
    }

    pub fn endpoint(&self) -> &Endpoint {
        &self.endpoint
    }

    pub fn gossip(&self) -> &Gossip {
        &self.gossip
    }

    /// Subscribe to LAN peer discovery events.
    /// Returns a receiver channel that emits DiscoveredPeer when new peers appear on the LAN.
    pub async fn subscribe_lan_peers(&self) -> mpsc::Receiver<DiscoveredPeer> {
        let (tx, rx) = mpsc::channel::<DiscoveredPeer>(64);
        let mut events = self.mdns.subscribe().await;

        tokio::spawn(async move {
            while let Some(event) = events.next().await {
                match event {
                    DiscoveryEvent::Discovered { endpoint_info, .. } => {
                        let peer = DiscoveredPeer {
                            peer_id: endpoint_info.endpoint_id.to_string(),
                        };
                        info!("LAN peer discovered: {}", peer.peer_id);
                        if tx.send(peer).await.is_err() {
                            break;
                        }
                    }
                    DiscoveryEvent::Expired { endpoint_id } => {
                        info!("LAN peer expired: {}", endpoint_id);
                        // Could add an ExpiredPeer event in the future
                    }
                }
            }
        });

        rx
    }

    /// Subscribe to a gossip topic.
    /// Returns a sender channel for broadcasting and a receiver channel for incoming messages.
    pub async fn join_topic(
        self: &Arc<Self>,
        topic: TopicId,
        bootstrap: Vec<iroh::EndpointId>,
    ) -> Result<(
        mpsc::Sender<Vec<u8>>,
        mpsc::Receiver<GossipMessage>,
    )> {
        let gossip_topic = self.gossip.subscribe(topic, bootstrap).await
            .map_err(|e| anyhow::anyhow!("Failed to subscribe to topic: {e}"))?;

        let (sender, receiver) = gossip_topic.split();

        // Channel for Flutter → gossip
        let (out_tx, mut out_rx) = mpsc::channel::<Vec<u8>>(128);
        // Channel for gossip → Flutter
        let (in_tx, in_rx) = mpsc::channel::<GossipMessage>(256);

        // Spawn: outgoing messages → gossip broadcast
        let sender_clone = sender.clone();
        tokio::spawn(async move {
            while let Some(msg) = out_rx.recv().await {
                if let Err(e) = sender_clone.broadcast(Bytes::from(msg)).await {
                    tracing::warn!("Failed to broadcast message: {e}");
                    break;
                }
            }
        });

        // Spawn: incoming gossip events → Flutter
        tokio::spawn(async move {
            let mut receiver = receiver;
            while let Some(Ok(event)) = receiver.next().await {
                match event {
                    iroh_gossip::api::Event::Received(msg) => {
                        let gossip_msg = GossipMessage {
                            content: msg.content.to_vec(),
                            delivered_from: msg.delivered_from.to_string(),
                        };
                        if in_tx.send(gossip_msg).await.is_err() {
                            break;
                        }
                    }
                    iroh_gossip::api::Event::NeighborUp(peer) => {
                        info!("Gossip neighbor joined: {}", peer.fmt_short());
                    }
                    iroh_gossip::api::Event::NeighborDown(peer) => {
                        info!("Gossip neighbor left: {}", peer.fmt_short());
                    }
                    iroh_gossip::api::Event::Lagged => {
                        tracing::warn!("Gossip subscriber lagged");
                    }
                }
            }
        });

        Ok((out_tx, in_rx))
    }
}
