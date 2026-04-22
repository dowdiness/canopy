import * as crdt from '@moonbit/crdt-json';
import { HTMLAdapter } from '@canopy/editor-adapter/html-adapter';
import type { ViewPatch, ViewNode } from '@canopy/editor-adapter/types';

type InlineMode = 'add-member' | 'wrap-object' | 'change-type' | null;

const EXAMPLE_FALLBACK = '{"hello": "world"}';
const VALID_TYPES = new Set(['null', 'bool', 'number', 'string', 'array', 'object']);

const agentId = `json-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
const handle = crdt.create_json_editor(agentId);

const editorEl = must<HTMLDivElement>('json-input');
const errorsEl = must<HTMLUListElement>('parse-errors');
const treeEl = must<HTMLDivElement>('tree-view');

const addMemberBtn = must<HTMLButtonElement>('add-member-btn');
const addElementBtn = must<HTMLButtonElement>('add-element-btn');
const wrapArrayBtn = must<HTMLButtonElement>('wrap-array-btn');
const wrapObjectBtn = must<HTMLButtonElement>('wrap-object-btn');
const changeTypeBtn = must<HTMLButtonElement>('change-type-btn');
const deleteBtn = must<HTMLButtonElement>('delete-btn');
const unwrapBtn = must<HTMLButtonElement>('unwrap-btn');

const inlineFormEl = must<HTMLDivElement>('toolbar-inline-form');
const inlineLabelEl = must<HTMLSpanElement>('inline-form-label');
const inlineInputEl = must<HTMLInputElement>('toolbar-inline-input');
const inlineSubmitEl = must<HTMLButtonElement>('toolbar-inline-submit');
const inlineCancelEl = must<HTMLButtonElement>('toolbar-inline-cancel');

// Protocol-based tree adapter
const adapter = new HTMLAdapter(treeEl, errorsEl);

let inlineMode: InlineMode = null;
let lastText = '';
let syncScheduled = false;
let suppressInput = false;

function must<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) {
    throw new Error(`Missing element #${id}`);
  }
  return element as T;
}

// Map ViewNode kind_tag to the old toolbar kind categories
function kindTagToToolbarKind(kindTag: string): string {
  switch (kindTag) {
    case 'Object': return 'object';
    case 'Array': return 'array';
    case 'String': return 'string';
    case 'Number': return 'number';
    case 'Bool': return 'bool';
    case 'Null': return 'null';
    case 'Error': return 'error';
    default: return 'other';
  }
}

function scheduleTextSync() {
  if (syncScheduled || suppressInput) return;
  syncScheduled = true;
  requestAnimationFrame(() => {
    syncScheduled = false;
    syncTextToModel();
  });
}

function syncTextToModel() {
  if (suppressInput) return;
  const nextText = editorEl.textContent ?? '';
  if (nextText !== lastText) {
    crdt.json_set_text(handle, nextText);
    lastText = nextText;
  }
  refresh();
}

function setEditorText(text: string) {
  suppressInput = true;
  editorEl.textContent = text;
  suppressInput = false;
  lastText = text;
}

function syncTextFromModel() {
  const text = crdt.json_get_text(handle);
  if ((editorEl.textContent ?? '') !== text) {
    setEditorText(text);
  } else {
    lastText = text;
  }
}

/** Compute and apply view patches from the protocol. */
function refresh() {
  const patchesJson = crdt.json_compute_view_patches_json(handle);
  const patches: ViewPatch[] = JSON.parse(patchesJson);
  adapter.applyPatches(patches);

  // Restore selection if it was lost (e.g. after FullTree rebuild)
  const selectedId = adapter.getSelectedNodeId();
  if (selectedId !== null && !adapter.findNode(selectedId)) {
    // Selected node no longer exists — select root instead
    const root = adapter.getTree();
    if (root) {
      adapter.applyPatches([{ type: 'SelectNode', node_id: root.id }]);
    }
  }

  updateToolbarState();
}

function updateToolbarState() {
  const selectedId = adapter.getSelectedNodeId();
  const selectedNode = selectedId !== null ? adapter.findNode(selectedId) : null;
  const kind = selectedNode ? kindTagToToolbarKind(selectedNode.kind_tag) : 'other';
  const hasSelection = selectedNode !== null;
  const root = adapter.getTree();
  const isRoot = hasSelection && selectedId === root?.id;

  addMemberBtn.disabled = kind !== 'object';
  addElementBtn.disabled = kind !== 'array';
  wrapArrayBtn.disabled = !hasSelection;
  wrapObjectBtn.disabled = !hasSelection;
  changeTypeBtn.disabled = !hasSelection;
  deleteBtn.disabled = !hasSelection || Boolean(isRoot);
  unwrapBtn.disabled = !(kind === 'object' || kind === 'array');
}

