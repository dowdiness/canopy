import * as crdt from '@moonbit/crdt-json';
import { HTMLAdapter } from '@canopy/editor-adapter/html-adapter';
import { DecorationOverlay } from './decoration-overlay';
import type { Decoration } from '@canopy/editor-adapter/types';
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
const formatBtn = must<HTMLButtonElement>('format-btn');
const unwrapBtn = must<HTMLButtonElement>('unwrap-btn');

const inlineFormEl = must<HTMLDivElement>('toolbar-inline-form');
const inlineLabelEl = must<HTMLSpanElement>('inline-form-label');
const inlineInputEl = must<HTMLInputElement>('toolbar-inline-input');
const inlineSubmitEl = must<HTMLButtonElement>('toolbar-inline-submit');
const inlineCancelEl = must<HTMLButtonElement>('toolbar-inline-cancel');

// Protocol-based tree adapter
const adapter = new HTMLAdapter(treeEl, errorsEl, true);

const decorationOverlay = new DecorationOverlay(editorEl);

let inlineMode: InlineMode = null;
let lastText = '';
let syncScheduled = false;
let pendingNodeId: number | null = null;
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

const ROLE_TO_CSS_CLASS: Record<string, string> = {
  'property-key': 'json-role-property-key',
  'string-value': 'json-role-string-value',
  'number-literal': 'json-role-number-literal',
  'boolean-literal': 'json-role-boolean-literal',
  'null-literal': 'json-role-null-literal',
  'punctuation': 'json-role-punctuation',
  'error': 'json-role-error',
};

export interface JsonRoleSpanData {
  start: number;
  end: number;
  role: string;
}

/** Fetch current JSON role spans from the MoonBit parser and return as typed data. */
export function getJsonRoleSpans(): JsonRoleSpanData[] {
  const raw = crdt.json_get_role_spans_json(handle);
  try {
    return JSON.parse(raw) as JsonRoleSpanData[];
  } catch {
    return [];
  }
}

/** Convert role span data to Decoration[] for the overlay. */
function roleSpansToDecorations(spans: JsonRoleSpanData[]): Decoration[] {
  return spans
    .filter(s => s.end > s.start)
    .map(s => ({
      from: s.start,
      to: s.end,
      css_class: ROLE_TO_CSS_CLASS[s.role] ?? '',
      data: null,
      widget: false,
    }));
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
  const roleSpans = getJsonRoleSpans();
  decorationOverlay.applyDecorations(roleSpansToDecorations(roleSpans));
  updateToolbarState();
  refreshInlineControls();
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

/** Create an inline action button with a data-action attribute. */
function createActionBtn(label: string, action: string, title: string): HTMLButtonElement {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'node-action-btn';
  btn.setAttribute('data-action', action);
  btn.title = title;
  btn.textContent = label;
  return btn;
}

/**
 * Inject per-row inline controls (action buttons, type dropdown) into tree nodes.
 * Called after every refresh. Removes stale controls and re-creates from current DOM.
 */
function refreshInlineControls() {
  // Remove stale controls
  treeEl.querySelectorAll('.node-actions, .node-type-select').forEach(el => el.remove());

  for (const nodeEl of treeEl.querySelectorAll<HTMLElement>('.tree-node')) {
    const nodeKind = nodeEl.getAttribute('data-node-kind');
    if (!nodeKind) continue;
    const nodeId = Number(nodeEl.getAttribute('data-node-id'));
    if (isNaN(nodeId)) continue;
    const rowEl = nodeEl.querySelector(':scope > .node-row');
    if (!rowEl) continue;

    const kind = kindTagToToolbarKind(nodeKind);
    const isContainer = kind === 'object' || kind === 'array';
    const isRoot = nodeEl.classList.contains('root');
    const actions = document.createElement('span');
    actions.className = 'node-actions';

    // Type dropdown for value (scalar) nodes
    if (!isContainer && kind !== 'error' && kind !== 'other') {
      const select = document.createElement('select');
      select.className = 'node-type-select';
      for (const t of ['null', 'bool', 'number', 'string', 'array', 'object']) {
        const opt = document.createElement('option');
        opt.value = t;
        opt.textContent = t;
        if (t === kind) opt.selected = true;
        select.appendChild(opt);
      }
      select.addEventListener('change', () => {
        applyEdit({ op: 'ChangeType', node_id: nodeId, new_type: select.value });
      });
      actions.appendChild(select);
    }

    // Add-child button (containers only)
    if (kind === 'object') {
      const btn = createActionBtn('+', 'add-member', 'Add member key');
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        showInlineForm('add-member', nodeId);
      });
      actions.appendChild(btn);
    } else if (kind === 'array') {
      const btn = createActionBtn('+', 'add-element', 'Add element');
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        hideInlineForm();
        applyEdit({ op: 'AddElement', array_id: nodeId });
      });
      actions.appendChild(btn);
    }

    // Unwrap (containers only)
    if (isContainer) {
      const btn = createActionBtn('↩', 'unwrap', 'Unwrap');
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        hideInlineForm();
        applyEdit({ op: 'Unwrap', node_id: nodeId });
      });
      actions.appendChild(btn);
    }

    // Wrap buttons
    if (kind !== 'error' && kind !== 'other') {
      const wrapArray = createActionBtn('⇥', 'wrap-array', 'Wrap in array');
      wrapArray.addEventListener('click', (e) => {
        e.stopPropagation();
        hideInlineForm();
        applyEdit({ op: 'WrapInArray', node_id: nodeId });
      });
      actions.appendChild(wrapArray);

      const wrapObj = createActionBtn('{}', 'wrap-object', 'Wrap in object');
      wrapObj.addEventListener('click', (e) => {
        e.stopPropagation();
        showInlineForm('wrap-object', nodeId);
      });
      actions.appendChild(wrapObj);
    }

    // Delete (never on root)
    if (!isRoot) {
      const btn = createActionBtn('×', 'delete', 'Delete');
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        hideInlineForm();
        applyEdit({ op: 'Delete', node_id: nodeId });
      });
      actions.appendChild(btn);
    }

    rowEl.appendChild(actions);
  }
}

