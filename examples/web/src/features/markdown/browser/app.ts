'use client';

// Markdown Block Editor — three-mode page wiring FFI → adapters.

import { BlockInput, type BlockSelection } from '@canopy/editor-adapter/block-input';
import { MarkdownPreview } from '@canopy/editor-adapter/markdown-preview';
import '@canopy/editor-adapter/block-input.css';
import type { ViewPatch, UserIntent } from '@canopy/editor-adapter/types';
import type { MountedImperativeSession } from '../../../shared/route-lifecycle/browser/imperative-session';
import { stripParagraphSentinels } from './sentinels';

export type MarkdownEditorRuntime = typeof import('@moonbit/crdt-markdown');

export function mountMarkdownApp(
  root: Document | HTMLElement = globalThis.document,
  restoredSnapshot: unknown,
  crdt: MarkdownEditorRuntime,
): MountedImperativeSession {
// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DEFAULT_TEXT = `# Hello World

Welcome to the Canopy Markdown editor.

This editor has three modes: raw, block, and preview.
`;

type Mode = 'raw' | 'block' | 'preview';

// ---------------------------------------------------------------------------
// DOM and lifecycle ownership
// ---------------------------------------------------------------------------

const document = root instanceof Document ? root : root.ownerDocument;
const window = document.defaultView ?? globalThis.window;

function must<T extends HTMLElement>(id: string): T {
  const el = root.querySelector<HTMLElement>(`#${id}`);
  if (!el) throw new Error(`Missing element #${id}`);
  return el as T;
}

const rawPane = must<HTMLDivElement>('raw-pane');
const blockPane = must<HTMLDivElement>('block-pane');
const previewPane = must<HTMLDivElement>('preview-pane');
const rawEditor = must<HTMLTextAreaElement>('raw-editor');
const blockContainer = must<HTMLDivElement>('block-container');
const previewContainer = must<HTMLDivElement>('preview-container');
const toolbarEl = must<HTMLDivElement>('toolbar');

const h1Btn = must<HTMLButtonElement>('h1-btn');
const h2Btn = must<HTMLButtonElement>('h2-btn');
const h3Btn = must<HTMLButtonElement>('h3-btn');
const listBtn = must<HTMLButtonElement>('list-btn');
const deleteBtn = must<HTMLButtonElement>('delete-btn');

const modeTabs = Array.from(root.querySelectorAll<HTMLButtonElement>('.mode-tab'));
const exampleButtons = Array.from(root.querySelectorAll<HTMLButtonElement>('.example-btn'));
const surfaceCandidate = root.querySelector<HTMLElement>('[data-markdown-ready]');
if (surfaceCandidate === null) throw new Error('Missing Markdown editor surface');
const surfaceEl: HTMLElement = surfaceCandidate;
const listenerAbort = new window.AbortController();
let disposed = false;
let rawSyncFrame: number | null = null;
let releaseHandle: (() => void) | null = null;
let releaseBlockInput: (() => void) | null = null;
let releasePreview: (() => void) | null = null;

function dispose(): void {
  if (disposed) return;
  disposed = true;
  surfaceEl.inert = true;
  surfaceEl.dataset.markdownReady = 'false';
  listenerAbort.abort();
  if (rawSyncFrame !== null) {
    window.cancelAnimationFrame(rawSyncFrame);
    rawSyncFrame = null;
  }
  const releases = [
    ['preview adapter', releasePreview],
    ['BlockInput adapter', releaseBlockInput],
    ['MoonBit handle', releaseHandle],
  ] as const;
  releasePreview = null;
  releaseBlockInput = null;
  releaseHandle = null;
  releases.forEach(([resource, release]) => {
    try {
      release?.();
    } catch (error) {
      console.error(`Failed to dispose Markdown editor ${resource}`, error);
    }
  });
}

