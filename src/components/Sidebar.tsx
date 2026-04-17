import { Component, createSignal, For, Show } from "solid-js";
import { dms, groups, endboxes, nearbyPeers, contacts, activeLeftPane, setActiveLeftPane, lanVisible } from "../store";
import { MessageSquare, FileText, Hash, Search, Radio, UserPlus, Plus } from "lucide-solid";
import { sendContactRequest } from "../tauri-bridge";
import { CreateGroupModal } from "./CreateGroupModal";

export const Sidebar: Component = () => {
  const [search, setSearch] = createSignal("");
  const [showCreateGroup, setShowCreateGroup] = createSignal(false);

  const isActive = (type: string, id: string) =>
    activeLeftPane()?.type === type && activeLeftPane()?.id === id;

  const navigate = (type: "dm" | "group" | "endbox", id: string) => {
    setActiveLeftPane({ type, id });
  };

  /** Truncate a peer ID for display: first 6 + last 4 chars */
  const shortPeerId = (id: string) => {
    if (id.length <= 12) return id;
    return id.slice(0, 6) + "…" + id.slice(-4);
  };

  /** Show displayName @ IP, or just IP if name unknown yet */
  const peerDisplayName = (peer: { peerId: string; addresses: string[]; displayName: string | null }) => {
    const name = peer.displayName || "Peer";
    for (const addr of peer.addresses) {
      const match = addr.match(/\/ip4\/((?:192\.168|10\.|172\.(?:1[6-9]|2\d|3[01]))\.[\d.]+)/);
      if (match) return `${name} @ ${match[1]}`;
    }
    return peer.displayName || shortPeerId(peer.peerId);
  };

  /** Check if a nearby peer is already a contact */
  const isContact = (peerId: string) => {
    return contacts.some((c) => c.peerId === peerId);
  };

  const handleAddContact = async (peerId: string) => {
    try {
      await sendContactRequest(peerId);
    } catch (e) {
      console.error("Failed to send contact request:", e);
    }
  };

  /** Find contact info for a DM */
  const contactForDM = (dmId: string) => {
    const peerId = dmId.replace("dm_", "");
    return contacts.find((c) => c.peerId === peerId);
  };

  return (
    <aside class={`w-full md:w-80 border-r-2 border-stone-800 dark:border-stone-700 bg-primary-50 dark:bg-[#1a1513] flex-col h-full overflow-y-auto ${activeLeftPane() ? 'hidden md:flex' : 'flex'}`}>
      <div class="p-4 flex-1 flex flex-col gap-6 mt-2">
        
        {/* Search */}
        <div class="relative chamfer-all chamfer-shadow flex" style="--chamfer-outer: 8px; --chamfer-inner: 6px; --bg-color: var(--color-white)">
          <Search size={16} class="absolute left-3 top-1/2 -translate-y-1/2 text-stone-500 z-10" />
          <input 
            type="text" 
            placeholder="Search DMs, Groups, Endboxes..." 
            class="w-full bg-transparent border-none py-2 pl-9 pr-3 text-sm font-bold text-stone-900 dark:text-stone-100 placeholder-stone-500 focus:outline-none relative z-10"
            value={search()}
            onInput={(e) => setSearch(e.currentTarget.value)}
          />
        </div>

        {/* DMs Section — from real contacts */}
        <div>
          <h2 class="text-xs font-black text-stone-500 dark:text-stone-500 uppercase tracking-widest mb-3 px-2">
            Direct Messages
          </h2>
          <div class="flex flex-col gap-1.5">
            <Show when={dms.length > 0} fallback={
              <p class="text-xs font-bold text-stone-400 dark:text-stone-600 px-2 italic">No contacts yet — add someone from Nearby</p>
            }>
              <For each={dms}>
                {(dm) => {
                  const contact = () => contactForDM(dm.id);
                  return (
                    <button
                      onClick={() => navigate('dm', dm.id)}
                      class={`flex items-center gap-3 w-full text-left px-3 py-2.5 font-bold transition-colors rounded-xl ${
                        isActive('dm', dm.id)
                          ? "chamfer-tl-br chamfer-shadow text-stone-900 dark:text-stone-100"
                          : "text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/50 dark:hover:bg-stone-800/50"
                      }`}
                      style={isActive('dm', dm.id) ? { "--chamfer-outer": "8px", "--chamfer-inner": "6px", "--shadow-x": "2px", "--shadow-y": "2px" } : {}}
                    >
                      <MessageSquare size={16} />
                      <div class="flex-1 truncate text-sm">{dm.name}</div>
                      <div class={`w-2.5 h-2.5 rounded-full border-2 border-stone-800 ${contact()?.online ? 'bg-emerald-500' : 'bg-stone-400'}`}></div>
                    </button>
                  );
                }}
              </For>
            </Show>
          </div>
        </div>

        {/* Groups Section */}
        <div>
          <h2 class="text-xs font-black text-stone-500 dark:text-stone-500 uppercase tracking-widest mb-3 px-2 flex items-center justify-between">
            Groups
            <button
              class="hover:bg-stone-200 dark:hover:bg-stone-800 p-1 rounded-md transition-colors text-stone-600"
              title="Create Group"
              onClick={() => setShowCreateGroup(true)}
            >
              <Plus size={14} />
            </button>
          </h2>
          <div class="flex flex-col gap-1.5">
            <Show when={groups.length > 0} fallback={
              <p class="text-xs font-bold text-stone-400 dark:text-stone-600 px-2 italic">No groups yet</p>
            }>
              <For each={groups}>
                {(group) => (
                  <button
                    onClick={() => navigate('group', group.id)}
                    class={`flex items-center gap-3 w-full text-left px-3 py-2.5 font-bold transition-colors rounded-xl ${
                      isActive('group', group.id)
                        ? "chamfer-tl-br chamfer-shadow text-stone-900 dark:text-stone-100"
                        : "text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/50 dark:hover:bg-stone-800/50"
                    }`}
                    style={isActive('group', group.id) ? { "--chamfer-outer": "8px", "--chamfer-inner": "6px", "--shadow-x": "2px", "--shadow-y": "2px" } : {}}
                  >
                    <Hash size={16} />
                    <div class="flex-1 truncate text-sm">{group.name}</div>
                    <div class="text-[10px] font-bold text-stone-400">{group.participants.length}</div>
                  </button>
                )}
              </For>
            </Show>
          </div>
        </div>

        {/* Endboxes Section */}
        <div>
          <h2 class="text-xs font-black text-stone-500 dark:text-stone-500 uppercase tracking-widest mb-3 px-2 flex items-center justify-between">
            Endboxes
            <button class="hover:bg-stone-200 dark:hover:bg-stone-800 p-1 rounded-md transition-colors text-stone-600">+</button>
          </h2>
          <div class="flex flex-col gap-1.5">
            <For each={endboxes.slice(0, 5)}>
              {(endbox) => (
                <button
                  onClick={() => navigate('endbox', endbox.id)}
                  class={`flex items-center gap-3 w-full text-left px-3 py-2.5 font-bold transition-colors rounded-xl ${
                    isActive('endbox', endbox.id)
                       ? "chamfer-tl-br chamfer-shadow text-stone-900 dark:text-stone-100"
                      : "text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-100 hover:bg-stone-200/50 dark:hover:bg-stone-800/50"
                  }`}
                  style={isActive('endbox', endbox.id) ? { "--chamfer-outer": "8px", "--chamfer-inner": "6px", "--shadow-x": "2px", "--shadow-y": "2px" } : {}}
                >
                  <div class="p-1.5 rounded-lg bg-[#669ff4] border-2 border-stone-800 text-stone-900">
                    <FileText size={16} />
                  </div>
                  <div class="flex-1 truncate text-sm">{endbox.name}</div>
                </button>
              )}
            </For>
          </div>
        </div>

        {/* Nearby Peers Section */}
        <div>
          <h2 class="text-xs font-black text-stone-500 dark:text-stone-500 uppercase tracking-widest mb-3 px-2 flex items-center gap-2">
            <Radio size={12} class={lanVisible() ? "text-emerald-500" : "text-stone-400"} />
            Nearby
            <Show when={!lanVisible()}>
              <span class="text-[10px] font-bold text-stone-400 normal-case tracking-normal ml-1">(hidden)</span>
            </Show>
          </h2>
          <div class="flex flex-col gap-1.5">
            <Show when={lanVisible() && nearbyPeers.length > 0} fallback={
              <p class="text-xs font-bold text-stone-400 dark:text-stone-600 px-2 italic">
                {lanVisible() ? "Scanning local network…" : "Visibility is off"}
              </p>
            }>
              <For each={nearbyPeers.slice(0, 8)}>
                {(peer) => (
                  <div class="flex items-center gap-3 w-full px-3 py-2.5 rounded-xl text-stone-600 dark:text-stone-400 hover:bg-stone-200/50 dark:hover:bg-stone-800/50 transition-colors">
                    <div class="w-2.5 h-2.5 rounded-full bg-emerald-400 border-2 border-stone-800 animate-pulse shrink-0"></div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-bold truncate">{peerDisplayName(peer)}</div>
                      <div class="text-[10px] font-medium text-stone-400">{peer.addresses.length} addr{peer.addresses.length !== 1 ? 's' : ''}</div>
                    </div>
                    <Show when={!isContact(peer.peerId)}>
                      <button
                        class="p-1.5 text-stone-500 hover:text-primary-600 dark:hover:text-primary-400 hover:bg-stone-200 dark:hover:bg-stone-800 rounded-lg transition-colors shrink-0"
                        title="Add as contact"
                        onClick={() => handleAddContact(peer.peerId)}
                      >
                        <UserPlus size={14} />
                      </button>
                    </Show>
                    <Show when={isContact(peer.peerId)}>
                      <span class="text-[10px] font-bold text-emerald-500 uppercase">Contact</span>
                    </Show>
                  </div>
                )}
              </For>
            </Show>
          </div>
        </div>

      </div>

      {/* Create Group Modal */}
      <Show when={showCreateGroup()}>
        <CreateGroupModal onClose={() => setShowCreateGroup(false)} />
      </Show>
    </aside>
  );
};
