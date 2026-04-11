import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  setIdentity,
  setNearbyPeers,
  nearbyPeers,
  setLanVisible,
  setContacts,
  contacts,
  setPendingRequests,
  pendingRequests,
  setChatMessages,
  chatMessages,
  syncDMsFromContacts,
  Message,
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
  name?: string;
}

export interface RustContact {
  peer_id: string;
  petname: string;
  broadcast_name: string;
  added_at: number;
  trust_level: string;
}

export interface RustStoredMessage {
  id: string;
  sender_id: string;
  content: string;
  timestamp: number;
  delivered: boolean;
}

// ─── Identity Commands ────────────────────────────────────────────────────────

export async function generateIdentity(): Promise<IdentityInfo> {
  const info = await invoke<IdentityInfo>("generate_identity");
  setIdentity({
    peerId: info.peer_id,
    publicKey: info.public_key_hex,
    name: info.name,
  });
  return info;
}

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

export async function exportKeypair(): Promise<string> {
  return invoke<string>("export_keypair");
}

// ─── Visibility Commands ──────────────────────────────────────────────────────

export async function toggleVisibility(visible: boolean): Promise<void> {
  if (!visible) {
    setNearbyPeers([]);
  }
  await invoke("toggle_visibility", { visible });
  setLanVisible(visible);
}

export async function getVisibility(): Promise<boolean> {
  return invoke<boolean>("get_visibility");
}

export async function getNearbyPeers(): Promise<NearbyPeer[]> {
  return invoke<NearbyPeer[]>("get_nearby_peers");
}

export async function showWindow(): Promise<void> {
  await invoke("show_window");
}

// ─── Contact Commands ─────────────────────────────────────────────────────────

export async function getContacts(): Promise<void> {
  const cts = await invoke<RustContact[]>("get_contacts");
  setContacts(
    cts.map((c) => ({
      peerId: c.peer_id,
      petname: c.petname,
      broadcastName: c.broadcast_name || c.petname,
      addedAt: c.added_at,
      trustLevel: c.trust_level,
      online: false,
    }))
  );
  syncDMsFromContacts();
}

export async function sendContactRequest(peerId: string): Promise<void> {
  await invoke("send_contact_request", { peerId });
}

export async function respondContactRequest(
  peerId: string,
  accept: boolean,
  petname: string
): Promise<void> {
  await invoke("respond_contact_request", { peerId, accept, petname });
  setPendingRequests((prev) => prev.filter((r) => r.fromPeerId !== peerId));
  if (accept) {
    await getContacts();
  }
}

export async function addContactFromRequest(
  peerId: string,
  petname: string
): Promise<void> {
  await invoke("add_contact_from_request", { peerId, petname });
  await getContacts(); // Refresh contacts
}

export async function renameContact(
  peerId: string,
  newName: string
): Promise<void> {
  await invoke("rename_contact", { peerId, newName });
  await getContacts();
}

export async function removeContact(peerId: string): Promise<void> {
  await invoke("remove_contact_cmd", { peerId });
  await getContacts();
}

// ─── Messaging Commands ──────────────────────────────────────────────────────

export async function sendMessage(
  peerId: string,
  content: string
): Promise<string> {
  const messageId = await invoke<string>("send_message", { peerId, content });

  // Add to local store immediately (optimistic)
  const msg: Message = {
    id: messageId,
    senderId: "me",
    content,
    timestamp: Date.now() / 1000,
    delivered: false,
  };

  setChatMessages((prev) => ({
    ...prev,
    [peerId]: [...(prev[peerId] || []), msg],
  }));

  return messageId;
}

export async function getChatHistory(peerId: string): Promise<void> {
  const msgs = await invoke<RustStoredMessage[]>("get_chat_history", {
    peerId,
  });
  setChatMessages((prev) => ({
    ...prev,
    [peerId]: msgs.map((m) => ({
      id: m.id,
      senderId: m.sender_id,
      content: m.content,
      timestamp: m.timestamp,
      delivered: m.delivered,
    })),
  }));
}

/** Update the user's display name. */
export async function setUsername(newName: string): Promise<string> {
  const name = await invoke<string>("set_username", { newName });
  setIdentity((prev) => prev ? { ...prev, name } : null);
  return name;
}

// ─── Event Listeners ──────────────────────────────────────────────────────────

export async function setupNetworkListeners(): Promise<void> {
  // Peer discovery
  await listen<NearbyPeer>("peer-discovered", (event) => {
    const incoming = event.payload;
    const existing = nearbyPeers.find((p) => p.peerId === incoming.peer_id);
    if (existing) {
      setNearbyPeers(
        (p) => p.peerId === incoming.peer_id,
        {
          addresses: incoming.addresses,
          name: incoming.name ?? existing.name,
        }
      );
    } else {
      setNearbyPeers((prev) => [
        ...prev,
        { peerId: incoming.peer_id, addresses: incoming.addresses, name: incoming.name },
      ]);
    }
  });

  await listen<string>("peer-expired", (event) => {
    const expiredId = event.payload;
    setNearbyPeers((prev) => prev.filter((p) => p.peerId !== expiredId));
  });

  // Contact online/offline
  await listen<string>("contact-online", (event) => {
    const pid = event.payload;
    setContacts((c) => c.peerId === pid, "online", true);
  });

  await listen<string>("contact-offline", (event) => {
    const pid = event.payload;
    setContacts((c) => c.peerId === pid, "online", false);
  });

  // Contact requests
  await listen<{ from_peer_id: string; from_name: string }>(
    "contact-request",
    (event) => {
      const { from_peer_id, from_name } = event.payload;
      // Avoid duplicates
      const exists = pendingRequests.find(
        (r) => r.fromPeerId === from_peer_id
      );
      if (!exists) {
        setPendingRequests((prev) => [
          ...prev,
          { fromPeerId: from_peer_id, fromName: from_name },
        ]);
      }
    }
  );

  await listen<{ peer_id: string; name: string }>(
    "contact-accepted",
    async (event) => {
      const { peer_id, name } = event.payload;
      // Add to contacts with the peer's actual name
      await addContactFromRequest(peer_id, name);
    }
  );

  // Chat messages
  await listen<{
    id: string;
    sender_id: string;
    sender_name: string;
    content: string;
    timestamp: number;
  }>("chat-message", (event) => {
    const { id, sender_id, content, timestamp } = event.payload;
    const msg: Message = {
      id,
      senderId: sender_id,
      content,
      timestamp,
      delivered: true,
    };

    setChatMessages((prev) => ({
      ...prev,
      [sender_id]: [...(prev[sender_id] || []), msg],
    }));
  });

  // Message delivery acks
  await listen<{ peer_id: string; message_id: string }>(
    "message-ack",
    (event) => {
      const { peer_id, message_id } = event.payload;
      const msgs = chatMessages[peer_id];
      if (msgs) {
        setChatMessages(
          peer_id,
          (m: Message) => m.id === message_id,
          "delivered",
          true
        );
      }
    }
  );

  // Load contacts after listeners are set up
  await getContacts();
}