try {
const agentId = `md-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
const handle = crdt.create_markdown_editor(agentId);
releaseHandle = () => crdt.destroy_markdown_editor(handle);

let activeMode: Mode = 'block';
let activeNodeId: number | null = null;
let savedBlockSelection: BlockSelection | null = null;
let rawDirty = false;

// ---------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------

const paragraphSentinel = crdt.markdown_empty_paragraph_sentinel();
const blockInput = new BlockInput(blockContainer, {
  stripParagraphSentinels: (text) => stripParagraphSentinels(text, paragraphSentinel),
  getSourceText: () => crdt.markdown_export_text(handle),
});
releaseBlockInput = () => blockInput.destroy();
const preview = new MarkdownPreview(previewContainer);
releasePreview = () => preview.destroy();

// ---------------------------------------------------------------------------
// Core functions
// ---------------------------------------------------------------------------

function refresh(): void {
  const patchesJson = crdt.markdown_compute_view_patches_json(handle);
  const patches: ViewPatch[] = JSON.parse(patchesJson);
  blockInput.applyPatches(patches);
  preview.applyPatches(patches);
}

function syncRawFromModel(): void {
  const text = crdt.markdown_export_text(handle);
  if (rawEditor.value !== text) rawEditor.value = text;
}

function applyEdit(op: string, nodeId: number, param1: string, param2: number): boolean {
  const resultJson: string = crdt.markdown_apply_edit(
    handle, op, nodeId, param1, param2, Date.now(),
  );
  const result = JSON.parse(resultJson);
  refresh();
  syncRawFromModel();
  if (result.status === 'error') {
    console.error('[canopy] edit error:', result.message);
    return false;
  }
  return true;
}

/** Read ordered block IDs from the rendered DOM. */
function getBlockIds(): number[] {
  return Array.from(blockContainer.querySelectorAll<HTMLElement>('[data-node-id]'))
    .map(el => parseInt(el.dataset.nodeId!, 10))
    .filter(id => !isNaN(id));
}

function selectBlock(id: number): void {
  blockInput.applyPatches([{ type: 'SelectNode', node_id: id }]);
  activeNodeId = id;
  updateToolbar();
}

/** Read the active block's kind and heading level from the DOM. */
function getActiveBlockInfo(): { kind: string; level: number } | null {
  if (activeNodeId === null) return null;
  const div = blockContainer.querySelector<HTMLElement>(
    `[data-node-id="${activeNodeId}"]`,
  );
  if (!div) return null;
  const kind = div.dataset.kind ?? '';
  // kind_tag is "H1"–"H6" for headings
  const levelMatch = kind.match(/^H(\d)$/);
  const level = levelMatch ? parseInt(levelMatch[1], 10) : 0;
  return { kind, level };
}

// ---------------------------------------------------------------------------
// Intent handling (BlockInput → FFI)
// ---------------------------------------------------------------------------

blockInput.onIntent((intent: UserIntent) => {
  switch (intent.type) {
    case 'CommitEdit':
      applyEdit('commit_edit', intent.node_id, intent.value, 0);
      break;

    case 'StructuralEdit': {
      const { op, node_id: nodeId, params } = intent;
      const blocksBefore = getBlockIds();
      const index = blocksBefore.indexOf(nodeId);

      applyEdit(op, nodeId, '', parseInt(params.offset || '0'));

      // Focus management: move to new/adjacent block after structural edit
      const blocksAfter = getBlockIds();
      if (op === 'insert_block_after' || op === 'split_block') {
        const target = blocksAfter[index + 1];
        if (target != null) selectBlock(target);
      } else if (op === 'merge_with_previous' && index > 0) {
        const target = blocksAfter[index - 1];
        if (target != null) selectBlock(target);
      }
      break;
    }

    case 'SelectNode':
      activeNodeId = intent.node_id;
      updateToolbar();
      break;

    default:
      break;
  }
});

// ---------------------------------------------------------------------------
// Raw mode input
// ---------------------------------------------------------------------------

rawEditor.addEventListener('input', () => {
  rawDirty = true;
  if (rawSyncFrame !== null) return;
  rawSyncFrame = window.requestAnimationFrame(() => {
    rawSyncFrame = null;
    if (disposed) return;
    crdt.markdown_set_text(handle, rawEditor.value);
    refresh();
    rawDirty = false;
  });
}, { signal: listenerAbort.signal });

// ---------------------------------------------------------------------------
// Mode switching
// ---------------------------------------------------------------------------

function setMode(mode: Mode): void {
  if (mode === activeMode) return;

  if (activeMode === 'block') {
    savedBlockSelection = blockInput.getSelection();
    if (savedBlockSelection === null) activeNodeId = null;
  }

  // Sync from current mode before switching — only if user edited in raw mode.
  // If they just viewed raw mode without editing, don't write back the
  // ZWSP-stripped display text (which would destroy empty block placeholders).
  if (activeMode === 'raw' && rawDirty) {
    if (rawSyncFrame !== null) {
      window.cancelAnimationFrame(rawSyncFrame);
      rawSyncFrame = null;
    }
    crdt.markdown_set_text(handle, rawEditor.value);
    refresh();
    rawDirty = false;
  }

  activeMode = mode;

  // Show/hide panes
  rawPane.hidden = mode !== 'raw';
  blockPane.hidden = mode !== 'block';
  previewPane.hidden = mode !== 'preview';
  toolbarEl.hidden = mode !== 'block';

  // Sync to new mode
  if (mode === 'raw') {
    syncRawFromModel();
    rawDirty = false;
    rawEditor.focus();
  } else if (mode === 'block' && savedBlockSelection !== null) {
    if (!blockInput.restoreSelection(savedBlockSelection)) {
      savedBlockSelection = null;
      activeNodeId = null;
    }
  }

  // Update tab styles
  modeTabs.forEach(tab => {
    const isActive = tab.dataset.mode === mode;
    tab.classList.toggle('active', isActive);
    tab.setAttribute('aria-selected', String(isActive));
    tab.tabIndex = isActive ? 0 : -1;
  });

  updateToolbar();
}

modeTabs.forEach(tab => {
  tab.addEventListener('click', () => {
    setMode(tab.dataset.mode as Mode);
  }, { signal: listenerAbort.signal });

  tab.addEventListener('keydown', (event) => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    const offset = event.key === 'ArrowRight' ? 1 : -1;
    const nextIndex = (modeTabs.indexOf(tab) + offset + modeTabs.length) % modeTabs.length;
    const nextTab = modeTabs[nextIndex];
    if (nextTab === undefined) return;
    setMode(nextTab.dataset.mode as Mode);
    nextTab.focus();
  }, { signal: listenerAbort.signal });
});

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

function updateToolbar(): void {
  const hasSelection = activeNodeId !== null && activeMode === 'block';
  const info = hasSelection ? getActiveBlockInfo() : null;
  h1Btn.disabled = !hasSelection;
  h2Btn.disabled = !hasSelection;
  h3Btn.disabled = !hasSelection;
  listBtn.disabled = !hasSelection;
  deleteBtn.disabled = !hasSelection;
  h1Btn.setAttribute('aria-pressed', String(info?.level === 1));
  h2Btn.setAttribute('aria-pressed', String(info?.level === 2));
  h3Btn.setAttribute('aria-pressed', String(info?.level === 3));
  listBtn.setAttribute(
    'aria-pressed',
    String(info?.kind === 'ListItem' || info?.kind === 'OrderedListItem'),
  );
}

/** Toggle heading level: clicking the same level reverts to paragraph (level 0). */
function toggleHeading(level: number): void {
  if (activeNodeId == null) return;
  const info = getActiveBlockInfo();
  const targetLevel = info && info.level === level ? 0 : level;
  applyEdit('change_heading_level', activeNodeId, '', targetLevel);
}

h1Btn.addEventListener('click', () => toggleHeading(1), { signal: listenerAbort.signal });
h2Btn.addEventListener('click', () => toggleHeading(2), { signal: listenerAbort.signal });
h3Btn.addEventListener('click', () => toggleHeading(3), { signal: listenerAbort.signal });

listBtn.addEventListener('click', () => {
  if (activeNodeId != null) applyEdit('toggle_list_item', activeNodeId, '', 0);
}, { signal: listenerAbort.signal });

deleteBtn.addEventListener('click', () => {
  if (activeNodeId == null) return;
  const blocksBefore = getBlockIds();
  const index = blocksBefore.indexOf(activeNodeId);
  applyEdit('delete', activeNodeId, '', 0);
  // Focus the next (or previous) block after deletion
  const blocksAfter = getBlockIds();
  if (blocksAfter.length > 0) {
    const nextIndex = Math.min(index, blocksAfter.length - 1);
    selectBlock(blocksAfter[nextIndex]);
  } else {
    activeNodeId = null;
    updateToolbar();
  }
}, { signal: listenerAbort.signal });

// ---------------------------------------------------------------------------
// Keyboard shortcuts (block mode)
// ---------------------------------------------------------------------------

document.addEventListener('keydown', (e: KeyboardEvent) => {
  if (activeMode !== 'block' || activeNodeId === null) return;
  if (e.isComposing) return;

  // Ctrl+1–6: toggle heading level
  if (e.ctrlKey && !e.shiftKey && e.key >= '1' && e.key <= '6') {
    e.preventDefault();
    toggleHeading(parseInt(e.key));
    return;
  }

  // Ctrl+0: revert to paragraph
  if (e.ctrlKey && !e.shiftKey && e.key === '0') {
    e.preventDefault();
    applyEdit('change_heading_level', activeNodeId, '', 0);
    return;
  }

  // Ctrl+Shift+L: toggle list
  if (e.ctrlKey && e.shiftKey && (e.key === 'l' || e.key === 'L')) {
    e.preventDefault();
    applyEdit('toggle_list_item', activeNodeId, '', 0);
    return;
  }
}, { signal: listenerAbort.signal });

// ---------------------------------------------------------------------------
// Examples
// ---------------------------------------------------------------------------

exampleButtons.forEach(btn => {
  btn.addEventListener('click', () => {
    const text = btn.dataset.example ?? DEFAULT_TEXT;
    blockInput.clearSelection();
    crdt.markdown_set_text(handle, text);
    syncRawFromModel();
    activeNodeId = null;
    savedBlockSelection = null;
    refresh();
    updateToolbar();
  }, { signal: listenerAbort.signal });
});

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

window.addEventListener('beforeunload', dispose, { signal: listenerAbort.signal });

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

rawPane.hidden = true;
blockPane.hidden = false;
previewPane.hidden = true;
toolbarEl.hidden = false;
modeTabs.forEach((tab) => {
  const isActive = tab.dataset.mode === 'block';
  tab.classList.toggle('active', isActive);
  tab.setAttribute('aria-selected', String(isActive));
  tab.tabIndex = isActive ? 0 : -1;
});

const initialText = typeof restoredSnapshot === 'string'
  ? restoredSnapshot
  : DEFAULT_TEXT;
crdt.markdown_set_text(handle, initialText);
syncRawFromModel();
refresh();
updateToolbar();
surfaceEl.inert = false;
surfaceEl.dataset.markdownReady = 'true';

return {
  snapshot: () => rawDirty || rawSyncFrame !== null
    ? rawEditor.value
    : crdt.markdown_export_text(handle),
  restoreFocus(token): boolean {
    if (disposed) return false;
    const modeTarget = modeTabs.find((tab) => tab.dataset.routeFocus === token);
    const target = modeTarget ?? (
      token === 'raw-editor' && !rawPane.hidden ? rawEditor : null
    );
    if (target === null) return false;
    target.focus({ preventScroll: true });
    return document.activeElement === target;
  },
  dispose,
};
} catch (error) {
  dispose();
  throw error;
}
}
