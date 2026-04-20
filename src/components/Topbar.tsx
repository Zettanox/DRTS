import { Component } from "solid-js";
import { identity, activeLeftPane, setActiveLeftPane } from "../store";
import { Shield, Settings, ChevronLeft } from "lucide-solid";
import { A } from "@solidjs/router";

export const Topbar: Component = () => {
  return (
    <header class="h-16 flex items-center justify-between px-4 md:px-6 sticky top-0 z-10 bg-primary-50 dark:bg-[#1f1917]">
      <div class="flex items-center gap-3">
        {activeLeftPane() && (
          <button 
            onClick={() => setActiveLeftPane(null)} 
            class="md:hidden p-2 text-stone-600 hover:bg-stone-200 rounded-lg -ml-2"
          >
            <ChevronLeft size={24} />
          </button>
        )}
        <div class="w-8 h-8 md:w-9 md:h-9 chamfer-all chamfer-shadow flex items-center justify-center text-white font-black text-lg md:text-xl" style="--bg-color: var(--color-primary-500); --chamfer-outer: 6px; --chamfer-inner: 4px; --shadow-x: 2px; --shadow-y: 2px;">
          S
        </div>
        <h1 class="font-black text-xl md:text-2xl tracking-tight text-stone-800 dark:text-stone-100 hidden sm:block">
          Stoa
        </h1>
      </div>

      <div class="flex items-center gap-3 md:gap-5">
        {identity() && (
          <div class="flex items-center gap-2 text-xs md:text-sm px-2 md:px-3 py-1.5 rounded-lg bg-emerald-100 dark:bg-emerald-900/30 border-2 border-emerald-800 dark:border-emerald-600 font-bold">
            <Shield size={16} class="text-emerald-700 dark:text-emerald-400" />
            <span class="text-emerald-900 dark:text-emerald-300 hidden md:inline">{identity()?.name}</span>
          </div>
        )}

        <A href="/settings" class="p-2 rounded-xl text-stone-700 dark:text-stone-300 hover:bg-stone-200 dark:hover:bg-stone-800 transition-colors border-2 border-transparent hover:border-stone-800 dark:hover:border-stone-600 font-bold flex items-center gap-2">
          <Settings size={20} />
        </A>
      </div>
    </header>
  );
};
