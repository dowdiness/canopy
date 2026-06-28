import * as crdt from '@moonbit/crdt-json';
import { HTMLAdapter } from '@canopy/editor-adapter/html-adapter';
import { DecorationOverlay } from './decoration-overlay';
import type { Decoration } from '@canopy/editor-adapter/types';
import type { ViewPatch, ViewNode } from '@canopy/editor-adapter/types';

const EXAMPLE_FALLBACK = '{"hello": "world"}';

const agentId = `json-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
const handle = crdt.create_json_editor(agentId);

const editorEl = must<HTMLDivElement>('json-input');
const errorsEl = must<HTMLUListElement>('parse-errors');
const treeEl = must<HTMLDivElement>('tree-view');
const formatBtn = must<HTMLButtonElement>('format-btn');

const viewEl = document.getElementById('json-editor-view')!;
const gutterEl = document.getElementById('json-gutter');

const patchLogEl = must<HTMLDivElement>('patch-log-body');
const patchLogHeaderEl = must<HTMLDivElement>('patch-log-header');
const patchLogToggleEl = must<HTMLSpanElement>('patch-log-toggle');
const patchLogCountEl = must<HTMLSpanElement>('patch-log-count');
const patchLogEmptyEl = must<HTMLDivElement>('patch-log-empty');
const structToggleBtn = must<HTMLButtonElement>('struct-toggle-btn');

// Protocol-based tree adapter
const adapter = new HTMLAdapter(treeEl, errorsEl, true);
const decorationOverlay = new DecorationOverlay(editorEl);

const collapsedNodes = new Set<number>();
let structMode = false;

function must<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing element #${id}`);
  return element as T;
}

// ── Role spans ──────────────────────────────────────

const ROLE_TO_CSS_CLASS: Record<string, string> = {
  'property-key': 'json-role-property-key',
  'string-value': 'json-role-string-value',
  'number-literal': 'json-role-number-literal',
  'boolean-literal': 'json-role-boolean-literal',
  'null-literal': 'json-role-null-literal',
  'punctuation': 'json-role-punctuation',
  'error': 'json-role-error',
};

export interface JsonRoleSpanData { start: number; end: number; role: string }

export function getJsonRoleSpans(): JsonRoleSpanData[] {
  const raw = crdt.json_get_role_spans_json(handle);
  try { return JSON.parse(raw) as JsonRoleSpanData[]; }
  catch { return []; }
}

declare global {
  interface Window { getJsonRoleSpans: () => JsonRoleSpanData[]; }
}
window.getJsonRoleSpans = getJsonRoleSpans;

function roleSpansToDecorations(spans: JsonRoleSpanData[]): Decoration[] {
  return spans.filter(s => s.end > s.start).map(s => ({
    from: s.start, to: s.end,
    css_class: ROLE_TO_CSS_CLASS[s.role] ?? '',
    data: null, widget: false,
  }));
}

// ── Edit log ─────────────────────────────────────────

interface EditLogEntry { op: Record<string, unknown>; ts: number; ok: boolean; error?: string }

const OP_CSS_CLASS: Record<string, string> = {
  Delete: 'Delete', AddMember: 'AddMember', AddElement: 'AddElement',
  WrapInArray: 'WrapInArray', WrapInObject: 'WrapInObject',
  Unwrap: 'Unwrap', ChangeType: 'ChangeType', RenameKey: 'RenameKey', CommitEdit: 'CommitEdit',
};

