import { Component, createSignal, For } from "solid-js";
import { contacts } from "../store";
import { createGroup } from "../tauri-bridge";
import { X, Users, Check } from "lucide-solid";

export const CreateGroupModal: Component<{ onClose: () => void }> = (props) => {
  const [groupName, setGroupName] = createSignal("");
  const [selectedPeers, setSelectedPeers] = createSignal<Set<string>>(new Set());

  const togglePeer = (peerId: string) => {
    setSelectedPeers((prev) => {
      const next = new Set(prev);
      if (next.has(peerId)) {
        next.delete(peerId);
      } else {
        next.add(peerId);
      }
      return next;
    });
  };

  const handleCreate = async () => {
    const name = groupName().trim();
    if (!name || selectedPeers().size === 0) return;

    try {
      await createGroup(name, [...selectedPeers()]);
      props.onClose();
    } catch (e) {
      console.error("Failed to create group:", e);
    }
  };

  return (
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-in fade-in duration-200">
      <div class="w-full max-w-md mx-4">
        <div class="flat-panel-all p-0 overflow-hidden" style="--chamfer-outer: 12px; --chamfer-inner: 10px;">
          {/* Header */}
          <div class="flex items-center justify-between px-6 py-4 border-b-2 border-stone-800 dark:border-stone-700 bg-white dark:bg-[#2c2421]">
            <div class="flex items-center gap-3">
              <div class="p-2 rounded-lg bg-primary-100 dark:bg-primary-900/30 text-primary-600 dark:text-primary-400">
                <Users size={20} />
              </div>
              <h2 class="text-lg font-black text-stone-900 dark:text-stone-100">Create Group</h2>
            </div>
            <button
              onClick={props.onClose}
              class="p-2 text-stone-500 hover:text-stone-800 dark:hover:text-stone-100 hover:bg-stone-200 dark:hover:bg-stone-800 rounded-lg transition-colors"
            >
              <X size={20} />
            </button>
          </div>

          {/* Body */}
          <div class="p-6 space-y-5 bg-primary-50 dark:bg-[#1a1513]">
            {/* Group Name */}
            <div>
              <label class="block text-xs font-black uppercase tracking-wider text-stone-500 mb-2">
                Group Name
              </label>
              <div class="chamfer-all chamfer-shadow" style="--chamfer-outer: 8px; --chamfer-inner: 6px; --bg-color: var(--color-white)">
                <input
                  type="text"
                  placeholder="e.g. Project Alpha"
                  class="w-full bg-transparent border-none py-2.5 px-4 text-sm font-bold text-stone-900 dark:text-stone-100 placeholder-stone-400 focus:outline-none relative z-10"
                  value={groupName()}
                  onInput={(e) => setGroupName(e.currentTarget.value)}
                  autofocus
                />
              </div>
            </div>

            {/* Contact Selection */}
            <div>
              <label class="block text-xs font-black uppercase tracking-wider text-stone-500 mb-2">
                Select Members ({selectedPeers().size} selected)
              </label>
              <div class="max-h-48 overflow-y-auto space-y-1.5 pr-1">
                <For each={contacts} fallback={
                  <p class="text-xs font-bold text-stone-400 italic py-3 text-center">
                    No contacts yet — add someone from Nearby first
                  </p>
                }>
                  {(contact) => {
                    const isSelected = () => selectedPeers().has(contact.peerId);
                    return (
                      <button
                        onClick={() => togglePeer(contact.peerId)}
                        class={`flex items-center gap-3 w-full text-left px-3 py-2.5 rounded-xl font-bold transition-all ${
                          isSelected()
                            ? "chamfer-tl-br chamfer-shadow text-stone-900 dark:text-stone-100"
                            : "text-stone-600 dark:text-stone-400 hover:bg-stone-200/50 dark:hover:bg-stone-800/50"
                        }`}
                        style={isSelected() ? { "--chamfer-outer": "8px", "--chamfer-inner": "6px", "--shadow-x": "2px", "--shadow-y": "2px" } : {}}
                      >
                        <div class={`w-5 h-5 rounded-md border-2 flex items-center justify-center transition-colors ${
                          isSelected()
                            ? "bg-primary-500 border-primary-600 text-white"
                            : "border-stone-400 dark:border-stone-600"
                        }`}>
                          {isSelected() && <Check size={12} />}
                        </div>
                        <div class="flex-1 truncate text-sm">{contact.petname}</div>
                        <div class={`w-2.5 h-2.5 rounded-full border-2 border-stone-800 ${
                          contact.online ? "bg-emerald-500" : "bg-stone-400"
                        }`}></div>
                      </button>
                    );
                  }}
                </For>
              </div>
            </div>
          </div>

          {/* Footer */}
          <div class="flex justify-end gap-3 px-6 py-4 border-t-2 border-stone-800 dark:border-stone-700 bg-white dark:bg-[#2c2421]">
            <button
              onClick={props.onClose}
              class="flat-button-secondary py-2 px-4 text-sm"
            >
              Cancel
            </button>
            <button
              onClick={handleCreate}
              disabled={!groupName().trim() || selectedPeers().size === 0}
              class="py-2 px-5 chamfer-all chamfer-shadow chamfer-active flex items-center gap-2 text-sm font-black text-white disabled:opacity-50 disabled:cursor-not-allowed"
              style="--bg-color: var(--color-primary-500); --chamfer-outer: 8px; --chamfer-inner: 6px; --shadow-x: 2px; --shadow-y: 2px;"
            >
              <Users size={16} />
              Create Group
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
