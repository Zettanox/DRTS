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
  exportSpaceFile,
} from "../tauri-bridge";
import type { SpaceFile } from "../store";
import { theme } from "../store";
import { FilePlus, Upload, Trash2, FileText, AlertTriangle, Download } from "lucide-solid";

// ─── CodeMirror Imports ───────────────────────────────────────────────────────
import { EditorView, basicSetup } from "codemirror";
import { EditorState, Compartment } from "@codemirror/state";
import { oneDark } from "@codemirror/theme-one-dark";
import { markdown } from "@codemirror/lang-markdown";
import { javascript } from "@codemirror/lang-javascript";
import { python } from "@codemirror/lang-python";
import { rust } from "@codemirror/lang-rust";
import { json } from "@codemirror/lang-json";
import { css } from "@codemirror/lang-css";
import { html } from "@codemirror/lang-html";
import { cpp } from "@codemirror/lang-cpp";
import { java } from "@codemirror/lang-java";

// ─── Language Detection ───────────────────────────────────────────────────────
function getLanguageExtension(fileName: string) {
  const ext = fileName.split(".").pop()?.toLowerCase() ?? "";
  switch (ext) {
    case "md":
    case "markdown":
      return markdown();
    case "js":
    case "mjs":
    case "cjs":
      return javascript();
    case "jsx":
      return javascript({ jsx: true });
    case "ts":
    case "mts":
      return javascript({ typescript: true });
    case "tsx":
      return javascript({ jsx: true, typescript: true });
    case "py":
      return python();
    case "rs":
      return rust();
    case "json":
    case "jsonc":
      return json();
    case "css":
    case "scss":
    case "less":
      return css();
    case "html":
    case "htm":
    case "svg":
      return html();
    case "c":
    case "cpp":
    case "cc":
    case "h":
    case "hpp":
      return cpp();
    case "java":
    case "kt":
      return java();
    default:
      return []; // plain text — still gets basicSetup features
  }
}

// ─── Custom Light Theme ────────────────────────────────────────────────────────
// Matches the app's warm stone palette so the editor feels native
const stoaLightTheme = EditorView.theme({
  "&": {
    backgroundColor: "transparent",
    color: "#1c1917",       // stone-900
    fontSize: "13.5px",
    fontFamily: "'JetBrains Mono', 'Fira Mono', 'Cascadia Code', 'Consolas', monospace",
    height: "100%",
  },
  ".cm-scroller": {
    fontFamily: "inherit",
    lineHeight: "1.75",
    overflow: "auto",
    padding: "12px 0",
  },
  ".cm-content": {
    padding: "0 24px",
    caretColor: "#eb6534",  // primary-500
  },
  ".cm-cursor": {
    borderLeftColor: "#eb6534",
    borderLeftWidth: "2px",
  },
  ".cm-activeLine": {
    backgroundColor: "rgba(235,101,52,0.06)",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "rgba(235,101,52,0.06)",
  },
  ".cm-selectionBackground, ::selection": {
    backgroundColor: "rgba(235,101,52,0.18) !important",
  },
  ".cm-gutters": {
    backgroundColor: "transparent",
    border: "none",
    color: "#a8a29e",        // stone-400
    paddingRight: "8px",
  },
  ".cm-lineNumbers .cm-gutterElement": {
    minWidth: "36px",
    textAlign: "right",
  },
  ".cm-foldGutter": { width: "16px" },
  ".cm-tooltip": {
    backgroundColor: "#f5f5f4",
    border: "1px solid #d6d3d1",
    borderRadius: "6px",
  },
  ".cm-searchMatch": {
    backgroundColor: "rgba(235,101,52,0.25)",
    outline: "1px solid #eb6534",
  },
  ".cm-searchMatch.cm-searchMatch-selected": {
    backgroundColor: "rgba(235,101,52,0.45)",
  },
}, { dark: false });

// ─── Custom Dark Theme ─────────────────────────────────────────────────────────
const stoaDarkTheme = EditorView.theme({
  "&": {
    backgroundColor: "transparent",
    color: "#d6d3d1",        // stone-300
    fontSize: "13.5px",
    fontFamily: "'JetBrains Mono', 'Fira Mono', 'Cascadia Code', 'Consolas', monospace",
    height: "100%",
  },
  ".cm-scroller": {
    fontFamily: "inherit",
    lineHeight: "1.75",
    overflow: "auto",
    padding: "12px 0",
  },
  ".cm-content": {
    padding: "0 24px",
    caretColor: "#f48c66",   // primary-400
  },
  ".cm-cursor": {
    borderLeftColor: "#f48c66",
    borderLeftWidth: "2px",
  },
  ".cm-activeLine": {
    backgroundColor: "rgba(244,140,102,0.08)",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "rgba(244,140,102,0.08)",
  },
  ".cm-selectionBackground, ::selection": {
    backgroundColor: "rgba(244,140,102,0.2) !important",
  },
  ".cm-gutters": {
    backgroundColor: "transparent",
    border: "none",
    color: "#57534e",        // stone-600
    paddingRight: "8px",
  },
  ".cm-lineNumbers .cm-gutterElement": {
    minWidth: "36px",
    textAlign: "right",
  },
  ".cm-foldGutter": { width: "16px" },
  ".cm-tooltip": {
    backgroundColor: "#292524",
    border: "1px solid #44403c",
    borderRadius: "6px",
    color: "#d6d3d1",
  },
  ".cm-searchMatch": {
    backgroundColor: "rgba(244,140,102,0.25)",
    outline: "1px solid #f48c66",
  },
  ".cm-searchMatch.cm-searchMatch-selected": {
    backgroundColor: "rgba(244,140,102,0.45)",
  },
}, { dark: true });

