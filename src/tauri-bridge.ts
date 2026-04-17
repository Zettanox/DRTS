import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open, save } from "@tauri-apps/plugin-dialog";
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
  syncGroupsFromBackend,
  setGroups,
  groups,
  setGroupMessages,
  groupMessages,
  Message,
  GroupEntry,
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
  display_name: string | null;
}

export interface RustContact {
  peer_id: string;
  petname: string;
  added_at: number;
  trust_level: string;
}

export interface RustStoredFileInfo {
  transfer_id: string;
  file_name: string;
  file_size: number;
  direction: string;
  status: string;
  file_path?: string;
}

export interface RustStoredMessage {
  id: string;
  sender_id: string;
  content: string;
  timestamp: number;
  delivered: boolean;
  file_info?: RustStoredFileInfo;
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

/** Map a stored message from Rust to the frontend Message type. */
function mapStoredMessage(m: RustStoredMessage): Message {
  return {
    id: m.id,
    senderId: m.sender_id,
    content: m.content,
    timestamp: m.timestamp,
    delivered: m.delivered,
    fileInfo: m.file_info ? {
      transferId: m.file_info.transfer_id,
      fileName: m.file_info.file_name,
      fileSize: m.file_info.file_size,
      direction: m.file_info.direction as "upload" | "download",
      progress: m.file_info.status === "complete" ? 1 : 0,
      status: m.file_info.status as "transferring" | "paused" | "complete" | "failed",
      chunkCount: 0,
      filePath: m.file_info.file_path,
    } : undefined,
  };
}

export async function getChatHistory(peerId: string): Promise<void> {
  const msgs = await invoke<RustStoredMessage[]>("get_chat_history", {
    peerId,
  });
  setChatMessages((prev) => ({
    ...prev,
    [peerId]: msgs.map(mapStoredMessage),
  }));
}

/** Update the user's display name. */
export async function setUsername(newName: string): Promise<string> {
  const name = await invoke<string>("set_username", { newName });
  setIdentity((prev) => prev ? { ...prev, name } : null);
  return name;
}

/** Open file picker and send the selected file to a peer. */
export async function sendFile(peerId: string): Promise<void> {
  const file = await open({
    multiple: false,
    title: "Select a file to send",
  });
  if (file) {
    await invoke("send_file", { peerId, filePath: file });
  }
}

/** Pause an ongoing file transfer (upload or download) */
export async function pauseFileTransfer(transferId: string): Promise<void> {
  await invoke("pause_transfer", { transferId });
  setChatMessages((prev) => {
    const next = { ...prev };
    for (const [peerId, msgs] of Object.entries(next)) {
      next[peerId] = msgs.map((m) =>
        m.fileInfo?.transferId === transferId
          ? { ...m, fileInfo: { ...m.fileInfo, status: "paused" } }
          : m
      );
    }
    return next;
  });
}

/** Resume a paused file transfer */
export async function resumeFileTransfer(transferId: string): Promise<void> {
  await invoke("resume_transfer", { transferId });
  setChatMessages((prev) => {
    const next = { ...prev };
    for (const [peerId, msgs] of Object.entries(next)) {
      next[peerId] = msgs.map((m) =>
        m.fileInfo?.transferId === transferId
          ? { ...m, fileInfo: { ...m.fileInfo, status: "transferring" } }
          : m
      );
    }
    return next;
  });
}

// ─── Group Commands ───────────────────────────────────────────────────────────────

export async function createGroup(
  name: string,
  memberIds: string[]
): Promise<void> {
  await invoke("create_group", { name, memberIds });
}

export async function getGroups(): Promise<void> {
  const gs = await invoke<GroupEntry[]>("get_groups");
  syncGroupsFromBackend(gs);
}

export async function sendGroupMessage(
  groupId: string,
  content: string
): Promise<string> {
  const messageId = await invoke<string>("send_group_message", {
    groupId,
    content,
  });

  // Optimistic local update
  const groupKey = `group_${groupId}`;
  const msg: Message = {
    id: messageId,
    senderId: "me",
    content,
    timestamp: Date.now() / 1000,
    delivered: false,
  };

  setGroupMessages((prev) => ({
    ...prev,
    [groupKey]: [...(prev[groupKey] || []), msg],
  }));

  return messageId;
}

export async function sendGroupFile(groupId: string): Promise<void> {
  const file = await open({
    multiple: false,
    title: "Select a file to send to group",
  });
  if (file) {
    await invoke("send_group_file", { groupId, filePath: file });
  }
}

export async function getGroupHistory(groupId: string): Promise<void> {
  const msgs = await invoke<RustStoredMessage[]>("get_group_history", {
    groupId,
  });
  const groupKey = `group_${groupId}`;
  setGroupMessages((prev) => ({
    ...prev,
    [groupKey]: msgs.map(mapStoredMessage),
  }));
}

export async function leaveGroup(groupId: string): Promise<void> {
  await invoke("leave_group", { groupId });
  // Remove from local store
  setGroups((prev) => prev.filter((g) => g.id !== `group_${groupId}`));
}

export async function removeGroupMember(
  groupId: string,
  peerId: string
): Promise<void> {
  await invoke("remove_group_member", { groupId, peerId });
}

export async function disbandGroup(groupId: string): Promise<void> {
  await invoke("disband_group", { groupId });
  setGroups((prev) => prev.filter((g) => g.id !== `group_${groupId}`));
}

// ─── Group Spaces ─────────────────────────────────────────────────────────────

import type { SpaceFile } from "./store";

export async function openGroupSpace(groupId: string): Promise<void> {
  await invoke("open_group_space", { groupId });
}

export async function listSpaceFiles(groupId: string): Promise<SpaceFile[]> {
  return await invoke<SpaceFile[]>("list_space_files", { groupId });
}

export async function createSpaceFile(groupId: string, fileName: string): Promise<void> {
  await invoke("create_space_file", { groupId, fileName });
}

export async function importSpaceFile(groupId: string): Promise<void> {
  const file = await open({
    multiple: false,
    title: "Select a text file to import into Shared Space",
  });
  if (!file) throw new Error("No file selected");
  await invoke("import_space_file", { groupId, filePath: file });
}

export async function deleteSpaceFile(groupId: string, fileId: string): Promise<void> {
  await invoke("delete_space_file", { groupId, fileId });
}

export async function getSpaceFileText(groupId: string, fileId: string): Promise<string> {
  return await invoke<string>("get_space_file_text", { groupId, fileId });
}

export async function exportSpaceFile(groupId: string, fileId: string, fileName: string): Promise<void> {
  const savePath = await save({
    title: "Export file from Shared Space",
    defaultPath: fileName,
  });
  if (!savePath) return;
  await invoke("export_space_file", { groupId, fileId, exportPath: savePath });
}

export async function editSpaceFile(
  groupId: string,
  fileId: string,
  index: number,
  deleteCount: number,
  insertText: string
): Promise<void> {
  await invoke("edit_space_file", { groupId, fileId, index, deleteCount, insertText });
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
        (prev) => ({
          ...prev,
          addresses: incoming.addresses,
          displayName: incoming.display_name ?? prev.displayName,
        })
      );
    } else {
      setNearbyPeers((prev) => [
        ...prev,
        { peerId: incoming.peer_id, addresses: incoming.addresses, displayName: incoming.display_name ?? null },
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

  // ─── File transfer state tracking ─────────────────────────────────────────
  // Maps transfer_id → peer_id for lookup during progress/complete events
  const transferPeerMap: Record<string, string> = {};

  // File transfer events
  await listen<{
    transfer_id: string;
    peer_id: string;
    file_name: string;
    file_size: number;
    direction: string;
    chunk_count: number;
    sender_name?: string;
  }>("file-transfer-started", (event) => {
    const { transfer_id, peer_id, file_name, file_size, direction, chunk_count } = event.payload;
    console.log(`[File] Transfer started: ${file_name} (${direction}) with ${peer_id}`);

    // Track this transfer
    transferPeerMap[transfer_id] = peer_id;

    // Add a file message to chat
    const msg: Message = {
      id: `file-${transfer_id}`,
      senderId: direction === "upload" ? "me" : peer_id,
      content: `📎 ${file_name}`,
      timestamp: Math.floor(Date.now() / 1000),
      delivered: false,
      fileInfo: {
        transferId: transfer_id,
        fileName: file_name,
        fileSize: file_size,
        direction: direction as "upload" | "download",
        progress: 0,
        status: "transferring",
        chunkCount: chunk_count,
      },
    };

    setChatMessages((prev) => ({
      ...prev,
      [peer_id]: [...(prev[peer_id] || []), msg],
    }));
  });

  // Group file transfer events
  await listen<{
    group_id: string;
    transfer_id: string;
    peer_id: string;
    file_name: string;
    file_size: number;
    direction: string;
    chunk_count: number;
    sender_name?: string;
  }>("group-file-transfer-started", (event) => {
    const { group_id, transfer_id, peer_id, file_name, file_size, direction, chunk_count, sender_name } = event.payload;
    console.log(`[File] Group transfer started: ${file_name} (${direction}) in group ${group_id}`);

    // Track with a special group prefix so progress/complete can find it
    transferPeerMap[transfer_id] = `__group__${group_id}`;

    const groupKey = `group_${group_id}`;
    const isUpload = direction === "upload";

    const msg: Message = {
      id: `file-${transfer_id}`,
      senderId: isUpload ? "me" : peer_id,
      content: isUpload ? `📎 File offered: ${file_name}` : `📎 ${file_name}`,
      timestamp: Math.floor(Date.now() / 1000),
      delivered: isUpload,  // Uploads are "delivered" immediately since we don't track per-member progress
      fileInfo: {
        transferId: transfer_id,
        fileName: file_name,
        fileSize: file_size,
        direction: direction as "upload" | "download",
        progress: isUpload ? 1 : 0,  // Uploads show as complete immediately
        status: isUpload ? "complete" : "transferring",
        chunkCount: chunk_count,
      },
    };

    setGroupMessages((prev) => ({
      ...prev,
      [groupKey]: [...(prev[groupKey] || []), msg],
    }));
  });

  await listen<{
    transfer_id: string;
    chunk_index: number;
    chunk_count: number;
    progress: number;
  }>("file-transfer-progress", (event) => {
    const { transfer_id, progress } = event.payload;
    const msgId = `file-${transfer_id}`;
    const target = transferPeerMap[transfer_id];
    if (!target) return;

    if (target.startsWith("__group__")) {
      // Group file progress
      const groupKey = `group_${target.replace("__group__", "")}`;
      const msgs = groupMessages[groupKey];
      if (msgs) {
        setGroupMessages((prev) => ({
          ...prev,
          [groupKey]: prev[groupKey]?.map((m) =>
            m.id === msgId && m.fileInfo
              ? { ...m, fileInfo: { ...m.fileInfo, progress } }
              : m
          ) || [],
        }));
      }
    } else {
      // DM file progress
      const msgs = chatMessages[target];
      if (msgs) {
        setChatMessages((prev) => ({
          ...prev,
          [target]: prev[target]?.map((m) =>
            m.id === msgId && m.fileInfo
              ? { ...m, fileInfo: { ...m.fileInfo, progress } }
              : m
          ) || [],
        }));
      }
    }
  });

  await listen<{
    transfer_id: string;
    peer_id: string;
    file_name: string;
    file_path?: string;
    file_size: number;
    direction: string;
  }>("file-transfer-complete", (event) => {
    const { transfer_id, file_name, file_path } = event.payload;
    console.log(`[File] Transfer complete: ${file_name}`);
    const msgId = `file-${transfer_id}`;
    const target = transferPeerMap[transfer_id];
    if (!target) return;

    if (target.startsWith("__group__")) {
      const groupKey = `group_${target.replace("__group__", "")}`;
      setGroupMessages((prev) => ({
        ...prev,
        [groupKey]: prev[groupKey]?.map((m) =>
          m.id === msgId
            ? {
                ...m,
                delivered: true,
                fileInfo: m.fileInfo ? {
                  ...m.fileInfo,
                  progress: 1,
                  status: "complete" as const,
                  filePath: file_path,
                } : undefined,
              }
            : m
        ) || [],
      }));
    } else {
      setChatMessages((prev) => ({
        ...prev,
        [target]: prev[target]?.map((m) =>
          m.id === msgId
            ? {
                ...m,
                delivered: true,
                fileInfo: m.fileInfo ? {
                  ...m.fileInfo,
                  progress: 1,
                  status: "complete" as const,
                  filePath: file_path,
                } : undefined,
              }
            : m
        ) || [],
      }));
    }

    // Clean up tracking
    delete transferPeerMap[transfer_id];
  });

  // Load contacts after listeners are set up
  await getContacts();

  // ─── Group Event Listeners ───────────────────────────────────────────────

  await listen<{
    id: string;
    name: string;
    members: string[];
    admin: string;
    created_at: number;
  }>("group-created", async () => {
    await getGroups();
  });

  await listen<{
    group_id: string;
    group_name: string;
    members: string[];
    admin: string;
    inviter_name: string;
  }>("group-invite", async () => {
    await getGroups();
  });

  await listen<{
    group_id: string;
    id: string;
    sender_id: string;
    sender_name: string;
    content: string;
    timestamp: number;
  }>("group-message", (event) => {
    const { group_id, id, sender_id, sender_name, content, timestamp } =
      event.payload;
    const groupKey = `group_${group_id}`;
    const msg: Message = {
      id,
      senderId: sender_id,
      content,
      timestamp,
      delivered: true,
    };

    setGroupMessages((prev) => ({
      ...prev,
      [groupKey]: [...(prev[groupKey] || []), msg],
    }));
  });

  await listen<{ group_id: string; reason: string }>("group-removed", async (event) => {
    const { group_id } = event.payload;
    setGroups((prev) => prev.filter((g) => g.id !== `group_${group_id}`));
  });

  await listen<{ group_id: string; removed: string }>("group-member-update", async () => {
    await getGroups();
  });

  // Load groups
  await getGroups();
}
