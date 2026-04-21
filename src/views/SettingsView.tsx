import { Component, createSignal, For, Show } from "solid-js";
import { identity, lanVisible, contacts, toggleTheme, theme } from "../store";
import {
  QrCode, ShieldCheck, Contact2, PenLine, DownloadCloud,
  ChevronLeft, Moon, Sun, Eye, EyeOff, Copy, Check, Save, Trash2,
  Edit, Globe, Plus, RefreshCw, Link, X, Wifi
} from "lucide-solid";
import { A } from "@solidjs/router";
import {
  exportKeypair, toggleVisibility, setUsername, removeContact, renameContact,
  getRelayConfig, setRelayConfig, getMyConnectionCode, addContactFromCode,
  RelayConfig,
} from "../tauri-bridge";

export const SettingsView: Component = () => {
  // ── Identity panel ──────────────────────────────────────────────────────────
  const [copied, setCopied] = createSignal(false);
  const [codeCopied, setCodeCopied] = createSignal(false);
  const [exportedKey, setExportedKey] = createSignal<string | null>(null);
  const [editingName, setEditingName] = createSignal(false);
  const [nameInput, setNameInput] = createSignal("");
  const [editingContact, setEditingContact] = createSignal<string | null>(null);
  const [contactNameInput, setContactNameInput] = createSignal("");

  // ── Internet / Relay panel ───────────────────────────────────────────────────
  const [relayConfig, setRelayConfigLocal] = createSignal<RelayConfig>({ relays: [] });
  const [relayLoading, setRelayLoading] = createSignal(false);
  const [relaySaved, setRelaySaved] = createSignal(false);
  const [newRelayLabel, setNewRelayLabel] = createSignal("");
  const [newRelayAddress, setNewRelayAddress] = createSignal("");
  const [showAddRelay, setShowAddRelay] = createSignal(false);

  // ── Connection Code panel ────────────────────────────────────────────────────
  const [myCode, setMyCode] = createSignal<{ code: string; qr_svg_b64: string } | null>(null);
  const [codeLoading, setCodeLoading] = createSignal(false);
  const [showQR, setShowQR] = createSignal(false);
  const [addCodeInput, setAddCodeInput] = createSignal("");
  const [addPetname, setAddPetname] = createSignal("");
  const [addCodeError, setAddCodeError] = createSignal<string | null>(null);
  const [addCodeSuccess, setAddCodeSuccess] = createSignal(false);

  // Load relay config on mount
  (async () => {
    try {
      const cfg = await getRelayConfig();
      setRelayConfigLocal(cfg);
    } catch (e) {
      console.error("Failed to load relay config:", e);
    }
  })();

  // ── Identity handlers ────────────────────────────────────────────────────────
  const handleExport = async () => {
    try { setExportedKey(await exportKeypair()); } catch (e) { console.error(e); }
  };

  const handleCopyPubKey = () => {
    const pk = identity()?.publicKey;
    if (pk) { navigator.clipboard.writeText(pk); setCopied(true); setTimeout(() => setCopied(false), 2000); }
  };

  const handleToggleVisibility = async () => {
    try { await toggleVisibility(!lanVisible()); } catch (e) { console.error(e); }
  };

  const startEditName = () => { setNameInput(identity()?.name || ""); setEditingName(true); };
  const saveName = async () => {
    const name = nameInput().trim();
    if (name) { try { await setUsername(name); setEditingName(false); } catch (e) { console.error(e); } }
  };

  const handleRemoveContact = async (peerId: string) => {
    try { await removeContact(peerId); } catch (e) { console.error(e); }
  };

  const startEditContact = (peerId: string, currentName: string) => {
    setEditingContact(peerId); setContactNameInput(currentName);
  };

  const saveContactName = async (peerId: string) => {
    const name = contactNameInput().trim();
    if (name) { try { await renameContact(peerId, name); setEditingContact(null); } catch (e) { console.error(e); } }
  };

  // ── Relay handlers ───────────────────────────────────────────────────────────
  const saveRelayConfig = async () => {
    setRelayLoading(true);
    try {
      await setRelayConfig(relayConfig());
      setRelaySaved(true);
      setTimeout(() => setRelaySaved(false), 2500);
    } catch (e) { console.error("Failed to save relay config:", e); }
    finally { setRelayLoading(false); }
  };

  const addRelay = () => {
    const label = newRelayLabel().trim();
    const address = newRelayAddress().trim();
    if (!label || !address) return;
    setRelayConfigLocal(prev => ({
      relays: [...prev.relays, { label, address, enabled: true }]
    }));
    setNewRelayLabel(""); setNewRelayAddress(""); setShowAddRelay(false);
  };

  const removeRelay = (idx: number) => {
    setRelayConfigLocal(prev => ({ relays: prev.relays.filter((_, i) => i !== idx) }));
  };

  const toggleRelay = (idx: number) => {
    setRelayConfigLocal(prev => ({
      relays: prev.relays.map((r, i) => i === idx ? { ...r, enabled: !r.enabled } : r)
    }));
  };

  // ── Connection code handlers ─────────────────────────────────────────────────
  const loadMyCode = async () => {
    setCodeLoading(true);
    try {
      const result = await getMyConnectionCode();
      setMyCode(result);
    } catch (e) {
      console.error("Failed to get connection code:", e);
    } finally {
      setCodeLoading(false);
    }
  };

  const copyCode = () => {
    const c = myCode()?.code;
    if (c) { navigator.clipboard.writeText(c); setCodeCopied(true); setTimeout(() => setCodeCopied(false), 2000); }
  };

  const handleAddByCode = async () => {
    const code = addCodeInput().trim();
    const petname = addPetname().trim();
    if (!code || !petname) { setAddCodeError("Both code and petname are required."); return; }
    setAddCodeError(null);
    try {
      await addContactFromCode(code, petname);
      setAddCodeSuccess(true);
      setAddCodeInput(""); setAddPetname("");
      setTimeout(() => setAddCodeSuccess(false), 2500);
    } catch (e: any) {
      setAddCodeError(e?.toString() || "Failed to add contact.");
    }
  };

  return (
    <div class="h-full flex flex-col bg-[#fffdfa] dark:bg-[#241d1a] overflow-y-auto">
      {/* Header */}
      <div class="h-16 flex items-center justify-between px-4 md:px-8 border-b-2 border-stone-800 dark:border-stone-700 bg-primary-50 dark:bg-[#1a1513] shrink-0">
        <div class="flex items-center gap-4">
          <A href="/workspace" class="p-2 text-stone-600 dark:text-stone-400 hover:text-stone-900 border-2 border-transparent hover:border-stone-800 rounded-lg hover:bg-stone-200 dark:hover:bg-stone-700 transition-colors">
            <ChevronLeft size={24} />
          </A>
          <h2 class="font-black text-xl md:text-2xl text-stone-900 dark:text-stone-100">Settings</h2>
        </div>
        <button onClick={toggleTheme} class="flat-button-secondary p-2 flex items-center justify-center">
          {theme() === "dark" ? <Sun size={20} /> : <Moon size={20} />}
        </button>
      </div>

      <div class="p-6 md:p-8 max-w-5xl mx-auto w-full grid grid-cols-1 lg:grid-cols-2 gap-6">

        {/* ── Core Identity ──────────────────────────────────────────────────── */}
        <div class="flat-panel p-6 flex flex-col gap-6">
          <div class="flex items-center gap-3 mb-1">
            <Contact2 size={20} class="text-primary-500" />
            <h3 class="text-lg font-black text-stone-900 dark:text-stone-100">Identity</h3>
          </div>

          <div class="flex items-center gap-4 border-b-2 border-stone-200 dark:border-stone-700 pb-6">
            <div class="w-14 h-14 rounded-md bg-amber-200 border-2 border-stone-800 flex items-center justify-center text-stone-900 shadow-[3px_3px_0px_0px_rgba(41,37,36,1)]">
              <Contact2 size={28} />
            </div>
            <div class="flex-1 min-w-0">
              <Show when={!editingName()} fallback={
                <div class="flex items-center gap-2">
                  <input type="text" class="flex-1 bg-stone-100 dark:bg-stone-800 border-2 border-stone-400 dark:border-stone-600 rounded-md px-3 py-1.5 font-black text-lg text-stone-900 dark:text-stone-100 focus:outline-none focus:border-primary-500"
                    value={nameInput()} onInput={(e) => setNameInput(e.currentTarget.value)}
                    onKeyDown={(e) => e.key === "Enter" && saveName()} autofocus />
                  <button onClick={saveName} class="p-2 text-emerald-500 hover:text-emerald-700"><Save size={18} /></button>
                </div>
              }>
                <div class="flex items-center gap-2">
                  <h3 class="text-xl font-black text-stone-900 dark:text-stone-100 truncate">{identity()?.name || "Local User"}</h3>
                  <button onClick={startEditName} class="p-1 text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 transition-colors shrink-0"><PenLine size={14} /></button>
                </div>
              </Show>
              <p class="text-sm font-bold text-stone-500">Ed25519 Identity</p>
              <p class="text-[10px] font-mono text-stone-400 mt-0.5 truncate">{identity()?.peerId || "No peer ID"}</p>
            </div>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <h4 class="text-xs font-black uppercase text-stone-500">Public Key</h4>
              <button onClick={handleCopyPubKey} class="text-xs font-bold text-stone-500 hover:text-stone-800 dark:hover:text-stone-200 flex items-center gap-1 transition-colors">
                {copied() ? <><Check size={12} /> Copied!</> : <><Copy size={12} /> Copy</>}
              </button>
            </div>
            <div class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 p-3 rounded-md break-all font-mono text-xs text-stone-700 dark:text-stone-300">
              {identity()?.publicKey || "No identity generated"}
            </div>
          </div>

          <button onClick={handleExport} class="flat-button py-2.5 px-4 flex items-center justify-center gap-2 w-full">
            <DownloadCloud size={18} /> Export Keypair
          </button>

          {exportedKey() && (
            <div class="bg-emerald-50 dark:bg-emerald-900/20 border-2 border-emerald-800 rounded-md p-3">
              <h4 class="text-xs font-black uppercase text-emerald-800 dark:text-emerald-400 mb-2">Exported Key (Base64)</h4>
              <div class="font-mono text-[10px] text-emerald-700 dark:text-emerald-300 break-all select-all">{exportedKey()}</div>
            </div>
          )}
        </div>

        {/* ── Network & Discovery ────────────────────────────────────────────── */}
        <div class="flat-panel p-6 flex flex-col gap-5">
          <div class="flex items-center gap-3 mb-1">
            <Wifi size={20} class="text-primary-500" />
            <h3 class="text-lg font-black text-stone-900 dark:text-stone-100">LAN Discovery</h3>
          </div>

          <div class="flex items-center justify-between p-4 bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 rounded-lg">
            <div class="flex items-center gap-3">
              {lanVisible() ? <Eye size={20} class="text-emerald-500" /> : <EyeOff size={20} class="text-stone-400" />}
              <div>
                <div class="font-black text-stone-900 dark:text-stone-100 text-sm">LAN Visibility</div>
                <div class="text-xs font-bold text-stone-500">{lanVisible() ? "Discoverable on local network" : "Hidden from local network"}</div>
              </div>
            </div>
            <button
              onClick={handleToggleVisibility}
              class={`w-12 h-7 rounded-full border-2 border-stone-800 transition-colors relative ${lanVisible() ? 'bg-emerald-400' : 'bg-stone-300 dark:bg-stone-600'}`}
            >
              <div class={`w-5 h-5 rounded-full bg-white border-2 border-stone-800 absolute top-0.5 transition-transform ${lanVisible() ? 'translate-x-5' : 'translate-x-0.5'}`} />
            </button>
          </div>

          <p class="text-stone-500 dark:text-stone-400 text-xs font-medium leading-relaxed">
            When visible, Stoa broadcasts your presence on the local network via mDNS so nearby devices can discover you without any server. Turning this off keeps your connections but stops new LAN discovery.
          </p>
        </div>

        {/* ── Internet / Relay Servers ───────────────────────────────────────── */}
        <div class="flat-panel p-6 flex flex-col gap-5 lg:col-span-2">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <Globe size={20} class="text-primary-500" />
              <h3 class="text-lg font-black text-stone-900 dark:text-stone-100">Internet Relay Servers</h3>
            </div>
            <div class="flex items-center gap-2">
              <button
                onClick={() => setShowAddRelay(v => !v)}
                class="flat-button-secondary px-3 py-1.5 text-xs flex items-center gap-1.5 font-black"
              >
                <Plus size={14} /> Add Relay
              </button>
              <button
                onClick={saveRelayConfig}
                disabled={relayLoading()}
                class="flat-button px-3 py-1.5 text-xs flex items-center gap-1.5 font-black"
              >
                {relaySaved() ? <><Check size={14} /> Saved!</> : relayLoading() ? <><RefreshCw size={14} class="animate-spin" /> Saving...</> : <><Save size={14} /> Save</>}
              </button>
            </div>
          </div>

          <p class="text-stone-500 dark:text-stone-400 text-xs font-medium leading-relaxed">
            Relay servers allow Stoa to connect peers across different networks (mobile data, different Wi-Fi, etc.). The relay only sees encrypted traffic — it cannot read your messages.
          </p>

          {/* Add relay form */}
          <Show when={showAddRelay()}>
            <div class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 rounded-lg p-4 flex flex-col gap-3">
              <h4 class="text-xs font-black uppercase text-stone-500">Add Relay Server</h4>
              <input
                type="text"
                placeholder="Label (e.g. My Home Relay)"
                class="bg-white dark:bg-stone-900 border-2 border-stone-300 dark:border-stone-600 rounded-md px-3 py-2 text-sm font-medium text-stone-900 dark:text-stone-100 focus:outline-none focus:border-primary-500"
                value={newRelayLabel()}
                onInput={(e) => setNewRelayLabel(e.currentTarget.value)}
              />
              <input
                type="text"
                placeholder="/ip4/1.2.3.4/tcp/4001/p2p/12D3KooW..."
                class="bg-white dark:bg-stone-900 border-2 border-stone-300 dark:border-stone-600 rounded-md px-3 py-2 text-xs font-mono text-stone-900 dark:text-stone-100 focus:outline-none focus:border-primary-500"
                value={newRelayAddress()}
                onInput={(e) => setNewRelayAddress(e.currentTarget.value)}
              />
              <div class="flex gap-2">
                <button onClick={addRelay} class="flat-button py-2 px-4 text-sm flex-1">Add</button>
                <button onClick={() => setShowAddRelay(false)} class="flat-button-secondary py-2 px-4 text-sm">Cancel</button>
              </div>
            </div>
          </Show>

          {/* Relay list */}
          <div class="flex flex-col gap-2">
            <Show when={relayConfig().relays.length > 0} fallback={
              <div class="text-center py-6 text-stone-400 text-sm font-medium">
                No relay servers configured. Add one above or see the deployment guide.
              </div>
            }>
              <For each={relayConfig().relays}>
                {(relay, idx) => (
                  <div class={`flex items-center gap-3 p-3 rounded-lg border-2 transition-colors ${relay.enabled ? 'bg-white dark:bg-stone-900 border-stone-300 dark:border-stone-700' : 'bg-stone-50 dark:bg-stone-800/50 border-stone-200 dark:border-stone-800 opacity-60'}`}>
                    {/* Enable toggle */}
                    <button
                      onClick={() => toggleRelay(idx())}
                      class={`w-9 h-5 rounded-full border-2 border-stone-700 transition-colors relative shrink-0 ${relay.enabled ? 'bg-emerald-400' : 'bg-stone-300 dark:bg-stone-600'}`}
                    >
                      <div class={`w-3.5 h-3.5 rounded-full bg-white border-2 border-stone-700 absolute top-[1px] transition-transform ${relay.enabled ? 'translate-x-4' : 'translate-x-[1px]'}`} />
                    </button>
                    <div class="flex-1 min-w-0">
                      <div class="font-black text-sm text-stone-900 dark:text-stone-100">{relay.label}</div>
                      <div class="font-mono text-[10px] text-stone-500 truncate">{relay.address}</div>
                    </div>
                    <button onClick={() => removeRelay(idx())} class="p-1.5 text-stone-400 hover:text-red-500 transition-colors shrink-0">
                      <X size={14} />
                    </button>
                  </div>
                )}
              </For>
            </Show>
          </div>
        </div>

        {/* ── Connection Code / QR ───────────────────────────────────────────── */}
        <div class="flat-panel p-6 flex flex-col gap-5 lg:col-span-2">
          <div class="flex items-center gap-3">
            <Link size={20} class="text-primary-500" />
            <h3 class="text-lg font-black text-stone-900 dark:text-stone-100">Connection Code</h3>
          </div>
          <p class="text-stone-500 dark:text-stone-400 text-xs font-medium leading-relaxed">
            Share your connection code with people you want to connect with over the internet. They paste it in their Stoa to find and contact you — no accounts, no servers, no phone numbers.
          </p>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* My code panel */}
            <div class="flex flex-col gap-3">
              <h4 class="text-xs font-black uppercase text-stone-500">My Code</h4>
              <Show when={myCode()} fallback={
                <button
                  onClick={loadMyCode}
                  disabled={codeLoading()}
                  class="flat-button py-3 flex items-center justify-center gap-2"
                >
                  {codeLoading() ? <><RefreshCw size={16} class="animate-spin" /> Generating...</> : <><QrCode size={16} /> Generate My Code</>}
                </button>
              }>
                <div class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 rounded-lg p-3 flex flex-col gap-3">
                  <div class="font-mono text-[11px] text-stone-700 dark:text-stone-300 break-all select-all leading-relaxed">
                    {myCode()!.code}
                  </div>
                  <div class="flex gap-2">
                    <button onClick={copyCode} class="flat-button-secondary px-3 py-1.5 text-xs flex items-center gap-1.5 font-black flex-1">
                      {codeCopied() ? <><Check size={12} /> Copied!</> : <><Copy size={12} /> Copy Code</>}
                    </button>
                    <button onClick={() => setShowQR(v => !v)} class="flat-button-secondary px-3 py-1.5 text-xs flex items-center gap-1.5 font-black">
                      <QrCode size={12} /> {showQR() ? "Hide" : "QR"}
                    </button>
                  </div>

                  {/* QR Code display */}
                  <Show when={showQR()}>
                    <div class="flex justify-center p-2 bg-white rounded-lg border-2 border-stone-300">
                      <div
                        class="w-48 max-w-full aspect-square [&>svg]:w-full [&>svg]:h-full"
                        innerHTML={atob(myCode()!.qr_svg_b64)}
                      />
                    </div>
                    <p class="text-[10px] text-stone-400 text-center font-medium">Scan with Stoa on another device</p>
                  </Show>
                </div>
              </Show>
            </div>

            {/* Add contact by code panel */}
            <div class="flex flex-col gap-3">
              <h4 class="text-xs font-black uppercase text-stone-500">Add Contact by Code</h4>
              <Show when={!addCodeSuccess()} fallback={
                <div class="flex items-center gap-2 text-emerald-600 dark:text-emerald-400 font-black text-sm p-3 bg-emerald-50 dark:bg-emerald-900/20 border-2 border-emerald-700 rounded-lg">
                  <Check size={18} /> Contact added! Connection request sent.
                </div>
              }>
                <div class="flex flex-col gap-3">
                  <textarea
                    placeholder="Paste their stoa1... code here"
                    class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 rounded-lg p-3 font-mono text-[11px] text-stone-700 dark:text-stone-300 resize-none h-20 focus:outline-none focus:border-primary-500"
                    value={addCodeInput()}
                    onInput={(e) => setAddCodeInput(e.currentTarget.value)}
                  />
                  <input
                    type="text"
                    placeholder="Give them a name (petname)"
                    class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 rounded-lg px-3 py-2 text-sm font-medium text-stone-900 dark:text-stone-100 focus:outline-none focus:border-primary-500"
                    value={addPetname()}
                    onInput={(e) => setAddPetname(e.currentTarget.value)}
                    onKeyDown={(e) => e.key === "Enter" && handleAddByCode()}
                  />
                  {addCodeError() && (
                    <p class="text-[11px] text-red-500 font-bold">{addCodeError()}</p>
                  )}
                  <button onClick={handleAddByCode} class="flat-button py-2.5 flex items-center justify-center gap-2">
                    <Plus size={16} /> Add Contact
                  </button>
                </div>
              </Show>
            </div>
          </div>
        </div>

        {/* ── Contacts Table ─────────────────────────────────────────────────── */}
        <div class="flat-panel p-6 lg:col-span-2">
          <div class="flex items-center gap-3 mb-4">
            <ShieldCheck size={24} class="text-emerald-500" />
            <h3 class="text-xl font-black text-stone-900 dark:text-stone-100">Web of Trust & Contacts</h3>
          </div>
          <p class="text-stone-600 dark:text-stone-400 font-medium text-sm leading-relaxed mb-6 max-w-3xl">
            Assign human-readable petnames to public keys locally. Trust is explicit — there's no global registry.
          </p>

          <div class="overflow-x-auto border-2 border-stone-800 rounded-md">
            <table class="w-full text-left border-collapse">
              <thead>
                <tr class="bg-primary-100 dark:bg-stone-800 text-stone-800 dark:text-stone-200 border-b-2 border-stone-800">
                  <th class="p-3 font-black uppercase text-xs">Petname</th>
                  <th class="p-3 font-black uppercase text-xs">Peer ID</th>
                  <th class="p-3 font-black uppercase text-xs">Trust</th>
                  <th class="p-3 font-black uppercase text-xs">Status</th>
                  <th class="p-3 font-black uppercase text-xs text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y-2 divide-stone-200 dark:divide-stone-700 font-medium">
                <Show when={contacts.length > 0} fallback={
                  <tr class="bg-white dark:bg-[#2c2421]">
                    <td class="p-3 font-bold text-stone-500 italic" colspan="5">No contacts yet — share your connection code to add someone.</td>
                  </tr>
                }>
                  <For each={contacts}>
                    {(contact) => (
                      <tr class="bg-white dark:bg-[#2c2421] hover:bg-stone-50 dark:hover:bg-stone-800/50 transition-colors">
                        <td class="p-3 font-bold text-stone-900 dark:text-stone-100">
                          <Show when={editingContact() === contact.peerId} fallback={contact.petname}>
                            <div class="flex items-center gap-2">
                              <input type="text" class="bg-stone-100 dark:bg-stone-700 border border-stone-400 rounded px-2 py-1 text-sm font-bold w-32 focus:outline-none"
                                value={contactNameInput()} onInput={(e) => setContactNameInput(e.currentTarget.value)}
                                onKeyDown={(e) => e.key === "Enter" && saveContactName(contact.peerId)} autofocus />
                              <button onClick={() => saveContactName(contact.peerId)} class="text-emerald-500 hover:text-emerald-700"><Save size={14} /></button>
                            </div>
                          </Show>
                        </td>
                        <td class="p-3 font-mono text-xs text-stone-500 truncate max-w-[120px]">{contact.peerId.slice(0, 12)}…</td>
                        <td class="p-3">
                          <span class={`text-xs font-black uppercase px-2 py-1 rounded border-2 ${contact.trustLevel === "Direct"
                            ? "bg-emerald-100 dark:bg-emerald-900/30 border-emerald-700 text-emerald-800 dark:text-emerald-400"
                            : "bg-blue-100 dark:bg-blue-900/30 border-blue-700 text-blue-800 dark:text-blue-400"
                          }`}>{contact.trustLevel}</span>
                        </td>
                        <td class="p-3">
                          <div class="flex items-center gap-2">
                            <div class={`w-2.5 h-2.5 rounded-full border border-stone-800 ${contact.online ? 'bg-emerald-500' : 'bg-stone-400'}`} />
                            <span class="text-xs font-bold text-stone-500">{contact.online ? "Online" : "Offline"}</span>
                          </div>
                        </td>
                        <td class="p-3 text-right">
                          <div class="flex items-center justify-end gap-2">
                            <button onClick={() => startEditContact(contact.peerId, contact.petname)}
                              class="p-1.5 text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 transition-colors" title="Rename">
                              <Edit size={14} />
                            </button>
                            <button onClick={() => handleRemoveContact(contact.peerId)}
                              class="p-1.5 text-stone-400 hover:text-red-500 transition-colors" title="Remove">
                              <Trash2 size={14} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    )}
                  </For>
                </Show>
              </tbody>
            </table>
          </div>
        </div>

      </div>
    </div>
  );
};
