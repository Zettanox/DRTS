import {
  Component,
  createSignal,
  onCleanup,
  onMount,
} from "solid-js";
import { listen } from "@tauri-apps/api/event";
import {
  editGroupSpace,
  getGroupSpaceText,
  openGroupSpace,
} from "../tauri-bridge";

export const SpaceEditor: Component<{ groupId: string }> = (props) => {
  let textareaRef!: HTMLTextAreaElement;
  const [content, setContent] = createSignal("");
  const [synced, setSynced] = createSignal(true);
  
  let prevValue = "";

  const loadText = async () => {
    try {
      const text = await getGroupSpaceText(props.groupId);
      // Try to preserve cursor
      let selectionStart = 0;
      let selectionEnd = 0;
      let isFocused = false;
      if (textareaRef && document.activeElement === textareaRef) {
        isFocused = true;
        selectionStart = textareaRef.selectionStart;
        selectionEnd = textareaRef.selectionEnd;
      }

      setContent(text);
      prevValue = text;

      if (isFocused && textareaRef) {
        // A robust implementation would adjust the cursor based on where the 
        // remote edit happened. For Phase 1 we'll restore to exact index.
        // It might be slightly off if remote inserted text *before* our cursor.
        textareaRef.selectionStart = selectionStart;
        textareaRef.selectionEnd = selectionEnd;
      }
    } catch (e) {
      console.error("Failed to fetch space text", e);
    }
  };

  onMount(async () => {
    // 1. Load initial text from local disk / local CRDT state
    await loadText();
    // 2. Broadcast our state vector to peers to initiate sync
    await openGroupSpace(props.groupId);

    // 3. Listen for incoming remote updates
    const unlistenUpdate = await listen<{ group_id: string }>(
      "space-remote-update",
      async (e) => {
        if (e.payload.group_id === props.groupId) {
          setSynced(false);
          await loadText();
          setTimeout(() => setSynced(true), 500); // Visual indicator
        }
      }
    );

    onCleanup(async () => {
      unlistenUpdate();
    });
  });

  const handleInput = async (e: Event) => {
    const target = e.target as HTMLTextAreaElement;
    const newValue = target.value;

    // Simple diffing algorithm to extract change (index, deleteCount, insertText)
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

    // Update state
    setContent(newValue);
    prevValue = newValue;

    // Send to CRDT backend
    if (deleteCount > 0 || insertText.length > 0) {
      setSynced(false);
      await editGroupSpace(props.groupId, start, deleteCount, insertText);
      setSynced(true);
    }
  };

  return (
    <div class="flex-1 flex flex-col items-center bg-stone-100 dark:bg-stone-900 overflow-y-auto">
      {/* Editor Header / Tooling Area */}
      <div class="w-full max-w-4xl pt-8 pb-4 px-12 flex justify-between items-center select-none sticky top-0 bg-stone-100/90 dark:bg-stone-900/90 backdrop-blur-sm z-10">
        <h2 class="text-2xl font-black text-stone-800 dark:text-stone-200 uppercase tracking-tighter">
          Shared Document
        </h2>
        <div class="flex items-center gap-2">
          {synced() ? (
            <span class="text-xs font-bold text-emerald-600 tracking-widest uppercase">
              Synced
            </span>
          ) : (
            <span class="text-xs font-bold text-stone-400 tracking-widest uppercase animate-pulse">
              Syncing
            </span>
          )}
        </div>
      </div>

      {/* Editor Canvas */}
      <div class="w-full max-w-4xl px-12 pb-12 flex-1 flex flex-col">
        <textarea
          ref={textareaRef}
          value={content()}
          onInput={handleInput}
          class="flex-1 w-full h-full min-h-[70vh] bg-transparent outline-none resize-none font-mono text-sm leading-relaxed text-stone-800 dark:text-stone-300 placeholder-stone-400 dark:placeholder-stone-600"
          placeholder="Start typing... everything is synced instantly."
          spellcheck={false}
        />
      </div>
    </div>
  );
};
