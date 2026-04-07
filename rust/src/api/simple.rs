use std::sync::Arc;
use tokio::sync::mpsc;
use flutter_rust_bridge::frb;

#[frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[frb(opaque)]
pub struct StoaCoreNode {
    inner: Arc<stoa_node::StoaNode>,
}

impl StoaCoreNode {
    /// Create a new node with persistent identity.
    /// `data_dir` is the app's document directory.
    pub async fn create(data_dir: String) -> anyhow::Result<StoaCoreNode> {
        let path = std::path::PathBuf::from(&data_dir);
        let node = stoa_node::StoaNode::new(&path).await?;
        Ok(Self { inner: Arc::new(node) })
    }

    #[frb(sync)]
    pub fn node_id(&self) -> String {
        self.inner.node_id()
    }

    #[frb(sync)]
    pub fn display_name(&self) -> String {
        self.inner.display_name()
    }

    pub fn set_display_name(&self, name: String) -> anyhow::Result<()> {
        self.inner.set_display_name(name)
    }

    /// Join a gossip topic. Returns a TopicHandle for send/receive.
    pub async fn join_topic(&self, topic_hex: String) -> anyhow::Result<TopicHandle> {
        let topic_bytes = hex_to_bytes32(&topic_hex)?;
        let topic_id = stoa_node::TopicId::from_bytes(topic_bytes);
        let (out_tx, in_rx) = self.inner.join_topic(topic_id, vec![]).await?;
        Ok(TopicHandle {
            out_tx,
            in_rx: std::sync::Mutex::new(in_rx),
        })
    }

    /// Start listening for LAN peers via mDNS. Returns a handle to poll for discoveries.
    pub async fn subscribe_lan(&self) -> LanPeerHandle {
        let rx = self.inner.subscribe_lan_peers().await;
        LanPeerHandle {
            rx: std::sync::Mutex::new(rx),
        }
    }
}

/// Handle for polling LAN peer discoveries from Flutter.
#[frb(opaque)]
pub struct LanPeerHandle {
    rx: std::sync::Mutex<mpsc::Receiver<stoa_node::DiscoveredPeer>>,
}

impl LanPeerHandle {
    /// Poll for a newly discovered LAN peer. Returns None if no new peer yet.
    pub async fn poll_peer(&self) -> anyhow::Result<Option<LanPeer>> {
        let mut rx = self.rx.lock()
            .map_err(|e| anyhow::anyhow!("Lock poisoned: {e}"))?;
        match rx.try_recv() {
            Ok(peer) => Ok(Some(LanPeer { peer_id: peer.peer_id })),
            Err(mpsc::error::TryRecvError::Empty) => Ok(None),
            Err(mpsc::error::TryRecvError::Disconnected) => {
                Err(anyhow::anyhow!("LAN discovery channel closed"))
            }
        }
    }
}

/// A peer discovered on the local network.
pub struct LanPeer {
    pub peer_id: String,
}

#[frb(opaque)]
pub struct TopicHandle {
    out_tx: mpsc::Sender<Vec<u8>>,
    in_rx: std::sync::Mutex<mpsc::Receiver<stoa_node::GossipMessage>>,
}

impl TopicHandle {
    pub async fn send_message(&self, content: String) -> anyhow::Result<()> {
        let bytes: Vec<u8> = content.into_bytes();
        self.out_tx
            .send(bytes)
            .await
            .map_err(|_| anyhow::anyhow!("Send channel closed"))?;
        Ok(())
    }

    pub async fn recv_message(&self) -> anyhow::Result<Option<GossipMsg>> {
        let mut rx = self.in_rx.lock()
            .map_err(|e| anyhow::anyhow!("Lock poisoned: {e}"))?;
        match rx.try_recv() {
            Ok(msg) => Ok(Some(GossipMsg {
                content: String::from_utf8_lossy(&msg.content).to_string(),
                sender: msg.delivered_from,
            })),
            Err(mpsc::error::TryRecvError::Empty) => Ok(None),
            Err(mpsc::error::TryRecvError::Disconnected) => {
                Err(anyhow::anyhow!("Topic channel closed"))
            }
        }
    }
}

/// A gossip message received from a peer.
pub struct GossipMsg {
    pub content: String,
    pub sender: String,
}

fn hex_to_bytes32(hex: &str) -> anyhow::Result<[u8; 32]> {
    let hex = hex.trim();
    if hex.len() != 64 {
        anyhow::bail!("Topic hex must be 64 chars (32 bytes), got {}", hex.len());
    }
    let mut bytes = [0u8; 32];
    for i in 0..32 {
        bytes[i] = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16)
            .map_err(|e| anyhow::anyhow!("Invalid hex at position {}: {e}", i * 2))?;
    }
    Ok(bytes)
}
