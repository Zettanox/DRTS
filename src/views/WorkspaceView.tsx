import { Component } from 'solid-js';
import { activeLeftPane, activeRightPane, setActiveRightPane } from '../store';
import { ChatView } from './ChatView';
import { X, Columns } from 'lucide-solid';

export const WorkspaceView: Component = () => {
  return (
    <div class="flex-1 flex overflow-hidden w-full h-full relative">
      {/* Left Pane */}
      <div class={`flex-1 overflow-hidden flex flex-col border-r-2 border-transparent bg-transparent ${activeRightPane() ? 'md:border-stone-800 md:dark:border-stone-700' : ''} ${!activeLeftPane() ? 'items-center justify-center' : ''}`}>
        {!activeLeftPane() ? (
          <div class="text-stone-400 font-black text-xl flex flex-col items-center gap-4 opacity-50">
            <Columns size={48} />
            <p>Select a Chat or Group to connect</p>
          </div>
        ) : (
          <ChatView pane="left" id={activeLeftPane()?.id || ""} />
        )}
      </div>

      {/* Right Pane */}
      {activeRightPane() && activeLeftPane() && (
        <div class="hidden md:flex flex-1 overflow-hidden relative flex-col">
           <button 
             class="absolute top-4 right-4 z-50 p-1.5 bg-red-400 hover:bg-red-300 text-stone-900 border-2 border-stone-800 rounded-lg shadow-[2px_2px_0px_0px_#292524] transition-all active:translate-x-[2px] active:translate-y-[2px] active:shadow-none" 
             onClick={() => setActiveRightPane(null)}
             title="Close split view"
           >
             <X size={16} />
           </button>
           {activeRightPane() && <ChatView pane="right" id={activeRightPane()?.id || ""} />}
        </div>
      )}
    </div>
  );
};
