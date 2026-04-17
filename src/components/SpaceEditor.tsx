import {
  Component,
  createSignal,
  createEffect,
  onCleanup,
  onMount,
  For,
  Show,
} from "solid-js";
import { listen } from "@tauri-apps/api/event";
import {
  openGroupSpace,
  listSpaceFiles,
  createSpaceFile,
  importSpaceFile,
  deleteSpaceFile,
  getSpaceFileText,
  editSpaceFile,
} from "../tauri-bridge";
import type { SpaceFile } from "../store";
import { FilePlus, Upload, Trash2, FileText, AlertTriangle } from "lucide-solid";

export const SpaceEditor: Component<{ groupId: string }> = (props) => {
  let textareaRef!: HTMLTextAreaElement;

  const [files, setFiles] = createSignal<SpaceFile[]>([]);
  const [activeFileId, setActiveFileId] = createSignal<string | null>(null);
  const [content, setContent] = createSignal("");
  const [synced, setSynced] = createSignal(true);
  const [newFileName, setNewFileName] = createSignal("");
  const [showNewInput, setShowNewInput] = createSignal(false);
  const [errorMsg, setErrorMsg] = createSignal<string | null>(null);

  let prevValue = "";

  // ─── Data Loading ───────────────────────────────────────────────────────────

  const loadFiles = async () => {
    try {
      const allFiles = await listSpaceFiles(props.groupId);
      const visible = allFiles.filter((f) => !f.deleted);
      setFiles(visible);

      // If active file was deleted or doesn't exist, select first available
      const currentId = activeFileId();
      if (currentId && !visible.find((f) => f.id === currentId)) {
        setActiveFileId(visible.length > 0 ? visible[0].id : null);
      } else if (!currentId && visible.length > 0) {
        setActiveFileId(visible[0].id);
      }
    } catch (e) {
      console.error("Failed to list space files", e);
    }
  };

  const loadFileContent = async (fileId: string) => {
    try {
      const text = await getSpaceFileText(props.groupId, fileId);
      // Preserve cursor if focused
      let selStart = 0, selEnd = 0, focused = false;
      if (textareaRef && document.activeElement === textareaRef) {
        focused = true;
        selStart = textareaRef.selectionStart;
        selEnd = textareaRef.selectionEnd;
      }

      setContent(text);
      prevValue = text;

      if (focused && textareaRef) {
        textareaRef.selectionStart = selStart;
        textareaRef.selectionEnd = selEnd;
      }
    } catch (e) {
      console.error("Failed to load file text", e);
    }
  };

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  onMount(async () => {
    await loadFiles();
    await openGroupSpace(props.groupId);

    const unlistenUpdate = await listen<{ group_id: string }>(
      "space-remote-update",
      async (e) => {
        if (e.payload.group_id === props.groupId) {
          setSynced(false);
          await loadFiles();
          const fid = activeFileId();
          if (fid) await loadFileContent(fid);
          setTimeout(() => setSynced(true), 500);
        }
      }
    );

    onCleanup(() => {
      unlistenUpdate();
    });
  });

  // Load content whenever the active file changes
  createEffect(() => {
    const fid = activeFileId();
    if (fid) {
      loadFileContent(fid);
    } else {
      setContent("");
      prevValue = "";
    }
  });

  // ─── Actions ────────────────────────────────────────────────────────────────

  const handleInput = async (e: Event) => {
    const target = e.target as HTMLTextAreaElement;
    const newValue = target.value;
    const fid = activeFileId();
    if (!fid) return;

    // Simple diff
    let start = 0;
    while (
      start < prevValue.length &&
      start < newValue.length &&
      prevValue[start] === newValue[start]
    ) {
      start++;
    }

    let endPrev = prevValue.length - 1;
    let endNew = newValue.length - 1;
    while (
      endPrev >= start &&
      endNew >= start &&
      prevValue[endPrev] === newValue[endNew]
    ) {
      endPrev--;
      endNew--;
    }

    const deleteCount = endPrev - start + 1;
    const insertText = newValue.substring(start, endNew + 1);

    setContent(newValue);
    prevValue = newValue;

    if (deleteCount > 0 || insertText.length > 0) {
      setSynced(false);
      await editSpaceFile(props.groupId, fid, start, deleteCount, insertText);
      setSynced(true);
    }
  };

  const handleCreateFile = async () => {
    const name = newFileName().trim();
    if (!name) return;
    try {
      const fileId = await createSpaceFile(props.groupId, name);
      setNewFileName("");
      setShowNewInput(false);
      await loadFiles();
      setActiveFileId(fileId);
    } catch (e: any) {
      setErrorMsg(e?.toString() || "Failed to create file");
      setTimeout(() => setErrorMsg(null), 4000);
    }
  };

  const handleImportFile = async () => {
    try {
      const fileId = await importSpaceFile(props.groupId);
      await loadFiles();
      setActiveFileId(fileId);
    } catch (e: any) {
      const msg = e?.toString() || "Failed to import file";
      if (msg !== "Error: No file selected") {
        setErrorMsg(msg);
        setTimeout(() => setErrorMsg(null), 5000);
      }
    }
  };

  const handleDeleteFile = async (fileId: string) => {
    try {
      await deleteSpaceFile(props.groupId, fileId);
      if (activeFileId() === fileId) {
        setActiveFileId(null);
      }
      await loadFiles();
    } catch (e: any) {
      setErrorMsg(e?.toString() || "Failed to delete file");
      setTimeout(() => setErrorMsg(null), 4000);
    }
  };

  // ─── Render ─────────────────────────────────────────────────────────────────

  return (
    <div class="flex-1 flex h-full overflow-hidden bg-stone-100 dark:bg-stone-900">
      {/* File Browser Sidebar */}
      <div class="w-56 shrink-0 flex flex-col border-r-2 border-stone-300 dark:border-stone-700 bg-stone-50 dark:bg-[#1a1513]">
        {/* Sidebar Header */}
        <div class="px-3 py-3 border-b-2 border-stone-300 dark:border-stone-700">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-xs font-black text-stone-500 dark:text-stone-400 uppercase tracking-widest">Files</h3>
            <div class="flex items-center gap-1">
              <button
                onClick={() => setShowNewInput(!showNewInput())}
                class="p-1.5 rounded-md hover:bg-stone-200 dark:hover:bg-stone-800 text-stone-500 hover:text-stone-700 dark:hover:text-stone-300 transition-colors"
                title="New file"
              >
                <FilePlus size={14} />
              </button>
              <button
                onClick={handleImportFile}
                class="p-1.5 rounded-md hover:bg-stone-200 dark:hover:bg-stone-800 text-stone-500 hover:text-stone-700 dark:hover:text-stone-300 transition-colors"
                title="Import file"
              >
                <Upload size={14} />
              </button>
            </div>
          </div>

          {/* New File Input */}
          <Show when={showNewInput()}>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                handleCreateFile();
              }}
              class="flex gap-1"
            >
              <input
                type="text"
                value={newFileName()}
                onInput={(e) => setNewFileName(e.currentTarget.value)}
                placeholder="filename.md"
                class="flex-1 text-xs font-bold px-2 py-1.5 rounded-md bg-white dark:bg-stone-800 border-2 border-stone-300 dark:border-stone-600 text-stone-800 dark:text-stone-200 outline-none focus:border-primary-500 transition-colors"
                autofocus
              />
              <button
                type="submit"
                class="px-2 py-1.5 text-xs font-black rounded-md bg-primary-500 text-white hover:bg-primary-600 transition-colors"
              >
                +
              </button>
            </form>
          </Show>
        </div>

        {/* File List */}
        <div class="flex-1 overflow-y-auto py-1">
          <For each={files()}>
            {(file) => (
              <div
                class={`group flex items-center gap-2 px-3 py-2 cursor-pointer transition-colors ${
                  activeFileId() === file.id
                    ? "bg-primary-100 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300"
                    : "text-stone-600 dark:text-stone-400 hover:bg-stone-200/60 dark:hover:bg-stone-800/60"
                }`}
                onClick={() => setActiveFileId(file.id)}
              >
                <FileText
                  size={14}
                  class={`shrink-0 ${
                    activeFileId() === file.id
                      ? "text-primary-500"
                      : "text-stone-400 dark:text-stone-500"
                  }`}
                />
                <span class="flex-1 truncate text-xs font-bold">{file.name}</span>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleDeleteFile(file.id);
                  }}
                  class="opacity-0 group-hover:opacity-100 p-1 rounded hover:bg-red-100 dark:hover:bg-red-900/40 text-stone-400 hover:text-red-500 transition-all"
                  title="Delete file"
                >
                  <Trash2 size={12} />
                </button>
              </div>
            )}
          </For>

          <Show when={files().length === 0}>
            <div class="px-3 py-6 text-center text-xs text-stone-400 font-bold">
              No files yet.<br />
              Create or import one.
            </div>
          </Show>
        </div>

        {/* Sync Status */}
        <div class="px-3 py-2 border-t-2 border-stone-300 dark:border-stone-700">
          {synced() ? (
            <span class="text-[10px] font-black text-emerald-600 tracking-widest uppercase">
              ● Synced
            </span>
          ) : (
            <span class="text-[10px] font-black text-amber-500 tracking-widest uppercase animate-pulse">
              ● Syncing
            </span>
          )}
        </div>
      </div>

      {/* Editor Panel */}
      <div class="flex-1 flex flex-col overflow-hidden">
        {/* Error Toast */}
        <Show when={errorMsg()}>
          <div class="mx-4 mt-3 px-4 py-3 rounded-lg bg-red-100 dark:bg-red-900/40 border-2 border-red-300 dark:border-red-700 flex items-start gap-2 animate-in fade-in slide-in-from-top-2 duration-200">
            <AlertTriangle size={16} class="text-red-500 shrink-0 mt-0.5" />
            <p class="text-xs font-bold text-red-700 dark:text-red-300">{errorMsg()}</p>
          </div>
        </Show>

        <Show
          when={activeFileId()}
          fallback={
            <div class="flex-1 flex items-center justify-center">
              <div class="text-center">
                <FileText size={48} class="mx-auto mb-4 text-stone-300 dark:text-stone-600" />
                <p class="text-stone-400 dark:text-stone-500 font-black text-lg">
                  {files().length === 0 ? "Create your first document" : "Select a file to edit"}
                </p>
                <p class="text-stone-400 dark:text-stone-600 font-bold text-sm mt-1">
                  All changes sync in real-time with your group
                </p>
              </div>
            </div>
          }
        >
          {/* Active file header */}
          <div class="px-6 py-3 border-b border-stone-200 dark:border-stone-800 flex items-center gap-2 select-none">
            <FileText size={16} class="text-primary-500" />
            <h3 class="text-sm font-black text-stone-700 dark:text-stone-300">
              {files().find((f) => f.id === activeFileId())?.name || "Untitled"}
            </h3>
          </div>

          {/* Textarea */}
          <div class="flex-1 overflow-y-auto">
            <textarea
              ref={textareaRef}
              value={content()}
              onInput={handleInput}
              class="w-full h-full min-h-full p-6 bg-transparent outline-none resize-none font-mono text-sm leading-relaxed text-stone-800 dark:text-stone-300 placeholder-stone-400 dark:placeholder-stone-600"
              placeholder="Start typing... everything syncs instantly."
              spellcheck={false}
            />
          </div>
        </Show>
      </div>
    </div>
  );
};
