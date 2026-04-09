import { Component, createSignal, createMemo, For } from "solid-js";
import { endboxes, activeRightPane, setActiveRightPane } from "../store";
import { FileText, Download, Edit3, X, Users, History, Share2, Columns } from "lucide-solid";

export const EndboxView: Component<{ id: string, pane: "left" | "right" }> = (props) => {
  const [detailsOpen, setDetailsOpen] = createSignal(false);
  const [editingFile, setEditingFile] = createSignal<string | null>(null);
  const [editorContent, setEditorContent] = createSignal("");
  
  const endbox = createMemo(() => endboxes.find(e => e.id === props.id));

  return (
    <div class="h-full flex flex-col relative w-full overflow-hidden bg-transparent">
      {/* Header */}
      <div class="h-16 flex items-center justify-between px-4 md:px-6 bg-primary-50 dark:bg-[#1a1513] border-b-2 border-stone-800 dark:border-stone-700 z-10 shrink-0">
        <button 
          class="flex items-center gap-3 hover:bg-stone-200 dark:hover:bg-stone-800 p-2 -ml-2 rounded-lg transition-colors cursor-pointer text-left focus:outline-none"
          onClick={() => setDetailsOpen(true)}
        >
          <div class="flex items-center justify-center text-stone-700 dark:text-stone-300">
             <div class="p-1.5 rounded-lg bg-[#669ff4] border-2 border-stone-800 text-stone-900 shadow-[2px_2px_0px_0px_rgba(41,37,36,1)]">
                <FileText size={18} />
             </div>
          </div>
          <div>
            <h2 class="font-black text-lg md:text-xl text-stone-900 dark:text-stone-100 leading-tight">
              {endbox()?.name || "Unknown Endbox"}
            </h2>
            <p class="text-xs md:text-sm font-bold text-stone-500 dark:text-stone-400">
              {endbox()?.files.length || 0} Files • Click for details
            </p>
          </div>
        </button>

        <div class={`flex items-center gap-3 ${props.pane === 'right' ? 'mr-10' : ''}`}>
          {props.pane === "left" && !activeRightPane() && (
            <button 
              class="flat-button-secondary py-1.5 px-3 text-xs md:text-sm hidden md:flex items-center gap-2"
              onClick={(e) => { e.stopPropagation(); setActiveRightPane({ type: 'endbox', id: props.id }); }}
            >
              <Columns size={16} /> Split
            </button>
          )}
          <button class="flat-button py-1.5 px-3 md:px-4 text-xs md:text-sm flex items-center gap-2">
            <Share2 size={16} /> <span class="hidden md:inline">Share Files</span>
          </button>
        </div>
      </div>

      <div class="flex-1 flex overflow-hidden w-full relative">
        {/* Main Content Area */}
        <div class="flex-1 overflow-y-auto p-4 md:p-6 bg-[#fffdfa] dark:bg-[#241d1a]">
          {editingFile() ? (
             <div class="flex flex-col h-full gap-4 max-w-4xl mx-auto">
               <div class="flex items-center justify-between">
                  {/* eslint-disable-next-line @typescript-eslint/no-non-null-asserted-optional-chain */}
                  <h3 class="font-black text-xl text-stone-900 dark:text-stone-100">{endbox()?.files.find(f => f.id === editingFile())?.name}</h3>
                  <div class="flex gap-2">
                     <button onClick={() => setEditingFile(null)} class="flat-button-secondary py-1.5 px-3 font-bold text-sm">Cancel</button>
                     <button onClick={() => setEditingFile(null)} class="flat-button py-1.5 px-3 flex items-center gap-2 font-bold text-sm">
                       Save changes
                     </button>
                  </div>
               </div>
               <textarea 
                  class="flex-1 w-full p-4 bg-white dark:bg-[#1a1513] border-2 border-stone-800 dark:border-stone-700 rounded-xl resize-none focus:outline-none focus:ring-2 focus:border-transparent focus:ring-primary-500 font-mono text-sm text-stone-800 dark:text-stone-300 shadow-inner" 
                  value={editorContent()} 
                  onInput={(e) => setEditorContent(e.currentTarget.value)} 
               />
             </div>
          ) : (
            <div class="flex flex-col gap-3">
              <For each={endbox()?.files}>
                {(file) => {
                  const isEditable = /\.(txt|md|json|cc|js|ts|jsx|tsx|css|html|xml|csv|toml|yaml)$/i.test(file.name);
                  return (
                  <div class="flat-panel p-3 px-4 flex items-center justify-between group hover:bg-stone-50 dark:hover:bg-[#342823] transition-colors cursor-pointer">
                    <div class="flex items-center gap-4">
                      <div class="w-10 h-10 rounded-lg bg-primary-100 dark:bg-primary-900 border-2 border-stone-800 flex items-center justify-center text-primary-600 dark:text-primary-400 shadow-[2px_2px_0px_0px_#292524] shrink-0">
                        <FileText size={20} />
                      </div>
                      <div class="flex flex-col">
                        <h3 class="font-black text-stone-800 dark:text-stone-100 truncate max-w-[150px] sm:max-w-[300px] md:max-w-[400px]" title={file.name}>{file.name}</h3>
                        <div class="flex items-center gap-3 mt-1">
                           <p class="text-xs font-bold text-stone-500">{(file.sizeBytes / 1024).toFixed(1)} KB</p>
                           <p class="text-xs font-bold text-stone-300 dark:text-stone-600">•</p>
                           <p class="text-xs font-bold text-stone-500">{new Date(file.lastModified).toLocaleDateString()}</p>
                        </div>
                      </div>
                    </div>
                    <div class="flex gap-2 opacity-100 md:opacity-0 md:group-hover:opacity-100 transition-opacity">
                      {isEditable && (
                        <button 
                          class="p-2 text-stone-500 hover:text-stone-900 dark:hover:text-stone-100 bg-white dark:bg-stone-800 rounded mx-0.5 border-2 border-stone-800 shadow-[2px_2px_0px_0px_#292524] active:translate-y-px active:shadow-none transition-all"
                          title="Edit File"
                          onClick={(e) => {
                             e.stopPropagation();
                             setEditingFile(file.id);
                             setEditorContent(`Mock content for ${file.name}...\n\n// Add text here to sync across network nodes. `);
                          }}
                        >
                          <Edit3 size={16} />
                        </button>
                      )}
                      <button class="p-2 text-stone-500 hover:text-stone-900 dark:hover:text-stone-100 bg-white dark:bg-stone-800 rounded mx-0.5 border-2 border-stone-800 shadow-[2px_2px_0px_0px_#292524] active:translate-y-px active:shadow-none transition-all">
                        <Download size={16} />
                      </button>
                    </div>
                  </div>
                )}}
              </For>
              
              {(!endbox()?.files || endbox()?.files.length === 0) && (
                <div class="col-span-1 sm:col-span-2 lg:col-span-3 flex flex-col items-center justify-center py-20 text-stone-400">
                   <FileText size={48} class="mb-4 opacity-50" />
                   <h2 class="text-xl font-black">No files found</h2>
                   <p class="font-medium mt-2">Upload or create a file to start collaborating.</p>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Endbox Details Drawer */}
        {detailsOpen() && (
          <div class="w-full md:w-72 lg:w-80 border-l-2 border-stone-800 dark:border-stone-700 bg-primary-50 dark:bg-[#1a1513] shrink-0 absolute md:static inset-0 z-20 flex flex-col h-full animate-in slide-in-from-right-4 duration-200">
            <div class="h-16 flex items-center justify-between px-4 border-b-2 border-stone-800 dark:border-stone-700 bg-white dark:bg-[#2c2421]">
              <h3 class="font-black text-stone-800 dark:text-stone-100">Endbox Details</h3>
              <button onClick={() => setDetailsOpen(false)} class="p-2 text-stone-500 hover:text-stone-800 dark:hover:text-stone-100 hover:bg-stone-200 dark:hover:bg-stone-800 rounded-lg transition-colors">
                <X size={20} />
              </button>
            </div>
            
            <div class="p-4 flex-1 overflow-y-auto space-y-4">
              <div class="flat-panel p-4 flex flex-col gap-3">
                 <div class="font-black text-xs uppercase text-stone-500 tracking-wider flex items-center gap-2"><History size={14} /> Origin</div>
                 <div class="font-bold text-stone-800 dark:text-stone-200 text-sm">Created {new Date(endbox()?.createdAt || Date.now()).toLocaleDateString()}</div>
                 <div class="font-bold text-stone-800 dark:text-stone-200 text-sm">Hosted by <span class="text-primary-600">{endbox()?.host}</span></div>
              </div>
              
              <div class="flat-panel p-4 flex flex-col gap-3">
                 <div class="font-black text-xs uppercase text-stone-500 tracking-wider flex items-center gap-2"><Users size={14} /> Collaborators ({endbox()?.collaborators.length})</div>
                 <div class="flex flex-col gap-2 mt-2">
                    <For each={endbox()?.collaborators}>
                       {collab => (
                          <div class="text-sm font-bold text-stone-800 dark:text-stone-200 flex items-center gap-2">
                             <div class="w-2 h-2 rounded-full bg-primary-500 border border-stone-800"></div>
                             {collab}
                          </div>
                       )}
                    </For>
                 </div>
              </div>

              <div class="flat-panel p-4 flex flex-col gap-3">
                 <div class="font-black text-xs uppercase text-stone-500 tracking-wider flex items-center gap-2"><FileText size={14} /> Edit History</div>
                 <div class="text-sm font-bold text-stone-500 italic">Synced to network state.</div>
              </div>
            </div>
          </div>
        )}

      </div>
    </div>
  );
};