function formatTimestamp(ts: number): string {
  const d = new Date(ts);
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function formatEntryParams(op: Record<string, unknown>): string {
  const parts: string[] = [];
  for (const [key, value] of Object.entries(op)) {
    if (key === 'op') continue;
    parts.push(typeof value === 'string' ? `${key}="${value}"` : `${key}=${String(value)}`);
  }
  return parts.join('  ');
}

function fetchEditLog(): void {
  const raw = crdt.json_get_edit_log(handle);
  let entries: EditLogEntry[];
  try { entries = JSON.parse(raw) as EditLogEntry[]; } catch { entries = []; }
  patchLogCountEl.textContent = String(entries.length);
  if (entries.length === 0) {
    patchLogEmptyEl.classList.remove('hidden');
    patchLogEl.replaceChildren(patchLogEmptyEl);
    return;
  }
  patchLogEmptyEl.classList.add('hidden');
  const fragment = document.createDocumentFragment();
  for (const entry of entries) {
    const opName = String(entry.op.op ?? '?');
    const div = document.createElement('div');
    div.className = 'patch-entry';
    const timeEl = document.createElement('span');
    timeEl.className = 'patch-entry-time';
    timeEl.textContent = formatTimestamp(entry.ts);
    const opEl = document.createElement('span');
    opEl.className = `patch-entry-op ${OP_CSS_CLASS[opName] ?? ''}`;
    opEl.textContent = opName;
    const paramsEl = document.createElement('span');
    paramsEl.className = 'patch-entry-params';
    paramsEl.textContent = formatEntryParams(entry.op);
    const statusEl = document.createElement('span');
    if (entry.ok) { statusEl.className = 'patch-entry-ok'; statusEl.textContent = '✓'; }
    else { statusEl.className = 'patch-entry-err'; statusEl.textContent = entry.error ? `✗ ${entry.error}` : '✗'; }
    div.append(timeEl, opEl, paramsEl, statusEl);
    fragment.append(div);
  }
  patchLogEl.replaceChildren(fragment);
}

// ── Gutter ───────────────────────────────────────────

function findTextPosition(offset: number): { node: Text; offset: number } | null {
  const walker = document.createTreeWalker(editorEl, NodeFilter.SHOW_TEXT);
  let remaining = offset;
  let lastText: Text | null = null;
  for (let node = walker.nextNode() as Text | null; node; node = walker.nextNode() as Text | null) {
    lastText = node;
    const length = node.data.length;
    if (remaining <= length) return { node, offset: remaining };
    remaining -= length;
  }
  if (lastText && remaining === 0) return { node: lastText, offset: lastText.data.length };
  return null;
}

function renderGutter() {
  if (!gutterEl) return;
  gutterEl.replaceChildren();
  const root = adapter.getTree();
  if (!root) return;
  const widgets: { nodeId: number; action: 'add-member' | 'add-element'; offset: number }[] = [];
  const walk = (node: ViewNode) => {
    const [start] = node.text_range;
    if (node.kind_tag === 'Object') widgets.push({ nodeId: node.id, action: 'add-member', offset: start });
    else if (node.kind_tag === 'Array') widgets.push({ nodeId: node.id, action: 'add-element', offset: start });
    for (const child of node.children) walk(child);
  };
  walk(root);
  const editorRect = editorEl.getBoundingClientRect();
  for (const w of widgets) {
    const pos = findTextPosition(w.offset);
    if (!pos) continue;
    const range = document.createRange();
    range.setStart(pos.node, pos.offset);
    range.setEnd(pos.node, Math.min(pos.offset + 1, pos.node.data.length));
    const rects = Array.from(range.getClientRects());
    range.detach();
    if (rects.length === 0) continue;
    const y = rects[0].top - editorRect.top + editorEl.scrollTop;
    const btn = document.createElement('button');
    btn.className = 'gutter-btn';
    btn.textContent = '+';
    btn.title = w.action === 'add-member' ? 'Add member' : 'Add element';
    btn.style.top = y + 'px';
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      applyEdit(w.action === 'add-member' ? { op: 'AddMember', object_id: w.nodeId, key: 'key' } : { op: 'AddElement', array_id: w.nodeId });
    });
    gutterEl.appendChild(btn);
  }
}

// ── Structured view ──────────────────────────────────

function renderStructuredView() {
  const root = adapter.getTree();
  if (!root) { viewEl.innerHTML = '<div class="tree-empty">No data</div>'; return; }
  viewEl.replaceChildren(renderTreeNode(root, true));
}