function showInlineForm(mode: InlineMode) {
  inlineMode = mode;
  inlineFormEl.classList.add('visible');

  if (mode === 'add-member') {
    inlineLabelEl.textContent = 'Member key:';
    inlineInputEl.placeholder = 'name';
    inlineInputEl.value = '';
  } else if (mode === 'wrap-object') {
    inlineLabelEl.textContent = 'Wrapper key:';
    inlineInputEl.placeholder = 'wrapper';
    inlineInputEl.value = 'wrapper';
  } else if (mode === 'change-type') {
    inlineLabelEl.textContent = 'New type:';
    inlineInputEl.placeholder = 'string | number | bool | null | array | object';
    inlineInputEl.value = '';
  }

  inlineInputEl.focus();
  inlineInputEl.select();
}

function hideInlineForm() {
  inlineMode = null;
  inlineFormEl.classList.remove('visible');
  inlineLabelEl.textContent = '';
  inlineInputEl.value = '';
}

function applyEdit(op: Record<string, unknown>) {
  const result = crdt.json_apply_edit(handle, JSON.stringify(op), Date.now());
  syncTextFromModel();
  refresh();

  if (result !== 'ok') {
    // Prepend the error to the diagnostics list
    const item = document.createElement('li');
    item.className = 'error-item';
    item.textContent = result;
    errorsEl.prepend(item);
  }
}

function submitInlineAction() {
  const selectedId = adapter.getSelectedNodeId();
  if (selectedId === null || !inlineMode) return;

  const value = inlineInputEl.value.trim();
  if (!value) {
    inlineInputEl.focus();
    return;
  }

  if (inlineMode === 'add-member') {
    applyEdit({ op: 'AddMember', object_id: selectedId, key: value });
  } else if (inlineMode === 'wrap-object') {
    applyEdit({ op: 'WrapInObject', node_id: selectedId, key: value });
  } else if (inlineMode === 'change-type') {
    if (!VALID_TYPES.has(value)) {
      inlineInputEl.focus();
      return;
    }
    applyEdit({ op: 'ChangeType', node_id: selectedId, new_type: value });
  }

  hideInlineForm();
}

// Wire up intent callback for selection
adapter.onIntent((intent) => {
  if (intent.type === 'SelectNode') {
    hideInlineForm();
    updateToolbarState();
  }
});

editorEl.addEventListener('input', scheduleTextSync);

addMemberBtn.addEventListener('click', () => {
  if (!addMemberBtn.disabled) showInlineForm('add-member');
});

addElementBtn.addEventListener('click', () => {
  const selectedId = adapter.getSelectedNodeId();
  if (selectedId !== null && !addElementBtn.disabled) {
    hideInlineForm();
    applyEdit({ op: 'AddElement', array_id: selectedId });
  }
});

wrapArrayBtn.addEventListener('click', () => {
  const selectedId = adapter.getSelectedNodeId();
  if (selectedId !== null && !wrapArrayBtn.disabled) {
    hideInlineForm();
    applyEdit({ op: 'WrapInArray', node_id: selectedId });
  }
});

wrapObjectBtn.addEventListener('click', () => {
  if (!wrapObjectBtn.disabled) showInlineForm('wrap-object');
});

changeTypeBtn.addEventListener('click', () => {
  if (!changeTypeBtn.disabled) showInlineForm('change-type');
});

deleteBtn.addEventListener('click', () => {
  const selectedId = adapter.getSelectedNodeId();
  if (selectedId !== null && !deleteBtn.disabled) {
    hideInlineForm();
    applyEdit({ op: 'Delete', node_id: selectedId });
  }
});

unwrapBtn.addEventListener('click', () => {
  const selectedId = adapter.getSelectedNodeId();
  if (selectedId !== null && !unwrapBtn.disabled) {
    hideInlineForm();
    applyEdit({ op: 'Unwrap', node_id: selectedId });
  }
});

inlineSubmitEl.addEventListener('click', submitInlineAction);
inlineCancelEl.addEventListener('click', hideInlineForm);
inlineInputEl.addEventListener('keydown', (event) => {
  if (event.key === 'Enter') {
    event.preventDefault();
    submitInlineAction();
  } else if (event.key === 'Escape') {
    event.preventDefault();
    hideInlineForm();
  }
});

document.querySelectorAll<HTMLButtonElement>('.example-btn').forEach((button) => {
  button.addEventListener('click', () => {
    const example = button.dataset.example ?? EXAMPLE_FALLBACK;
    crdt.json_set_text(handle, example);
    syncTextFromModel();
    hideInlineForm();
    refresh();
  });
});

window.addEventListener('beforeunload', () => {
  adapter.destroy();
  crdt.destroy_json_editor(handle);
});

const initialText = crdt.json_get_text(handle);
if (initialText.trim()) {
  setEditorText(initialText);
} else {
  crdt.json_set_text(handle, EXAMPLE_FALLBACK);
  setEditorText(EXAMPLE_FALLBACK);
}

refresh();