// ─── Component ────────────────────────────────────────────────────────────────
export const SpaceEditor: Component<{ groupId: string }> = (props) => {
  let editorContainerRef!: HTMLDivElement;
  let editorView: EditorView | null = null;

  // Compartments allow reconfiguring parts of the editor without rebuilding
  const themeCompartment = new Compartment();
  const langCompartment = new Compartment();

  const [files, setFiles] = createSignal<SpaceFile[]>([]);
  const [activeFileId, setActiveFileId] = createSignal<string | null>(null);
  const [synced, setSynced] = createSignal(true);
  const [newFileName, setNewFileName] = createSignal("");
  const [showNewInput, setShowNewInput] = createSignal(false);
  const [errorMsg, setErrorMsg] = createSignal<string | null>(null);

  let selectNewest = false;
  // When true, the next editor change is from us pushing remote content —
  // we should NOT broadcast it back as a local edit.
  let suppressBroadcast = false;

  // ─── Editor Setup / Teardown ─────────────────────────────────────────────

  const createEditor = (initialContent: string, fileName: string) => {
    if (editorView) {
      editorView.destroy();
      editorView = null;
    }

    const isDark = theme() === "dark";
    const themeExt = isDark
      ? [stoaDarkTheme, oneDark]
      : [stoaLightTheme];

    const state = EditorState.create({
      doc: initialContent,
      extensions: [
        basicSetup,
        langCompartment.of(getLanguageExtension(fileName)),
        themeCompartment.of(themeExt),
        EditorView.updateListener.of((update) => {
          if (!update.docChanged || suppressBroadcast) return;

          // Collect all changes synchronously BEFORE any await.
          // iterChanges gives positions in the OLD document (before each transaction).
          // Multiple changes within one transaction need cumulative offset adjustment
          // so each subsequent CRDT write targets the correct shifted position.
          // Between transactions, positions are already relative to the doc after
          // all prior transactions, so no inter-transaction delta is needed.
          type Change = { from: number; deleteCount: number; insert: string };
          const allChanges: Change[] = [];

          for (const txn of update.transactions) {
            if (!txn.docChanged) continue;
            const txnChanges: Change[] = [];
            txn.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
              txnChanges.push({
                from: fromA,
                deleteCount: toA - fromA,
                insert: inserted.toString(),
              });
            });

            // Within a single transaction, apply offset to account for earlier
            // changes that have already shifted the CRDT's text.
            let delta = 0;
            for (const c of txnChanges) {
              allChanges.push({ from: c.from + delta, deleteCount: c.deleteCount, insert: c.insert });
              delta += c.insert.length - c.deleteCount;
            }
          }

          if (allChanges.length === 0) return;

          // Apply sequentially — never concurrently — to prevent position races.
          setSynced(false);
          (async () => {
            const fid = activeFileId();
            if (!fid) return;
            for (const change of allChanges) {
              if (change.deleteCount === 0 && change.insert.length === 0) continue;
              await editSpaceFile(props.groupId, fid, change.from, change.deleteCount, change.insert);
            }
            setSynced(true);
          })();
        }),
        EditorView.lineWrapping,
      ],
    });

    editorView = new EditorView({
      state,
      parent: editorContainerRef,
    });
  };

  // Push new content into an existing editor without destroying it
  // (preserves cursor position as much as possible)
  const setEditorContent = (newContent: string) => {
    if (!editorView) return;
    const current = editorView.state.doc.toString();
    if (current === newContent) return; // nothing changed

    suppressBroadcast = true;
    editorView.dispatch({
      changes: {
        from: 0,
        to: editorView.state.doc.length,
        insert: newContent,
      },
    });
    suppressBroadcast = false;
  };

  const switchEditorLanguage = (fileName: string) => {
    if (!editorView) return;
    editorView.dispatch({
      effects: langCompartment.reconfigure(getLanguageExtension(fileName)),
    });
  };

  const switchEditorTheme = (isDark: boolean) => {
    if (!editorView) return;
    editorView.dispatch({
      effects: themeCompartment.reconfigure(
        isDark ? [stoaDarkTheme, oneDark] : [stoaLightTheme]
      ),
    });
  };

  // ─── Data Loading ─────────────────────────────────────────────────────────

  const loadFiles = async () => {
    try {
      const allFiles = await listSpaceFiles(props.groupId);
      const visible = allFiles.filter((f) => !f.deleted);
      setFiles(visible);

      if (selectNewest && visible.length > 0) {
        const newest = visible.reduce((a, b) => a.timestamp > b.timestamp ? a : b);
        setActiveFileId(newest.id);
        selectNewest = false;
      } else {
        const currentId = activeFileId();
        if (currentId && !visible.find((f) => f.id === currentId)) {
          setActiveFileId(visible.length > 0 ? visible[0].id : null);
        } else if (!currentId && visible.length > 0) {
          setActiveFileId(visible[0].id);
        }
      }
    } catch (e) {
      console.error("Failed to list space files", e);
    }
  };

  const loadFileContent = async (fileId: string) => {
    try {
      const text = await getSpaceFileText(props.groupId, fileId);
      const fileName = files().find((f) => f.id === fileId)?.name ?? "";

      if (!editorView) {
        // First load or after a destroy — build fresh
        createEditor(text, fileName);
      } else {
        setEditorContent(text);
        switchEditorLanguage(fileName);
      }
    } catch (e) {
      console.error("Failed to load file text", e);
    }
  };

  // ─── Lifecycle ───────────────────────────────────────────────────────────

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
          if (fid) {
            const text = await getSpaceFileText(props.groupId, fid);
            setEditorContent(text);
          }
          setTimeout(() => setSynced(true), 500);
        }
      }
    );

    onCleanup(() => {
      unlistenUpdate();
      editorView?.destroy();
      editorView = null;
    });
  });

  // Rebuild/update the editor when the active file changes
  createEffect(() => {
    const fid = activeFileId();
    if (fid) {
      loadFileContent(fid);
    } else {
      editorView?.destroy();
      editorView = null;
    }
  });

  // Reconfigure the theme whenever the global theme signal changes
  createEffect(() => {
    switchEditorTheme(theme() === "dark");
  });

  // ─── File Actions ─────────────────────────────────────────────────────────

  const handleCreateFile = async () => {
    const name = newFileName().trim();
    if (!name) return;
    try {
      selectNewest = true;
      await createSpaceFile(props.groupId, name);
      setNewFileName("");
      setShowNewInput(false);
    } catch (e: any) {
      selectNewest = false;
      setErrorMsg(e?.toString() || "Failed to create file");
      setTimeout(() => setErrorMsg(null), 4000);
    }
  };

  const handleImportFile = async () => {
    try {
      selectNewest = true;
      await importSpaceFile(props.groupId);
    } catch (e: any) {
      selectNewest = false;
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
        editorView?.destroy();
        editorView = null;
        setActiveFileId(null);
      }
      await loadFiles();
    } catch (e: any) {
      setErrorMsg(e?.toString() || "Failed to delete file");
      setTimeout(() => setErrorMsg(null), 4000);
    }
  };

  const handleExportFile = async () => {
    const fid = activeFileId();
    if (!fid) return;
    const file = files().find((f) => f.id === fid);
    if (!file) return;
    try {
      await exportSpaceFile(props.groupId, fid, file.name);
    } catch (e: any) {
      setErrorMsg(e?.toString() || "Failed to export file");
      setTimeout(() => setErrorMsg(null), 4000);
    }
  };

  // ─── Render ───────────────────────────────────────────────────────────────

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
          <div class="mx-4 mt-3 px-4 py-3 rounded-lg bg-red-100 dark:bg-red-900/40 border-2 border-red-300 dark:border-red-700 flex items-start gap-2">
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
          {/* File header bar */}
          <div class="px-4 py-2.5 border-b border-stone-200 dark:border-stone-800 flex items-center gap-2 select-none shrink-0">
            <FileText size={14} class="text-primary-500 shrink-0" />
            <h3 class="flex-1 text-sm font-black text-stone-700 dark:text-stone-300 truncate">
              {files().find((f) => f.id === activeFileId())?.name || "Untitled"}
            </h3>
            <button
              onClick={handleExportFile}
              class="p-1.5 rounded-md hover:bg-stone-200 dark:hover:bg-stone-800 text-stone-400 hover:text-stone-700 dark:hover:text-stone-300 transition-colors shrink-0"
              title="Export file to disk"
            >
              <Download size={14} />
            </button>
          </div>

          {/* CodeMirror editor mount point */}
          <div
            ref={editorContainerRef}
            class="flex-1 overflow-hidden [&_.cm-editor]:h-full [&_.cm-editor.cm-focused]:outline-none [&_.cm-scroller]:overflow-auto"
          />
        </Show>
      </div>
    </div>
  );
};