function renderTreeNode(node: ViewNode, isRoot: boolean): HTMLElement {
  const wrap = document.createElement('div');
  wrap.className = 'tree-node' + (isRoot ? ' root' : '');
  wrap.dataset.nodeId = String(node.id);
  wrap.dataset.nodeKind = node.kind_tag;

  const row = document.createElement('div');
  row.className = 'node-row';
  const isContainer = node.kind_tag === 'Object' || node.kind_tag === 'Array';
  const body = isContainer ? document.createElement('div') : null;
  if (body) body.className = 'node-children';

  if (isContainer) {
    const toggle = document.createElement('span');
    toggle.className = 'node-toggle';
    const isCollapsed = collapsedNodes.has(node.id);
    toggle.textContent = isCollapsed ? '▶' : '▼';
    toggle.setAttribute('role', 'button');
    toggle.setAttribute('tabindex', '0');
    if (body) body.style.display = isCollapsed ? 'none' : '';
    const doToggle = () => {
      if (collapsedNodes.has(node.id)) { collapsedNodes.delete(node.id); toggle.textContent = '▼'; if (body) body.style.display = ''; }
      else { collapsedNodes.add(node.id); toggle.textContent = '▶'; if (body) body.style.display = 'none'; }
    };
    toggle.addEventListener('click', (e) => { e.stopPropagation(); doToggle(); });
    toggle.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); doToggle(); } });
    row.appendChild(toggle);

    const tag = document.createElement('span');
    tag.className = 'node-tag ' + node.kind_tag.toLowerCase();
    tag.textContent = node.kind_tag;
    row.appendChild(tag);

    const count = node.children.length;
    if (count > 0) {
      const badge = document.createElement('span');
      badge.className = 'node-count';
      badge.textContent = String(count);
      row.appendChild(badge);
    }

    const actions = document.createElement('span');
    actions.className = 'node-actions';
    const addBtn = document.createElement('button');
    addBtn.className = 'node-action-btn';
    addBtn.textContent = '+';
    addBtn.title = node.kind_tag === 'Array' ? 'Add element' : 'Add member';
    addBtn.dataset.action = node.kind_tag === 'Array' ? 'add-element' : 'add-member';
    addBtn.addEventListener('click', (e) => { e.stopPropagation(); applyEdit(node.kind_tag === 'Array' ? { op: 'AddElement', array_id: node.id } : { op: 'AddMember', object_id: node.id, key: 'key' }); });
    actions.appendChild(addBtn);
    const delBtn = document.createElement('button');
    delBtn.className = 'node-action-btn';
    delBtn.textContent = '×';
    delBtn.title = 'Delete';
    delBtn.dataset.action = 'delete';
    delBtn.addEventListener('click', (e) => { e.stopPropagation(); applyEdit({ op: 'Delete', node_id: node.id }); });
    actions.appendChild(delBtn);
    const wrapArrBtn = document.createElement('button');
    wrapArrBtn.className = 'node-action-btn';
    wrapArrBtn.textContent = '[]';
    wrapArrBtn.title = 'Wrap in array';
    wrapArrBtn.dataset.action = 'wrap-array';
    wrapArrBtn.addEventListener('click', (e) => { e.stopPropagation(); applyEdit({ op: 'WrapInArray', node_id: node.id }); });
    actions.appendChild(wrapArrBtn);
    const wrapObjBtn = document.createElement('button');
    wrapObjBtn.className = 'node-action-btn';
    wrapObjBtn.textContent = '{}';
    wrapObjBtn.title = 'Wrap in object';
    wrapObjBtn.dataset.action = 'wrap-object';
    wrapObjBtn.addEventListener('click', (e) => { e.stopPropagation(); applyEdit({ op: 'WrapInObject', node_id: node.id, key: 'key' }); });
    actions.appendChild(wrapObjBtn);
    if (node.children.length > 0) {
      const unwrapBtn = document.createElement('button');
      unwrapBtn.className = 'node-action-btn';
      unwrapBtn.textContent = '⇔';
      unwrapBtn.title = 'Unwrap';
      unwrapBtn.addEventListener('click', (e) => { e.stopPropagation(); applyEdit({ op: 'Unwrap', node_id: node.id }); });
      actions.appendChild(unwrapBtn);
    }
    row.appendChild(actions);

    const idSpan = document.createElement('span');
    idSpan.className = 'node-id';
    idSpan.textContent = '#' + node.id;
    row.appendChild(idSpan);
  } else {
    // Scalar value
    const kind = node.kind_tag.toLowerCase();
    const tag = document.createElement('span');
    tag.className = 'node-tag ' + kind;
    tag.textContent = node.text ?? node.label ?? '?';
    if (!tag.textContent || tag.textContent === '""') { tag.setAttribute('data-empty', 'true'); tag.textContent = ''; }
    tag.dataset.nodeId = String(node.id);
    tag.dataset.kind = node.kind_tag;
    tag.style.cursor = 'text';
    tag.addEventListener('click', (e) => { e.stopPropagation(); startInlineEdit(tag, node); });
    row.appendChild(tag);

    // Type switch
    const select = document.createElement('select');
    select.className = 'node-type-select';
    for (const t of ['string', 'number', 'bool', 'null', 'array', 'object']) {
      const opt = document.createElement('option');
      opt.value = t; opt.textContent = t; if (t === kind) opt.selected = true;
      select.appendChild(opt);
    }
    select.addEventListener('change', () => applyEdit({ op: 'ChangeType', node_id: node.id, new_type: select.value }));
    row.appendChild(select);

    const delBtn = document.createElement('button');
    delBtn.className = 'node-action-btn';
    delBtn.textContent = '×';
    delBtn.title = 'Delete';
    delBtn.dataset.action = 'delete';
    delBtn.addEventListener('click', (e) => { e.stopPropagation(); applyEdit({ op: 'Delete', node_id: node.id }); });
    row.appendChild(delBtn);
    const idSpan = document.createElement('span');
    idSpan.className = 'node-id';
    idSpan.textContent = '#' + node.id;
    row.appendChild(idSpan);
  }

  wrap.appendChild(row);
  if (body) {
    const sourceText = crdt.json_get_text(handle);
    for (let i = 0; i < node.children.length; i++) {
      const child = node.children[i];
      const childRow = renderTreeNode(child, false);
      const childRowEl = childRow.querySelector(':scope > .node-row');
      if (childRowEl && node.kind_tag === 'Object') {
        let keyName = `[${i}]`;
        const keySpan = node.token_spans.find(s => s.role === `key:${i}`);
        if (keySpan) {
          keyName = sourceText.slice(keySpan.start, keySpan.end);
          if (keyName.startsWith('"') && keyName.endsWith('"')) keyName = keyName.slice(1, -1);
        }
        const parentId = node.id;
        const keyIdx = i;
        const keyEl = document.createElement('span');
        keyEl.className = 'node-key';
        keyEl.textContent = '"' + keyName + '":';
        keyEl.style.cursor = 'text';
        keyEl.addEventListener('click', (e) => {
          e.stopPropagation();
          const input = document.createElement('input');
          input.type = 'text';
          input.value = keyName;
          input.className = 'json-inline-input';
          keyEl.replaceChildren(input);
          input.focus();
          input.select();
          const finish = (commit: boolean) => {
            if (commit) {
              const val = input.value.trim();
              if (val && val !== keyName) {
                applyEdit({ op: 'RenameKey', object_id: parentId, key_index: keyIdx, new_key: val });
              }
            }
            keyEl.textContent = '"' + keyName + '":';
          };
          input.addEventListener('blur', () => finish(true));
          input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') { e.preventDefault(); finish(true); }
            else if (e.key === 'Escape') { e.preventDefault(); finish(false); }
          });
        });
        const toggle = childRowEl.querySelector('.node-toggle');
        if (toggle) toggle.after(keyEl);
        else childRowEl.insertBefore(keyEl, childRowEl.firstChild);
      }
      body.appendChild(childRow);
    }
    wrap.appendChild(body);
  }
  return wrap;
}

