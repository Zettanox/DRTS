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
  isFile?: boolean;
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

// Signals
export const [identity, setIdentity] = createSignal<{ publicKey: string; name: string } | null>(null);
export const [theme, setTheme] = createSignal<"dark" | "light">("dark");
export const [globalNetwork, setGlobalNetwork] = createSignal<"Auto" | "LAN-Only" | "Online-Only">("Auto");

// Desktop Split Pane Logic
export type PaneState = { type: "dm" | "group" | "endbox", id: string } | null;
export const [activeLeftPane, setActiveLeftPane] = createSignal<PaneState>(null);
export const [activeRightPane, setActiveRightPane] = createSignal<PaneState>(null);

// Stores
export const [peers, setPeers] = createStore<Peer[]>([
  { id: "peer1", name: "Alice (Local)", status: "LAN" },
  { id: "peer2", name: "Bob (Remote)", status: "Internet" },
  { id: "peer3", name: "Charlie", status: "Offline" },
]);

export const [dms, setDMs] = createStore<Chat[]>([
  {
    id: "dm1",
    name: "Alice (Local)",
    participants: ["peer1"],
    messages: [
      { id: "m1", senderId: "peer1", content: "Hey! Are you on the local network?", timestamp: Date.now() - 100000 },
      { id: "m2", senderId: "me", content: "Yes! Connecting via LAN now. It's super fast.", timestamp: Date.now() - 50000 }
    ],
  }
]);

export const [groups, setGroups] = createStore<Chat[]>([
  {
    id: "group1",
    name: "Stoa Dev Group",
    participants: ["peer1", "peer2"],
    messages: [
      { id: "m3", senderId: "peer2", content: "Sending the latest build now.", timestamp: Date.now() - 10000 },
    ],
  }
]);

export const [endboxes, setEndboxes] = createStore<Endbox[]>([
  {
    id: "end1",
    name: "Stoa Assets Base",
    collaborators: ["peer1"],
    host: "me",
    createdAt: Date.now() - 86400000,
    files: [
      { id: "f1", name: "logo.png", sizeBytes: 102400, lastModified: Date.now() - 3600000 },
      { id: "f2", name: "pitch_deck.pdf", sizeBytes: 5242880, lastModified: Date.now() - 7200000 }
    ]
  },
  {
    id: "end2",
    name: "Rust Configs",
    collaborators: ["peer1", "peer2"],
    host: "peer2",
    createdAt: Date.now() - 172800000,
    files: [
      { id: "f3", name: "libp2p_params.toml", sizeBytes: 2048, lastModified: Date.now() - 1800000 },
      { id: "f4", name: "keys.json", sizeBytes: 512, lastModified: Date.now() - 1900000 }
    ]
  }
]);

export function toggleTheme() {
  setTheme(t => t === "dark" ? "light" : "dark");
  if (theme() === "dark") {
    document.documentElement.classList.add("dark");
  } else {
    document.documentElement.classList.remove("dark");
  }
}
