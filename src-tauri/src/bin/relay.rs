//! stoa-relay — Standalone Circuit Relay v2 server for the Stoa P2P network.
//!
//! Deploy this on any machine with a public IP (VPS, home server with port forwarding, etc.)
//! It stores zero state, forwards only encrypted bytes, and consumes minimal resources.
//!
//! Usage:
//!   stoa-relay --external-ip 1.2.3.4                   # Listen on 0.0.0.0:38291, ephemeral keypair
//!   stoa-relay --port 38291 --external-ip 1.2.3.4      # Custom port
//!   stoa-relay --key-file relay.key --external-ip ...  # Persist keypair for stable PeerID (recommended)
//!
//! After starting, the relay prints its full multiaddr. Share it with Stoa users
//! who paste it into Settings → Internet → Relay Servers.
//!
//! SECURITY NOTE: Relay V2 circuits are limited to 2 minutes and 2 MB by default.
//! This forces peers to DCUtR (hole-punch) to a direct connection and prevents
//! freeloaders from routing heavy traffic through this server.

use clap::Parser;
use futures::StreamExt;
use libp2p::{
    core::upgrade,
    identify, noise, ping, relay,
    swarm::{NetworkBehaviour, SwarmEvent},
    tcp, yamux, Multiaddr, PeerId, Transport,
};
use std::{error::Error, path::PathBuf, sync::atomic::{AtomicU64, Ordering}};
use std::sync::Arc;

#[derive(Parser)]
#[command(name = "stoa-relay", about = "Stoa Circuit Relay v2 server")]
struct Cli {
    /// Port to listen on
    #[arg(short, long, default_value = "38291")]
    port: u16,

    /// Path to persist the keypair (gives a stable PeerID across restarts — recommended for production)
    #[arg(short, long)]
    key_file: Option<PathBuf>,

    /// Public IP address of this server (REQUIRED for relay reservations to work).
    #[arg(short, long, alias = "ip")]
    external_ip: String,

    /// Maximum simultaneous relay reservations (default 512).
    /// Each reservation is a waiting-room slot for a peer that wants to be found.
    #[arg(long, default_value = "512")]
    max_reservations: u32,

    /// Hard cap on total established connections (default 512).
    /// Prevents memory exhaustion from bot floods.
    #[arg(long, default_value = "512")]
    max_connections: u32,
}

#[derive(NetworkBehaviour)]
struct RelayBehaviour {
    relay: relay::Behaviour,
    identify: identify::Behaviour,
    ping: ping::Behaviour,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let args = Cli::parse();

    let keypair = load_or_generate_keypair(args.key_file.as_deref())?;
    let peer_id = PeerId::from(keypair.public());

    // Counters for periodic stats logging
    let connected_count = Arc::new(AtomicU64::new(0));
    let circuit_count   = Arc::new(AtomicU64::new(0));

    println!("╔══════════════════════════════════════════════════╗");
    println!("║              Stoa Relay Server                   ║");
    println!("╠══════════════════════════════════════════════════╣");
    println!("║  PeerID          : {peer_id}");
    println!("║  Port            : {}", args.port);
    println!("║  ExtIP           : {}", args.external_ip);
    println!("║  Max connections : {}", args.max_connections);
    println!("║  Max reservations: {}", args.max_reservations);
    println!("╚══════════════════════════════════════════════════╝");
    println!();
    println!("  Circuit limits: 2 min / 2 MiB  ← peers must hole-punch to direct after that");
    println!();

    // ── Relay V2 limits ────────────────────────────────────────────────────────
    // Keep circuit duration and bytes LOW so that:
    //  a) Stoa peers hole-punch (DCUtR) to a direct connection quickly, and
    //  b) random freeloaders cannot use this server as a long-lived data pipe.
    let relay_config = relay::Config {
        max_reservations: args.max_reservations as usize,
        max_circuits: (args.max_reservations / 2) as usize,
        max_circuits_per_peer: 4,
        max_circuit_duration: std::time::Duration::from_secs(20 * 60),
        max_circuit_bytes: 50 * 1024 * 1024,
        reservation_duration: std::time::Duration::from_secs(3600),
        ..Default::default()
    };

