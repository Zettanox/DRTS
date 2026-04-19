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
  status: "transferring" | "paused" | "complete" | "failed";
  chunkCount: number;
  filePath?: string;
}

export interface Chat {
  id: string;
  name: string;
  participants: string[];
  messages: Message[];
  admin?: string;
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

/** Backend group data from Rust */
export interface GroupEntry {
  id: string;
  name: string;
  members: string[];
  admin: string;
  created_at: number;
}

/** A file within a group's Shared Space */
export interface SpaceFile {
  id: string;
  name: string;
  added_by: string;
  timestamp: number;
  deleted: boolean;
}

// ─── Signals ──────────────────────────────────────────────────────────────────

export const [identity, setIdentity] = createSignal<{
  peerId: string;
  publicKey: string;
  name: string;
} | null>(null);

// Initialise from localStorage; fall back to "dark" if nothing stored yet.
// Also apply to the DOM immediately so there is no flash on load.
const _savedTheme = (localStorage.getItem("stoa-theme") as "dark" | "light" | null) ?? "dark";
if (_savedTheme === "dark") {
  document.documentElement.classList.add("dark");
} else {
  document.documentElement.classList.remove("dark");
}
export const [theme, setTheme] = createSignal<"dark" | "light">(_savedTheme);
export const [globalNetwork, setGlobalNetwork] = createSignal<"Auto" | "LAN-Only" | "Online-Only">("Auto");
export const [lanVisible, setLanVisible] = createSignal(true);

// Desktop Split Pane Logic
export type PaneState = { type: "dm" | "group"; id: string } | null;
export const [activeLeftPane, setActiveLeftPane] = createSignal<PaneState>(null);
export const [activeRightPane, setActiveRightPane] = createSignal<PaneState>(null);

// ─── Stores ───────────────────────────────────────────────────────────────────

export const [peers, setPeers] = createStore<Peer[]>([]);

export const [nearbyPeers, setNearbyPeers] = createStore<NearbyPeerEntry[]>([]);

export const [contacts, setContacts] = createStore<ContactEntry[]>([]);

export const [pendingRequests, setPendingRequests] = createStore<ContactRequestEntry[]>([]);

export const [dms, setDMs] = createStore<Chat[]>([]);

export const [groups, setGroups] = createStore<Chat[]>([]);


// Chat messages keyed by peer ID (for DMs) or group_<id> (for groups)
export const [chatMessages, setChatMessages] = createStore<Record<string, Message[]>>({});
// Group messages keyed by group_<id>
export const [groupMessages, setGroupMessages] = createStore<Record<string, Message[]>>({});

// ─── Helpers ──────────────────────────────────────────────────────────────────

export function toggleTheme() {
  const next = theme() === "dark" ? "light" : "dark";
  setTheme(next);
  localStorage.setItem("stoa-theme", next);
  if (next === "dark") {
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

/** Build group entries from backend data */
export function syncGroupsFromBackend(backendGroups: GroupEntry[]) {
  const groupList: Chat[] = backendGroups.map((g) => ({
    id: `group_${g.id}`,
    name: g.name,
    participants: g.members,
    messages: [],
    admin: g.admin,
  }));
  setGroups(groupList);
}
