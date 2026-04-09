import { Component, For, Show } from "solid-js";
import { pendingRequests } from "../store";
import { addContactFromRequest, respondContactRequest } from "../tauri-bridge";
import { UserPlus, X, ShieldCheck } from "lucide-solid";

export const ContactRequestModal: Component = () => {
  const handleAccept = async (fromPeerId: string, fromName: string) => {
    await respondContactRequest(fromPeerId, true);
    await addContactFromRequest(fromPeerId, fromName);
  };

  const handleReject = async (fromPeerId: string) => {
    await respondContactRequest(fromPeerId, false);
  };

  return (
    <Show when={pendingRequests.length > 0}>
      <div class="fixed top-4 right-4 z-50 flex flex-col gap-3 max-w-sm">
        <For each={pendingRequests}>
          {(req) => (
            <div class="flat-panel p-4 flex flex-col gap-3 animate-in slide-in-from-right">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-lg bg-emerald-200 border-2 border-stone-800 flex items-center justify-center text-stone-900 shadow-[2px_2px_0px_0px_rgba(41,37,36,1)]">
                  <UserPlus size={20} />
                </div>
                <div class="flex-1 min-w-0">
                  <div class="font-black text-stone-900 dark:text-stone-100 text-sm">Contact Request</div>
                  <div class="text-xs font-bold text-stone-500 truncate">{req.fromName}</div>
                </div>
              </div>

              <div class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 rounded-md p-2">
                <div class="flex items-center gap-2 text-xs font-mono text-stone-500">
                  <ShieldCheck size={12} />
                  <span class="truncate">{req.fromPeerId}</span>
                </div>
              </div>

              <div class="flex gap-2">
                <button
                  class="flat-button py-2 px-4 flex-1 text-sm flex items-center justify-center gap-2"
                  onClick={() => handleAccept(req.fromPeerId, req.fromName)}
                >
                  <UserPlus size={14} /> Accept
                </button>
                <button
                  class="flat-button-secondary py-2 px-4 text-sm flex items-center justify-center gap-2"
                  onClick={() => handleReject(req.fromPeerId)}
                >
                  <X size={14} /> Reject
                </button>
              </div>
            </div>
          )}
        </For>
      </div>
    </Show>
  );
};