function showInlineForm(mode: InlineMode, targetId?: number | null) {
  pendingNodeId = targetId ?? null;
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

  // Scroll the target row into view
  const scrollId = pendingNodeId ?? adapter.getSelectedNodeId();
  if (scrollId !== null) {
    const rowEl = treeEl.querySelector(`[data-node-id="${scrollId}"] > .node-row`);
    if (rowEl) rowEl.scrollIntoView({ block: 'nearest' });
  }

  inlineInputEl.focus();
  inlineInputEl.select();
}

function hideInlineForm() {
  inlineMode = null;
  pendingNodeId = null;
  inlineFormEl.classList.remove('visible');
  inlineLabelEl.textContent = '';
  inlineInputEl.value = '';
}


/** Pretty-print the JSON text in the editor. Shows an error if invalid. */
function formatJson() {
  const text = editorEl.textContent ?? '';
  if (!text.trim()) return;
  try {
    const parsed = JSON.parse(text);
    const formatted = JSON.stringify(parsed, null, 2);
    // Set the CRDT model directly, then sync back to DOM + tree
    crdt.json_set_text(handle, formatted);
    syncTextFromModel();
    refresh();
  } catch (_e) {
    const item = document.createElement('li');
    item.className = 'error-item';
    item.textContent = 'Invalid JSON — cannot format';
    errorsEl.prepend(item);
  }
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
  // Prefer pendingNodeId (set by row-level button) over selected node
  const targetId = pendingNodeId ?? adapter.getSelectedNodeId();
  if (targetId === null || !inlineMode) return;

  const value = inlineInputEl.value.trim();
  if (!value) {
    inlineInputEl.focus();
    return;
  }

  if (inlineMode === 'add-member') {
    applyEdit({ op: 'AddMember', object_id: targetId, key: value });
  } else if (inlineMode === 'wrap-object') {
    applyEdit({ op: 'WrapInObject', node_id: targetId, key: value });
  } else if (inlineMode === 'change-type') {
    if (!VALID_TYPES.has(value)) {
      inlineInputEl.focus();
      return;
    }
    applyEdit({ op: 'ChangeType', node_id: targetId, new_type: value });
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

formatBtn.addEventListener('click', () => {
  hideInlineForm();
  formatJson();
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
    adapter.resetCollapseState();
    refresh();
  });
});

window.addEventListener('beforeunload', () => {
  adapter.destroy();
  decorationOverlay.dispose();
  crdt.destroy_json_editor(handle);
});

const initialText = crdt.json_get_text(handle);
if (initialText.trim()) {
  setEditorText(initialText);
} else {
  crdt.json_set_text(handle, EXAMPLE_FALLBACK);
  setEditorText(EXAMPLE_FALLBACK);
}

adapter.resetCollapseState();
refresh();


