import { Component, createSignal, createMemo, createEffect, For, Show, onMount } from "solid-js";
import { dms, groups, contacts, identity, chatMessages, groupMessages, activeRightPane, setActiveRightPane, Message } from "../store";
import { sendMessage as bridgeSendMessage, getChatHistory, sendFile, pauseFileTransfer, resumeFileTransfer, sendGroupMessage, getGroupHistory, sendGroupFile, leaveGroup, removeGroupMember, disbandGroup } from "../tauri-bridge";
import { Send, Paperclip, Users, Shield, X, MapPin, Columns, Check, CheckCheck, Clock, FileIcon, Download, LogOut, UserMinus, Trash2, Hash } from "lucide-solid";

export const ChatView: Component<{ id: string, pane: "left" | "right" }> = (props) => {
  const [inputText, setInputText] = createSignal("");
  const [forceNetwork, setForceNetwork] = createSignal<"Auto" | "LAN" | "Internet">("Auto");
  const [detailsOpen, setDetailsOpen] = createSignal(false);
  let messagesEndRef: HTMLDivElement | undefined;
  
  const currentChat = createMemo(() => dms.find(c => c.id === props.id) || groups.find(c => c.id === props.id));
  const isGroup = createMemo(() => !!groups.find(c => c.id === props.id));

  // Extract peer ID from DM id (dm_<peerId>) or group ID from group_<id>
  const peerId = createMemo(() => {
    if (isGroup()) return null;
    return props.id.replace("dm_", "");
  });

  const groupId = createMemo(() => {
    if (!isGroup()) return null;
    return props.id.replace("group_", "");
  });

  // Am I the admin of this group?
  const isAdmin = createMemo(() => {
    if (!isGroup()) return false;
    const group = groups.find(g => g.id === props.id);
    return group?.admin === identity()?.peerId;
  });

  // Get contact info
  const contact = createMemo(() => {
    const pid = peerId();
    if (!pid) return null;
    return contacts.find(c => c.peerId === pid);
  });

  // Get messages for this chat — DM or Group
  const messages = createMemo(() => {
    if (isGroup()) {
      const gid = groupId();
      if (!gid) return [];
      const groupKey = `group_${gid}`;
      return groupMessages[groupKey] || [];
    }
    const pid = peerId();
    if (!pid) return [];
    return chatMessages[pid] || [];
  });

  // Load chat history on mount
  onMount(async () => {
    if (isGroup()) {
      const gid = groupId();
      if (gid) await getGroupHistory(gid);
    } else {
      const pid = peerId();
      if (pid) await getChatHistory(pid);
    }
  });

  // Auto-scroll to bottom on new messages
  createEffect(() => {
    const _ = messages().length;
    setTimeout(() => {
      messagesEndRef?.scrollIntoView({ behavior: "smooth" });
    }, 50);
  });

  const handleSend = async (e: Event) => {
    e.preventDefault();
    if (!inputText().trim()) return;

    if (isGroup()) {
      const gid = groupId();
      if (gid) {
        await sendGroupMessage(gid, inputText());
        setInputText("");
      }
    } else {
      const pid = peerId();
      if (pid) {
        await bridgeSendMessage(pid, inputText());
        setInputText("");
      }
    }
  };

  const isMe = (senderId: string) => senderId === "me";

  const deliveryIcon = (msg: Message) => {
    if (!isMe(msg.senderId)) return null;
    if (msg.delivered) {
      return <CheckCheck size={14} class="text-emerald-400" />;
    }
    return <Check size={14} class="text-primary-200" />;
  };

  const formatTime = (timestamp: number) => {
    // Timestamps from Rust are in seconds, JS uses milliseconds
    const ms = timestamp < 1e12 ? timestamp * 1000 : timestamp;
    return new Date(ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  const formatFileSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  };

  return (
    <div class="h-full flex flex-col relative w-full overflow-hidden bg-transparent">
      {/* Header */}
      <div class="h-16 flex items-center justify-between px-4 md:px-6 bg-primary-50 dark:bg-[#1a1513] border-b-2 border-stone-800 dark:border-stone-700 z-10 shrink-0">
        <button 
          class="flex items-center gap-3 hover:bg-stone-200 dark:hover:bg-stone-800 p-2 -ml-2 rounded-lg transition-colors cursor-pointer text-left focus:outline-none"
          onClick={() => setDetailsOpen(true)}
        >
          <div class="flex items-center justify-center text-stone-700 dark:text-stone-300">
            {isGroup() ? <Users size={22} /> : <div class={`w-3 h-3 rounded-full border border-stone-800 ${contact()?.online ? 'bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.8)]' : 'bg-stone-400'}`}></div>}
          </div>
          <div>
            <h2 class="font-black text-lg md:text-xl text-stone-900 dark:text-stone-100 leading-tight">
              {currentChat()?.name || "Unknown"}
            </h2>
            <p class="text-xs md:text-sm font-bold text-stone-500 dark:text-stone-400">
              {isGroup() ? `${currentChat()?.participants.length} peers` : (contact()?.online ? "Online — LAN" : "Offline")}
            </p>
          </div>
        </button>

        <div class={`flex items-center gap-3 ${props.pane === 'right' ? 'mr-10' : ''}`}>
          {props.pane === "left" && !activeRightPane() && (
            <button 
              class="flat-button-secondary py-1.5 px-3 text-xs md:text-sm flex items-center gap-2 mr-2"
              onClick={(e) => { e.stopPropagation(); setActiveRightPane({ type: isGroup() ? 'group' : 'dm', id: props.id }); }}
            >
              <Columns size={16} /> Split
            </button>
          )}
          <span class="text-xs font-black text-stone-400 dark:text-stone-500 uppercase tracking-wider hidden lg:inline">Route:</span>
          <div class="hidden lg:flex bg-stone-200 dark:bg-[#2c2421] rounded-md border-2 border-stone-800 dark:border-stone-700 p-0.5">
            {(["Auto", "LAN", "Internet"] as const).map(mode => (
              <button
                class={`px-3 py-1 text-sm font-bold rounded-md transition-all ${
                  forceNetwork() === mode
                    ? "bg-white dark:bg-[#4a3a33] text-primary-600 dark:text-primary-400 border border-stone-800 shadow-[1px_1px_0px_0px_rgba(41,37,36,1)] dark:shadow-none"
                    : "text-stone-600 dark:text-stone-400 border border-transparent hover:text-stone-900"
                }`}
                onClick={() => setForceNetwork(mode)}
              >
                {mode}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div class="flex-1 flex overflow-hidden w-full relative">
        {/* Main Chat Pane */}
        <div class="flex-1 flex flex-col min-w-0 h-full">
          {/* Messages */}
          <div class="flex-1 overflow-y-auto p-4 md:p-6 space-y-5 bg-[#fffdfa] dark:bg-[#241d1a]">
            <div class="flex items-center justify-center my-6">
              <div class="px-4 py-2 rounded-md bg-emerald-100 dark:bg-emerald-900/40 border-2 border-emerald-800 flex items-center gap-2 text-xs font-black text-emerald-900 dark:text-emerald-400 shadow-[2px_2px_0px_0px_rgba(6,78,59,0.5)]">
                <Shield size={14} />
                End-to-End Encrypted (LAN Direct)
              </div>
            </div>

            <For each={messages()}>
              {(message) => (
                <div class={`flex w-full ${isMe(message.senderId) ? "justify-end" : "justify-start"}`}>
                  <div class={`max-w-[85%] md:max-w-[70%] px-5 py-3 relative group font-bold ${
                    isMe(message.senderId)
                      ? "chamfer-tr-bl chamfer-shadow text-stone-100"
                      : "chamfer-tl-br chamfer-shadow text-stone-800 dark:text-stone-200"
                  }`} style={{ "--bg-color": isMe(message.senderId) ? "var(--color-primary-500)" : "" }}>
                    {!isMe(message.senderId) && isGroup() && (
                      <div class="text-xs font-black mb-1 text-accent-600 dark:text-accent-400">
                        {contacts.find(c => c.peerId === message.senderId)?.petname || message.senderId.slice(0, 12) + '…'}
                      </div>
                    )}

                    {/* File message */}
                    <Show when={message.fileInfo} fallback={
                      <div class="text-[15px] leading-relaxed break-words">{message.content}</div>
                    }>
                      {(fi) => (
                        <div class="flex items-center gap-3 min-w-[200px]">
                          <div class={`w-10 h-10 rounded-md flex items-center justify-center shrink-0 ${
                            isMe(message.senderId)
                              ? "bg-primary-400/30"
                              : "bg-stone-200 dark:bg-stone-700"
                          }`}>
                            <FileIcon size={20} />
                          </div>
                          <div class="flex-1 min-w-0">
                            <div class="text-sm font-black truncate">{fi().fileName}</div>
                            <div class={`text-[10px] font-bold flex items-center justify-between ${
                              isMe(message.senderId) ? "text-primary-200" : "text-stone-500"
                            }`}>
                              <div>
                                {formatFileSize(fi().fileSize)} · {fi().direction === "upload" ? "Sending" : "Receiving"}
                                {fi().status === "complete" && " · Complete ✓"}
                                {fi().status === "paused" && " · Paused"}
                              </div>
                              <Show when={fi().status === "transferring" || fi().status === "paused"}>
                                <div class="flex gap-2">
                                  <Show when={fi().status === "transferring"}>
                                    <button 
                                      onClick={() => pauseFileTransfer(fi().transferId)}
                                      class="hover:text-stone-800 dark:hover:text-stone-200 transition-colors"
                                      title="Pause Transfer"
                                    >
                                      ⏸️
                                    </button>
                                  </Show>
                                  <Show when={fi().status === "paused"}>
                                    <button 
                                      onClick={() => resumeFileTransfer(fi().transferId)}
                                      class="hover:text-stone-800 dark:hover:text-stone-200 transition-colors"
                                      title="Resume Transfer"
                                    >
                                      ▶️
                                    </button>
                                  </Show>
                                </div>
                              </Show>
                            </div>
                            {/* Progress bar */}
                            <Show when={fi().status === "transferring" || fi().status === "paused"}>
                              <div class={`w-full h-1.5 rounded-full mt-1.5 overflow-hidden ${
                                isMe(message.senderId) ? "bg-primary-400/30" : "bg-stone-300 dark:bg-stone-600"
                              }`}>
                                <div
                                  class={`h-full rounded-full transition-all duration-300 ${fi().status === "paused" ? "bg-amber-400" : "bg-emerald-400"}`}
                                  style={{ width: `${Math.round(fi().progress * 100)}%` }}
                                />
                              </div>
                            </Show>
                          </div>
                        </div>
                      )}
                    </Show>

                    <div class={`text-xs mt-1.5 font-bold flex items-center justify-end gap-1.5 ${isMe(message.senderId) ? "text-primary-100" : "text-stone-400 dark:text-stone-500"}`}>
                      {formatTime(message.timestamp)}
                      {deliveryIcon(message)}
                    </div>
                  </div>
                </div>
              )}
            </For>
            <div ref={messagesEndRef} />
          </div>

          {/* Input */}
          <div class="p-3 md:p-4 bg-primary-50 dark:bg-[#1f1917] border-t-2 border-stone-800 dark:border-stone-700 shrink-0">
            <form onSubmit={handleSend} class="flex items-center gap-2 md:gap-3 flat-panel-all p-1.5 pl-3 w-full" style="--chamfer-outer: 8px; --chamfer-inner: 6px;">
              <button
                type="button"
                class="p-1 md:p-2 text-stone-500 hover:text-stone-800 dark:hover:text-stone-200 transition-colors"
                onClick={() => {
                  if (isGroup()) {
                    const gid = groupId();
                    if (gid) sendGroupFile(gid);
                  } else {
                    const pid = peerId();
                    if (pid) sendFile(pid);
                  }
                }}
              >
                <Paperclip size={20} />
              </button>
              <input
                type="text"
                class="flex-1 bg-transparent border-none focus:outline-none focus:ring-0 text-sm md:text-base font-bold px-1 md:px-2 text-stone-800 dark:text-stone-100 placeholder-stone-400 w-full"
                placeholder="Write a message..."
                value={inputText()}
                onInput={(e) => setInputText(e.currentTarget.value)}
              />
              <button
                type="submit"
                disabled={!inputText().trim()}
                class="p-2 md:p-3 chamfer-all chamfer-shadow chamfer-active flex items-center justify-center text-white disabled:opacity-50 disabled:cursor-not-allowed" 
                style="--bg-color: var(--color-primary-500); --chamfer-outer: 8px; --chamfer-inner: 6px; --shadow-x: 2px; --shadow-y: 2px;"
              >
                <Send size={18} />
              </button>
            </form>
          </div>
        </div>

        {/* Profile Details Drawer */}
        {detailsOpen() && (
          <div class="w-full md:w-72 lg:w-80 border-l-2 border-stone-800 dark:border-stone-700 bg-primary-50 dark:bg-[#1a1513] shrink-0 absolute md:static inset-0 z-20 flex flex-col h-full animate-in slide-in-from-right-4 duration-200">
            <div class="h-16 flex items-center justify-between px-4 border-b-2 border-stone-800 dark:border-stone-700 bg-white dark:bg-[#2c2421]">
              <h3 class="font-black text-stone-800 dark:text-stone-100">Details</h3>
              <button onClick={() => setDetailsOpen(false)} class="p-2 text-stone-500 hover:text-stone-800 dark:hover:text-stone-100 hover:bg-stone-200 dark:hover:bg-stone-800 rounded-lg transition-colors">
                <X size={20} />
              </button>
            </div>
            <div class="p-6 flex flex-col items-center gap-4 border-b-2 border-stone-800 dark:border-stone-700 bg-primary-50 dark:bg-[#1a1513]">
              <div class="w-20 h-20 rounded-full border-4 border-stone-800 dark:border-stone-600 bg-stone-200 dark:bg-stone-800 flex items-center justify-center text-stone-500 shadow-[4px_4px_0px_0px_rgba(41,37,36,1)] dark:shadow-none">
                {isGroup() ? <Users size={40} /> : <div class="text-4xl font-black">{currentChat()?.name.charAt(0)}</div>}
              </div>
              <h2 class="text-2xl font-black text-stone-900 dark:text-stone-100 text-center">{currentChat()?.name}</h2>
              {!isGroup() && (
                <div class="flex items-center gap-2 text-stone-500 dark:text-stone-400 font-bold text-sm">
                  <MapPin size={16} /> {contact()?.online ? "Online — LAN Direct" : "Offline"}
                </div>
              )}
            </div>
            <div class="p-4 flex-1 overflow-y-auto">
              <Show when={!isGroup()} fallback={
                /* Group Details */
                <>
                  <div class="flat-panel p-4 mb-4 flex flex-col gap-3">
                    <div class="font-black text-xs uppercase text-stone-500 tracking-wider">Group ID</div>
                    <div class="font-mono text-xs text-stone-600 dark:text-stone-400 break-all">{groupId()}</div>
                  </div>
                  <div class="flat-panel p-4 mb-4 flex flex-col gap-3">
                    <div class="font-black text-xs uppercase text-stone-500 tracking-wider mb-2">
                      Members ({currentChat()?.participants.length})
                    </div>
                    <For each={currentChat()?.participants || []}>
                      {(memberId) => {
                        const memberContact = () => contacts.find(c => c.peerId === memberId);
                        const isSelf = () => memberId === identity()?.peerId;
                        return (
                          <div class="flex items-center gap-3 py-2 px-1 rounded-lg">
                            <div class={`w-2.5 h-2.5 rounded-full border border-stone-800 shrink-0 ${
                              isSelf() ? 'bg-primary-500' : memberContact()?.online ? 'bg-emerald-500' : 'bg-stone-400'
                            }`}></div>
                            <div class="flex-1 min-w-0">
                              <div class="text-sm font-bold truncate text-stone-800 dark:text-stone-200">
                                {isSelf() ? 'You' : memberContact()?.petname || memberId.slice(0, 12) + '…'}
                              </div>
                            </div>
                            <Show when={isAdmin() && !isSelf()}>
                              <button
                                class="p-1.5 text-stone-400 hover:text-red-500 hover:bg-red-100 dark:hover:bg-red-900/30 rounded-md transition-colors"
                                title="Remove from group"
                                onClick={() => { const gid = groupId(); if(gid) removeGroupMember(gid, memberId); }}
                              >
                                <UserMinus size={14} />
                              </button>
                            </Show>
                          </div>
                        );
                      }}
                    </For>
                  </div>
                  {/* Group Actions */}
                  <div class="space-y-2 mt-4">
                    <button
                      class="w-full flex items-center gap-3 px-4 py-3 rounded-xl font-bold text-sm text-amber-700 dark:text-amber-400 hover:bg-amber-100 dark:hover:bg-amber-900/30 transition-colors"
                      onClick={() => { const gid = groupId(); if(gid) leaveGroup(gid); }}
                    >
                      <LogOut size={16} />
                      Leave Group
                    </button>
                    <Show when={isAdmin()}>
                      <button
                        class="w-full flex items-center gap-3 px-4 py-3 rounded-xl font-bold text-sm text-red-700 dark:text-red-400 hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors"
                        onClick={() => { const gid = groupId(); if(gid) disbandGroup(gid); }}
                      >
                        <Trash2 size={16} />
                        Disband Group
                      </button>
                    </Show>
                  </div>
                </>
              }>
                {/* DM Details */}
                <div class="flat-panel p-4 mb-4 flex flex-col gap-3">
                   <div class="font-black text-xs uppercase text-stone-500 tracking-wider">Peer ID</div>
                   <div class="font-mono text-xs text-stone-600 dark:text-stone-400 break-all">{peerId()}</div>
                </div>
                {contact() && (
                  <div class="flat-panel p-4 mb-4 flex flex-col gap-3">
                    <div class="font-black text-xs uppercase text-stone-500 tracking-wider">Contact Since</div>
                    <div class="font-bold text-stone-800 dark:text-stone-200">
                      {new Date((contact()?.addedAt || 0) * 1000).toLocaleDateString()}
                    </div>
                  </div>
                )}
                <div class="flat-panel p-4 flex flex-col gap-3">
                   <div class="font-black text-xs uppercase text-stone-500 tracking-wider">Trust Level</div>
                   <div class="font-bold text-stone-800 dark:text-stone-200">{contact()?.trustLevel || "Direct"}</div>
                </div>
              </Show>
            </div>
          </div>
        )}

      </div>
    </div>
  );
};
