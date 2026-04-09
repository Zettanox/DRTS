import { Component } from "solid-js";
import { identity } from "../store";
import { QrCode, ShieldCheck, Contact2, PenLine, Smartphone, DownloadCloud, ChevronLeft, Moon, Sun } from "lucide-solid";

import { A } from "@solidjs/router";
import { toggleTheme, theme } from "../store";

export const SettingsView: Component = () => {
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
            </div>
          </div>

          <div>
            <h4 class="text-sm font-black uppercase text-stone-500 mb-2">Public Key</h4>
            <div class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 p-3 rounded-md break-all font-mono text-xs text-stone-700 dark:text-stone-300">
              {identity()?.publicKey || "No identity generated"}
            </div>
          </div>

          <div class="flex gap-4">
            <button class="flat-button py-2.5 px-4 flex-1 flex items-center justify-center gap-2">
              <DownloadCloud size={18} /> Export Keypair
            </button>
            <button class="flat-button-secondary py-2.5 px-4 flex items-center justify-center gap-2">
              <QrCode size={18} /> Show QR
            </button>
          </div>
        </div>

        {/* Nostr-style Profile & Cross-Platform */}
        <div class="flat-panel p-6 flex flex-col gap-5">
          <div class="flex items-center gap-3 text-primary-600 dark:text-primary-400 mb-2">
            <Smartphone size={24} />
            <h3 class="text-xl font-black text-stone-900 dark:text-stone-100">Cross-Platform Sync</h3>
          </div>
          <p class="text-stone-600 dark:text-stone-400 font-medium text-sm leading-relaxed">
            Prove your identity across platforms (desktop and mobile) by signing your profile metadata JSON with your root key, creating a portable trust anchor similar to Nostr.
          </p>
          
          <div class="bg-stone-100 dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-700 p-3 rounded-md font-mono text-[10px] text-stone-500 mt-2">
            {`{\n  "name": "${identity()?.name || "User"}",\n  "pubkey": "${identity()?.publicKey}",\n  "signature": "sig_..."\n}`}
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
                  <td class="p-3 font-bold flex items-center gap-2">Alice <PenLine size={12} class="text-stone-400 cursor-pointer" /></td>
                  <td class="p-3 font-mono text-xs text-stone-500">ed25519:abcdef...</td>
                  <td class="p-3"><span class="px-2 py-0.5 bg-emerald-100 text-emerald-800 border-2 border-emerald-800 font-bold rounded-md text-xs">Verified via QR</span></td>
                  <td class="p-3 text-right">
                    <button class="text-xs font-bold text-stone-500 hover:text-stone-800">Manage</button>
                  </td>
                </tr>
                <tr class="bg-white dark:bg-[#2c2421]">
                  <td class="p-3 font-bold flex items-center gap-2">Bob <PenLine size={12} class="text-stone-400 cursor-pointer" /></td>
                  <td class="p-3 font-mono text-xs text-stone-500">ed25519:deadbeef..</td>
                  <td class="p-3"><span class="px-2 py-0.5 bg-blue-100 text-blue-800 border-2 border-blue-800 font-bold rounded-md text-xs">Vouched by Alice</span></td>
                  <td class="p-3 text-right">
                    <button class="text-xs font-bold text-stone-500 hover:text-stone-800">Manage</button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

      </div>
    </div>
  );
};
