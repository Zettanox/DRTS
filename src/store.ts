import { createSignal } from "solid-js";
import { createStore } from "solid-js/store";

export type ConnectionType = "LAN" | "Internet" | "Offline";

export interface Peer {
  id: string;
  name: string;
  status: ConnectionType;
}

export interface Message {
  id: string;
  senderId: string;
  content: string;
  timestamp: number;
  delivered: boolean;
  fileInfo?: FileInfo;
}

export interface FileInfo {
  transferId: string;
  fileName: string;
  fileSize: number;
  direction: "upload" | "download";
  progress: number;
  status: "transferring" | "complete" | "failed";
  chunkCount: number;
  filePath?: string;
}

export interface Chat {
  id: string;
  name: string;
  participants: string[];
  messages: Message[];
}

export interface StoredFile {
  id: string;
  name: string;
  sizeBytes: number;
  lastModified: number;
}

export interface Endbox {
  id: string;
  name: string;
  collaborators: string[];
  files: StoredFile[];
  host: string;
  createdAt: number;
}

export interface NearbyPeerEntry {
  peerId: string;
  addresses: string[];
  displayName: string | null;
}

export interface ContactEntry {
  peerId: string;
  petname: string;
  addedAt: number;
  trustLevel: string;
  online: boolean;
}

export interface ContactRequestEntry {
  fromPeerId: string;
  fromName: string;
}

// ─── Signals ──────────────────────────────────────────────────────────────────

export const [identity, setIdentity] = createSignal<{
  peerId: string;
  publicKey: string;
  name: string;
} | null>(null);

export const [theme, setTheme] = createSignal<"dark" | "light">("dark");
export const [globalNetwork, setGlobalNetwork] = createSignal<"Auto" | "LAN-Only" | "Online-Only">("Auto");
export const [lanVisible, setLanVisible] = createSignal(true);

// Desktop Split Pane Logic
export type PaneState = { type: "dm" | "group" | "endbox"; id: string } | null;
export const [activeLeftPane, setActiveLeftPane] = createSignal<PaneState>(null);
export const [activeRightPane, setActiveRightPane] = createSignal<PaneState>(null);

// ─── Stores ───────────────────────────────────────────────────────────────────

export const [peers, setPeers] = createStore<Peer[]>([]);

export const [nearbyPeers, setNearbyPeers] = createStore<NearbyPeerEntry[]>([]);

export const [contacts, setContacts] = createStore<ContactEntry[]>([]);

export const [pendingRequests, setPendingRequests] = createStore<ContactRequestEntry[]>([]);

export const [dms, setDMs] = createStore<Chat[]>([]);

export const [groups, setGroups] = createStore<Chat[]>([]);

export const [endboxes, setEndboxes] = createStore<Endbox[]>([
  {
    id: "end1",
    name: "Stoa Assets Base",
    collaborators: [],
    host: "me",
    createdAt: Date.now() - 86400000,
    files: [
      { id: "f1", name: "logo.png", sizeBytes: 102400, lastModified: Date.now() - 3600000 },
      { id: "f2", name: "pitch_deck.pdf", sizeBytes: 5242880, lastModified: Date.now() - 7200000 },
    ],
  },
  {
    id: "end2",
    name: "Rust Configs",
    collaborators: [],
    host: "me",
    createdAt: Date.now() - 172800000,
    files: [
      { id: "f3", name: "libp2p_params.toml", sizeBytes: 2048, lastModified: Date.now() - 1800000 },
      { id: "f4", name: "keys.json", sizeBytes: 512, lastModified: Date.now() - 1900000 },
    ],
  },
]);

// Chat messages keyed by peer ID
export const [chatMessages, setChatMessages] = createStore<Record<string, Message[]>>({});

// ─── Helpers ──────────────────────────────────────────────────────────────────

export function toggleTheme() {
  setTheme((t) => (t === "dark" ? "light" : "dark"));
  if (theme() === "dark") {
    document.documentElement.classList.add("dark");
  } else {
    document.documentElement.classList.remove("dark");
  }
}

/** Build DM entries from contacts list */
export function syncDMsFromContacts() {
  const currentContacts = contacts;
  const dmList: Chat[] = currentContacts.map((c) => ({
    id: `dm_${c.peerId}`,
    name: c.petname,
    participants: [c.peerId],
    messages: [],
  }));
  setDMs(dmList);
}
