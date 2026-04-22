import { Component } from "solid-js";
import { identity, activeLeftPane, setActiveLeftPane, theme } from "../store";
import { Shield, Settings, ChevronLeft } from "lucide-solid";
import { A } from "@solidjs/router";

export const Topbar: Component = () => {
  return (
    <header class="h-16 flex items-center justify-between px-4 md:px-6 sticky top-0 z-10 bg-primary-50 dark:bg-[#1f1917]">
      <div class="flex items-center gap-3">
        {activeLeftPane() && (
          <button 
            onClick={(e) => { e.preventDefault(); setActiveLeftPane(null); }}
            class="md:hidden w-12 h-12 flex items-center justify-center text-stone-600 hover:bg-stone-200 rounded-lg -ml-3"
            aria-label="Back to chat list"
          >
            <ChevronLeft size={28} />
          </button>
        )}
        <img 
          src={theme() === 'dark' ? "/src/assets/logo_dark.svg" : "/src/assets/logo_light.svg"} 
          alt="Stoa Logo" 
          class="w-8 h-8 md:w-9 md:h-9" 
        />
        <h1 class="font-black text-xl md:text-2xl tracking-tight text-stone-800 dark:text-stone-100 hidden sm:block">
          Stoa
        </h1>
      </div>

      <div class="flex items-center gap-3 md:gap-5">
        {identity() && (
          <div 
            class="flex items-center gap-2 text-xs md:text-sm px-3 md:px-4 py-1.5 font-bold chamfer-all chamfer-shadow dark:text-emerald-300"
            style={{ 
              "--chamfer-outer": "8px", 
              "--chamfer-inner": "6px", 
              "--shadow-x": "2px", 
              "--shadow-y": "2px",
              "--bg-color": theme() === 'dark' ? "#064e3b" : "#d1fae5", 
              "--border-color": theme() === 'dark' ? "#10b981" : "#065f46" 
            }}
          >
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