function startInlineEdit(span: HTMLElement, node: ViewNode) {
  const rawVal = node.text ?? node.label ?? '';
  const display = node.kind_tag === 'String' && rawVal.startsWith('"') && rawVal.endsWith('"') ? rawVal.slice(1, -1) : rawVal;
  const input = document.createElement('input');
  input.type = 'text';
  input.value = display;
  input.className = 'json-inline-input';
  span.replaceChildren(input);
  input.focus();
  input.select();
  const finish = (commit: boolean) => {
    if (commit) {
      const val = input.value.trim();
      if (val !== display) {
        // Validate as JSON; if invalid, wrap as string
        let committed: string;
        try { JSON.parse(val); committed = val; }
        catch { committed = '"' + val + '"'; }
        applyEdit({ op: 'CommitEdit', node_id: node.id, new_value: committed });
      }
    }
    span.removeAttribute('data-empty');
    if (!display) { span.setAttribute('data-empty', 'true'); span.textContent = ''; }
    else { span.textContent = rawVal; }
  };
  input.addEventListener('blur', () => finish(true));
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); finish(true); }
    else if (e.key === 'Escape') { e.preventDefault(); finish(false); }
  });
}

// ── Refresh ──────────────────────────────────────────

function refresh() {
  // Clear stale errors from previous failed edits
  errorsEl.replaceChildren();

  const patchesJson = crdt.json_compute_view_patches_json(handle);
  const patches: ViewPatch[] = JSON.parse(patchesJson);
  adapter.applyPatches(patches);
  const selectedId = adapter.getSelectedNodeId();
  if (selectedId !== null && !adapter.findNode(selectedId)) {
    const root = adapter.getTree();
    if (root) adapter.applyPatches([{ type: 'SelectNode', node_id: root.id }]);
  }
  const roleSpans = getJsonRoleSpans();
  decorationOverlay.applyDecorations(roleSpansToDecorations(roleSpans));
  renderGutter();
  if (structMode) renderStructuredView();
  // Show errors panel only when there are actual errors
  const errorsPanel = document.getElementById('errors-panel');
  if (errorsPanel) {
    errorsPanel.style.display = errorsEl.querySelector('.error-item') ? '' : 'none';
  }
}

