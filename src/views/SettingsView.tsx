import { Component, createSignal } from "solid-js";
import { identity, lanVisible } from "../store";
import { QrCode, ShieldCheck, Contact2, PenLine, Smartphone, DownloadCloud, ChevronLeft, Moon, Sun, Eye, EyeOff, Copy, Check } from "lucide-solid";
import { A } from "@solidjs/router";
import { toggleTheme, theme } from "../store";
import { exportKeypair, toggleVisibility } from "../tauri-bridge";

export const SettingsView: Component = () => {
  const [copied, setCopied] = createSignal(false);
  const [exportedKey, setExportedKey] = createSignal<string | null>(null);

  const handleExport = async () => {
    try {
      const key = await exportKeypair();
      setExportedKey(key);
    } catch (e) {
      console.error("Export failed:", e);
    }
  };

  const handleCopyPubKey = () => {
    const pk = identity()?.publicKey;
    if (pk) {
      navigator.clipboard.writeText(pk);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const handleToggleVisibility = async () => {
    try {
      await toggleVisibility(!lanVisible());
    } catch (e) {
      console.error("Toggle visibility failed:", e);
    }
  };

  return (
    <div class="h-full flex flex-col bg-[#fffdfa] dark:bg-[#241d1a] overflow-y-auto">
      <div class="h-16 flex items-center justify-between px-4 md:px-8 border-b-2 border-stone-800 dark:border-stone-700 bg-primary-50 dark:bg-[#1a1513] shrink-0">
        <div class="flex items-center gap-4">
          <A href="/workspace" class="p-2 text-stone-600 dark:text-stone-400 hover:text-stone-900 border-2 border-transparent hover:border-stone-800 rounded-lg hover:bg-stone-200 transition-colors">
            <ChevronLeft size={24} />
          </A>
          <h2 class="font-black text-xl md:text-2xl text-stone-900 dark:text-stone-100">Identity & Trust Settings</h2>
        </div>
        <button onClick={toggleTheme} class="flat-button-secondary p-2 flex items-center justify-center">
           {theme() === "dark" ? <Sun size={20} /> : <Moon size={20} />}
        </button>
      </div>

      <div class="p-8 max-w-5xl mx-auto w-full grid grid-cols-1 lg:grid-cols-2 gap-8">
        
        {/* Core Identity Panel */}
        <div class="flat-panel p-6 flex flex-col gap-6">
          <div class="flex items-center gap-4 border-b-2 border-stone-200 dark:border-stone-700 pb-6">
            <div class="w-16 h-16 rounded-md bg-amber-200 border-2 border-stone-800 flex items-center justify-center text-stone-900 shadow-[3px_3px_0px_0px_rgba(41,37,36,1)]">
              <Contact2 size={32} />
            </div>
            <div>
              <h3 class="text-xl font-black text-stone-900 dark:text-stone-100">{identity()?.name || "Local User"}</h3>
              <p class="text-sm font-bold text-stone-500">Local Ed25519 Identity</p>
              <p class="text-[10px] font-mono text-stone-400 mt-1 truncate max-w-[200px]">
                {identity()?.peerId || "No peer ID"}
              </p>
            </div>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <h4 class="text-sm font-black uppercase text-stone-500">Public Key</h4>
              <button onClick={handleCopyPubKey} class="text-xs font-bold text-stone-500 hover:text-stone-800 dark:hover:text-stone-200 flex items-center gap-1 transition-colors">
                {copied() ? <><Check size={12} /> Copied!</> : <><Copy size={12} /> Copy</>}
              </button>
            </div>
            <div class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 p-3 rounded-md break-all font-mono text-xs text-stone-700 dark:text-stone-300">
              {identity()?.publicKey || "No identity generated"}
            </div>
          </div>

          <div class="flex gap-4">
            <button onClick={handleExport} class="flat-button py-2.5 px-4 flex-1 flex items-center justify-center gap-2">
              <DownloadCloud size={18} /> Export Keypair
            </button>
            <button class="flat-button-secondary py-2.5 px-4 flex items-center justify-center gap-2">
              <QrCode size={18} /> Show QR
            </button>
          </div>

          {exportedKey() && (
            <div class="bg-emerald-50 dark:bg-emerald-900/20 border-2 border-emerald-800 rounded-md p-3">
              <h4 class="text-xs font-black uppercase text-emerald-800 dark:text-emerald-400 mb-2">Exported Key (Base64)</h4>
              <div class="font-mono text-[10px] text-emerald-700 dark:text-emerald-300 break-all select-all">
                {exportedKey()}
              </div>
            </div>
          )}
        </div>

        {/* LAN Visibility + Cross-Platform */}
        <div class="flat-panel p-6 flex flex-col gap-5">
          <div class="flex items-center gap-3 text-primary-600 dark:text-primary-400 mb-2">
            <Smartphone size={24} />
            <h3 class="text-xl font-black text-stone-900 dark:text-stone-100">Network & Discovery</h3>
          </div>

          {/* Visibility Toggle */}
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
              <div class={`w-5 h-5 rounded-full bg-white border-2 border-stone-800 absolute top-0.5 transition-transform ${lanVisible() ? 'translate-x-5' : 'translate-x-0.5'}`}></div>
            </button>
          </div>

          <p class="text-stone-600 dark:text-stone-400 font-medium text-sm leading-relaxed">
            Prove your identity across platforms (desktop and mobile) by signing your profile metadata JSON with your root key, creating a portable trust anchor similar to Nostr.
          </p>
          
          <div class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 p-3 rounded-md font-mono text-[10px] text-stone-500 mt-2">
            {`{\n  "name": "${identity()?.name || "User"}",\n  "pubkey": "${identity()?.peerId || "..."}",\n  "signature": "sig_..."\n}`}
          </div>

          <button class="flat-button w-full mt-auto py-3">Publish Signed Profile</button>
        </div>

        {/* Web of Trust & Petnames */}
        <div class="flat-panel p-6 lg:col-span-2">
          <div class="flex items-center gap-3 mb-4">
            <ShieldCheck size={24} class="text-emerald-500" />
            <h3 class="text-xl font-black text-stone-900 dark:text-stone-100">Web of Trust & Contacts</h3>
          </div>
          <p class="text-stone-600 dark:text-stone-400 font-medium text-sm leading-relaxed mb-6 max-w-3xl">
            You don't need a global registry. Assign human-readable "Petnames" to public keys locally. If your trusted contacts vouch for a new peer, their trust organically bridges to your network.
          </p>

          <div class="overflow-x-auto border-2 border-stone-800 rounded-md">
            <table class="w-full text-left border-collapse">
              <thead>
                <tr class="bg-primary-100 dark:bg-stone-800 text-stone-800 dark:text-stone-200 border-b-2 border-stone-800">
                  <th class="p-3 font-black uppercase text-xs">Petname</th>
                  <th class="p-3 font-black uppercase text-xs">Public Key Prefix</th>
                  <th class="p-3 font-black uppercase text-xs">Trust Level</th>
                  <th class="p-3 font-black uppercase text-xs text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y-2 divide-stone-200 dark:divide-stone-700 font-medium">
                <tr class="bg-white dark:bg-[#2c2421]">
                  <td class="p-3 font-bold text-stone-500 italic" colspan="4">No contacts added yet. Discover peers nearby or import a key.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

      </div>
    </div>
  );
};
