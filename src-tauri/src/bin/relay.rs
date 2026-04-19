//! stoa-relay — Standalone Circuit Relay v2 server for the Stoa P2P network.
//!
//! Deploy this on any machine with a public IP (VPS, home server with port forwarding, etc.)
//! It stores zero state, forwards only encrypted bytes, and consumes minimal resources.
//!
//! Usage:
//!   stoa-relay                          # Listen on 0.0.0.0:4001, ephemeral keypair
//!   stoa-relay --port 4001              # Custom port
//!   stoa-relay --key-file relay.key     # Persist keypair for stable PeerID (recommended)
//!
//! After starting, the relay prints its full multiaddr. Share it with Stoa users
//! who paste it into Settings → Internet → Relay Servers.

use clap::Parser;
use futures::StreamExt;
use libp2p::{
    core::upgrade,
    identify, noise,
    relay,
    swarm::{NetworkBehaviour, SwarmEvent},
    tcp, yamux, Multiaddr, PeerId, Transport,
};
use std::{error::Error, path::PathBuf};

#[derive(Parser)]
#[command(name = "stoa-relay", about = "Stoa Circuit Relay v2 server")]
struct Cli {
    /// Port to listen on
    #[arg(short, long, default_value = "4001")]
    port: u16,

    /// Path to persist the keypair (gives a stable PeerID across restarts — recommended for production)
    #[arg(short, long)]
    key_file: Option<PathBuf>,
}

#[derive(NetworkBehaviour)]
struct RelayBehaviour {
    relay: relay::Behaviour,
    identify: identify::Behaviour,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let args = Cli::parse();

    let keypair = load_or_generate_keypair(args.key_file.as_deref())?;
    let peer_id = PeerId::from(keypair.public());

    println!("╔══════════════════════════════════════════════════╗");
    println!("║              Stoa Relay Server                   ║");
    println!("╠══════════════════════════════════════════════════╣");
    println!("║  PeerID : {peer_id}");
    println!("║  Port   : {}", args.port);
    println!("╚══════════════════════════════════════════════════╝");

    // Generous limits for a hosted relay; tune to your VPS resources
    let relay_config = relay::Config {
        max_reservations: 1024,
        max_circuits: 256,
        max_circuit_bytes: 64 * 1024 * 1024, // 64 MiB per circuit
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
    };

    let mut swarm = libp2p::Swarm::new(
        transport,
        behaviour,
        peer_id,
        libp2p::swarm::Config::with_tokio_executor(),
    );

    let listen_addr: Multiaddr = format!("/ip4/0.0.0.0/tcp/{}", args.port).parse()?;
    swarm.listen_on(listen_addr)?;

    loop {
        match swarm.select_next_some().await {
            SwarmEvent::NewListenAddr { address, .. } => {
                println!("[Relay] Listening: {address}/p2p/{peer_id}");
                println!("[Relay] ↑ Share this address with your Stoa users");
            }
            SwarmEvent::Behaviour(RelayBehaviourEvent::Relay(event)) => {
                println!("[Relay] {:?}", event);
            }
            SwarmEvent::ConnectionEstablished { peer_id, .. } => {
                println!("[Relay] Peer connected:    {peer_id}");
            }
            SwarmEvent::ConnectionClosed { peer_id, cause, .. } => {
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