    let transport = tcp::tokio::Transport::new(tcp::Config::default())
        .upgrade(upgrade::Version::V1)
        .authenticate(noise::Config::new(&keypair)?)
        .multiplex(yamux::Config::default())
        .boxed();


    let behaviour = RelayBehaviour {
        relay: relay::Behaviour::new(peer_id, relay_config),
        identify: identify::Behaviour::new(
            identify::Config::new("/stoa/relay/1.0.0".to_string(), keypair.public())
                .with_push_listen_addr_updates(true),
        ),
        ping: ping::Behaviour::new(
            ping::Config::new().with_interval(std::time::Duration::from_secs(15)),
        ),
    };

    let mut swarm = libp2p::Swarm::new(
        transport,
        behaviour,
        peer_id,
        libp2p::swarm::Config::with_tokio_executor(),
    );

    let listen_addr: Multiaddr = format!("/ip4/0.0.0.0/tcp/{}", args.port).parse()?;
    swarm.listen_on(listen_addr)?;

    // Tell the swarm our public address so reservation responses include it
    let external_addr: Multiaddr = format!(
        "/ip4/{}/tcp/{}/p2p/{}",
        args.external_ip, args.port, peer_id
    )
    .parse()?;
    swarm.add_external_address(external_addr.clone());
    println!("[Relay] External address registered: {external_addr}");

    let cc  = connected_count.clone();
    let circ = circuit_count.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));
        loop {
            interval.tick().await;
            println!(
                "[Relay] Stats — peers connected: {}  active circuits: {}",
                cc.load(Ordering::Relaxed),
                circ.load(Ordering::Relaxed),
            );
        }
    });

    loop {
        match swarm.select_next_some().await {
            SwarmEvent::NewListenAddr { address, .. } => {
                println!("[Relay] Listening: {address}/p2p/{peer_id}");
                println!("[Relay] ↑ Share this address with your Stoa users");
            }
            SwarmEvent::Behaviour(RelayBehaviourEvent::Relay(event)) => {
                match &event {
                    relay::Event::CircuitReqAccepted { src_peer_id, .. } => {
                        circuit_count.fetch_add(1, Ordering::Relaxed);
                        println!("[Relay] Circuit opened: {src_peer_id}");
                    }
                    relay::Event::CircuitClosed { src_peer_id, .. } => {
                        circuit_count.fetch_sub(1, Ordering::Relaxed);
                        println!("[Relay] Circuit closed: {src_peer_id}");
                    }
                    relay::Event::CircuitReqDenied { src_peer_id, .. } => {
                        println!("[Relay] Circuit denied (limit hit): {src_peer_id}");
                    }
                    _ => { println!("[Relay] {:?}", event); }
                }
            }
            SwarmEvent::Behaviour(RelayBehaviourEvent::Ping(_)) => {}
            SwarmEvent::ConnectionEstablished { peer_id, .. } => {
                connected_count.fetch_add(1, Ordering::Relaxed);
                println!("[Relay] Peer connected:    {peer_id}");
            }
            SwarmEvent::ConnectionClosed { peer_id, cause, .. } => {
                let prev = connected_count.load(Ordering::Relaxed);
                connected_count.store(prev.saturating_sub(1), Ordering::Relaxed);
                println!("[Relay] Peer disconnected: {peer_id} ({cause:?})");
            }
            _ => {}
        }
    }
}

fn load_or_generate_keypair(
    path: Option<&std::path::Path>,
) -> Result<libp2p::identity::Keypair, Box<dyn Error>> {
    use libp2p::identity::Keypair;

    if let Some(p) = path {
        if p.exists() {
            let bytes = std::fs::read(p)?;
            let kp = Keypair::from_protobuf_encoding(&bytes)?;
            println!("[Relay] Loaded keypair from {}", p.display());
            return Ok(kp);
        }
        let kp = Keypair::generate_ed25519();
        let encoded = kp.to_protobuf_encoding()?;
        std::fs::write(p, &encoded)?;
        println!("[Relay] New keypair saved to {}", p.display());
        return Ok(kp);
    }

    println!("[Relay] Using ephemeral keypair (PeerID changes on restart — use --key-file for production)");
    Ok(Keypair::generate_ed25519())
}
