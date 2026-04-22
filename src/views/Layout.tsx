import { Component } from "solid-js";
import { Topbar } from "../components/Topbar";
import { Sidebar } from "../components/Sidebar";
import { ContactRequestModal } from "../components/ContactRequestModal";
import { activeLeftPane } from "../store";

export const Layout: Component<{ children: any }> = (props) => {
  return (
    <div class="h-screen w-screen flex flex-col overflow-hidden relative">
      <Topbar />
      <div class="flex-1 flex overflow-hidden z-10 border-t-2 border-stone-800 dark:border-stone-700">
        <Sidebar />
        <main 
          class="flex-1 min-w-0 bg-[#fffdfa] dark:bg-[#241d1a]"
          classList={{ 'flex': !!activeLeftPane(), 'hidden md:flex': !activeLeftPane() }}
        >
          {props.children}
        </main>
      </div>
      <ContactRequestModal />
    </div>
  );
};
