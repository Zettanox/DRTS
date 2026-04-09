import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  setIdentity,
  setNearbyPeers,
  nearbyPeers,
  setLanVisible,
} from "./store";

// ─── Types matching Rust structs ──────────────────────────────────────────────

export interface IdentityInfo {
  peer_id: string;
  public_key_hex: string;
  name: string;
}

export interface NearbyPeer {
  peer_id: string;
  addresses: string[];
}

// ─── Tauri Command Wrappers ───────────────────────────────────────────────────

/** Generate (or load) Ed25519 identity and start the LAN network node. */
export async function generateIdentity(): Promise<IdentityInfo> {
  const info = await invoke<IdentityInfo>("generate_identity");
  setIdentity({
    peerId: info.peer_id,
    publicKey: info.public_key_hex,
    name: info.name,
  });
  return info;
}

/** Get current identity if already loaded. */
export async function getIdentity(): Promise<IdentityInfo | null> {
  const info = await invoke<IdentityInfo | null>("get_identity");
  if (info) {
    setIdentity({
      peerId: info.peer_id,
      publicKey: info.public_key_hex,
      name: info.name,
    });
  }
  return info;
}

/** Export keypair as base64 for cross-platform import. */
export async function exportKeypair(): Promise<string> {
  return invoke<string>("export_keypair");
}

/** Toggle mDNS visibility on/off. Kills/respawns the network task. */
export async function toggleVisibility(visible: boolean): Promise<void> {
  if (!visible) {
    // Clear frontend peers immediately
    setNearbyPeers([]);
  }
  await invoke("toggle_visibility", { visible });
  setLanVisible(visible);
}

/** Fetch the current visibility state. */
export async function getVisibility(): Promise<boolean> {
  return invoke<boolean>("get_visibility");
}

/** Fetch snapshots of all currently discovered nearby peers. */
export async function getNearbyPeers(): Promise<NearbyPeer[]> {
  return invoke<NearbyPeer[]>("get_nearby_peers");
}

/** Show the main window (called once frontend is ready). */
export async function showWindow(): Promise<void> {
  await invoke("show_window");
}

// ─── Event Listeners ──────────────────────────────────────────────────────────

/** Subscribe to real-time peer discovery/expiry events from the Rust backend. */
export async function setupNetworkListeners(): Promise<void> {
  await listen<NearbyPeer>("peer-discovered", (event) => {
    const incoming = event.payload;
    const existing = nearbyPeers.find((p) => p.peerId === incoming.peer_id);
    if (existing) {
      // Update addresses for existing peer
      setNearbyPeers(
        (p) => p.peerId === incoming.peer_id,
        "addresses",
        incoming.addresses
      );
    } else {
      // Add new peer
      setNearbyPeers((prev) => [
        ...prev,
        { peerId: incoming.peer_id, addresses: incoming.addresses },
      ]);
    }
  });

  await listen<string>("peer-expired", (event) => {
    const expiredId = event.payload;
    setNearbyPeers((prev) => prev.filter((p) => p.peerId !== expiredId));
  });
}