// ── Edit & format ────────────────────────────────────

function applyEdit(op: Record<string, unknown>) {
  const result = crdt.json_apply_edit(handle, JSON.stringify(op), Date.now());
  if (result !== 'ok') {
    const item = document.createElement('li');
    item.className = 'error-item';
    item.textContent = result;
    errorsEl.prepend(item);
  }
  syncTextFromModel();
  refresh();
  fetchEditLog();
}

function formatJson() {
  const text = editorEl.textContent ?? '';
  if (!text.trim()) return;
  try {
    const parsed = JSON.parse(text);
    const formatted = JSON.stringify(parsed, null, 2);
    crdt.json_set_text(handle, formatted);
    syncTextFromModel();
    refresh();
  } catch {
    const item = document.createElement('li');
    item.className = 'error-item';
    item.textContent = 'Invalid JSON';
    errorsEl.prepend(item);
  }
}

function syncTextFromModel() {
  const text = crdt.json_get_text(handle);
  if ((editorEl.textContent ?? '') !== text) editorEl.textContent = text;
}

let syncFrame: number | null = null;
editorEl.addEventListener('input', () => {
  if (syncFrame !== null) return;
  syncFrame = requestAnimationFrame(() => {
    syncFrame = null;
    if (!structMode) {
      const text = editorEl.textContent ?? '';
      if (text !== crdt.json_get_text(handle)) {
        crdt.json_set_text(handle, text);
        refresh();
      }
    }
  });
});

// ── Mode toggle ──────────────────────────────────────

structToggleBtn.addEventListener('click', () => {
  structMode = !structMode;
  structToggleBtn.textContent = structMode ? '📝 Raw' : '▦ Structured';
  structToggleBtn.classList.toggle('active', structMode);
  viewEl.style.display = structMode ? '' : 'none';
  editorEl.style.display = structMode ? 'none' : '';
  if (gutterEl) gutterEl.style.display = structMode ? 'none' : '';
  formatBtn.disabled = structMode;
  if (structMode) renderStructuredView();
  else { syncTextFromModel(); refresh(); }
});

// ── Event listeners ──────────────────────────────────

let gutterScrollFrame: number | null = null;
editorEl.addEventListener('scroll', () => {
  if (gutterScrollFrame !== null) return;
  gutterScrollFrame = requestAnimationFrame(() => {
    gutterScrollFrame = null;
    if (!structMode) renderGutter();
  });
});

formatBtn.addEventListener('click', formatJson);

document.querySelectorAll<HTMLButtonElement>('.example-btn').forEach((button) => {
  button.addEventListener('click', () => {
    const example = button.dataset.example ?? EXAMPLE_FALLBACK;
    crdt.json_set_text(handle, example);
    editorEl.textContent = example;
    adapter.resetCollapseState();
    refresh();
  });
});

// Patch log collapse toggle
patchLogHeaderEl.setAttribute('role', 'button');
patchLogHeaderEl.setAttribute('tabindex', '0');
patchLogHeaderEl.setAttribute('aria-expanded', 'true');
patchLogHeaderEl.setAttribute('aria-controls', 'patch-log-body');
function togglePatchLog() {
  const isHidden = patchLogEl.classList.toggle('hidden');
  patchLogToggleEl.classList.toggle('collapsed');
  patchLogHeaderEl.setAttribute('aria-expanded', String(!isHidden));
}
patchLogHeaderEl.addEventListener('click', togglePatchLog);
patchLogHeaderEl.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); togglePatchLog(); }
});

window.addEventListener('beforeunload', () => {
  adapter.destroy();
  crdt.destroy_json_editor(handle);
});

// ── Init ──────────────────────────────────────────────

const initialText = crdt.json_get_text(handle);
if (initialText.trim()) editorEl.textContent = initialText;
else {
  crdt.json_set_text(handle, EXAMPLE_FALLBACK);
  editorEl.textContent = EXAMPLE_FALLBACK;
}
adapter.resetCollapseState();
refresh();
fetchEditLog();
