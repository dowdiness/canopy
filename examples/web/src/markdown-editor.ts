// Markdown Block Editor — three-mode page wiring FFI → adapters.

import * as crdt from '@moonbit/crdt-markdown';
import { BlockInput } from '@canopy/editor-adapter/block-input';
import { MarkdownPreview } from '@canopy/editor-adapter/markdown-preview';
import '@canopy/editor-adapter/block-input.css';
import type { ViewPatch, UserIntent } from '@canopy/editor-adapter/types';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DEFAULT_TEXT = `# Hello World

Welcome to the Canopy Markdown editor.

This editor has three modes: raw, block, and preview.
`;

type Mode = 'raw' | 'block' | 'preview';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

const agentId = `md-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
const handle = crdt.create_markdown_editor(agentId);

let activeMode: Mode = 'block';
let activeNodeId: number | null = null;
let rawSyncScheduled = false;
let rawDirty = false;

// ---------------------------------------------------------------------------
// DOM helpers
// ---------------------------------------------------------------------------

function must<T extends HTMLElement>(id: string): T {
  const el = document.getElementById(id);
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

const modeTabs = document.querySelectorAll<HTMLButtonElement>('.mode-tab');

// ---------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------

const blockInput = new BlockInput(blockContainer);
const preview = new MarkdownPreview(previewContainer);

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
  if (rawSyncScheduled) return;
  rawSyncScheduled = true;
  requestAnimationFrame(() => {
    rawSyncScheduled = false;
    crdt.markdown_set_text(handle, rawEditor.value);
    refresh();
  });
});

// ---------------------------------------------------------------------------
// Mode switching
// ---------------------------------------------------------------------------

function setMode(mode: Mode): void {
  if (mode === activeMode) return;

  // Sync from current mode before switching — only if user edited in raw mode.
  // If they just viewed raw mode without editing, don't write back the
  // ZWSP-stripped display text (which would destroy empty block placeholders).
  if (activeMode === 'raw' && rawDirty) {
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
  }

  // Update tab styles
  modeTabs.forEach(tab => {
    tab.classList.toggle('active', tab.dataset.mode === mode);
  });

  updateToolbar();
}

modeTabs.forEach(tab => {
  tab.addEventListener('click', () => {
    setMode(tab.dataset.mode as Mode);
  });
});

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

function updateToolbar(): void {
  const hasSelection = activeNodeId !== null && activeMode === 'block';
  h1Btn.disabled = !hasSelection;
  h2Btn.disabled = !hasSelection;
  h3Btn.disabled = !hasSelection;
  listBtn.disabled = !hasSelection;
  deleteBtn.disabled = !hasSelection;
}

/** Toggle heading level: clicking the same level reverts to paragraph (level 0). */
function toggleHeading(level: number): void {
  if (activeNodeId == null) return;
  const info = getActiveBlockInfo();
  const targetLevel = info && info.level === level ? 0 : level;
  applyEdit('change_heading_level', activeNodeId, '', targetLevel);
}

h1Btn.addEventListener('click', () => toggleHeading(1));
h2Btn.addEventListener('click', () => toggleHeading(2));
h3Btn.addEventListener('click', () => toggleHeading(3));

listBtn.addEventListener('click', () => {
  if (activeNodeId != null) applyEdit('toggle_list_item', activeNodeId, '', 0);
});

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
});

// ---------------------------------------------------------------------------
// Keyboard shortcuts (block mode)
// ---------------------------------------------------------------------------

document.addEventListener('keydown', (e) => {
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
});

// ---------------------------------------------------------------------------
// Examples
// ---------------------------------------------------------------------------

document.querySelectorAll<HTMLButtonElement>('.example-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    const text = btn.dataset.example ?? DEFAULT_TEXT;
    crdt.markdown_set_text(handle, text);
    syncRawFromModel();
    activeNodeId = null;
    refresh();
    updateToolbar();
  });
});

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

window.addEventListener('beforeunload', () => {
  blockInput.destroy();
  preview.destroy();
  crdt.destroy_markdown_editor(handle);
});

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

crdt.markdown_set_text(handle, DEFAULT_TEXT);
syncRawFromModel();
refresh();
updateToolbar();
