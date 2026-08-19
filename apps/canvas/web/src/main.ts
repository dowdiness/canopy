import { adaptMoonBitModule } from '@canopy/editor-adapter/moonbit-result';
import * as cmCommands from '@codemirror/commands';
import * as cmState from '@codemirror/state';
import * as cmView from '@codemirror/view';
import {
  GraphAdapter,
  type CanvasModule,
  type NodeData,
  type NodeParamData,
  type PortCompatibility,
  type PortDef,
  type RenderState,
  type SourceGraphOperationResult,
  type Tagged,
} from './graph-adapter';

export { GraphAdapter } from './graph-adapter';
export type {
  GraphOperation,
  RenderState,
  SourceGraphOperationResult,
} from './graph-adapter';

type LibraryItem = {
  key: string;
  label: string;
  description: string;
};

type SourceDemoModule = CanvasModule &
  Required<
    Pick<
      CanvasModule,
      'sample_graph_dsl_source' |
      'mount_source_demo' |
      'mount_canvas_context_menu' |
      'dismiss_canvas_context_menu' |
      'mount_canvas_pointer_session'
    >
  >;

let adapter: GraphAdapter;
let rafPending = false;

const root       = document.getElementById('canvas-root') as HTMLDivElement;
const world      = document.getElementById('world') as HTMLDivElement;
const search     = document.getElementById('node-search') as HTMLInputElement;
const libraryEl  = document.getElementById('node-library') as HTMLDivElement;
const validation = document.getElementById('validation-list') as HTMLDivElement;
const inspectorNode = document.getElementById('inspector-node') as HTMLDivElement;
const actionStat = document.getElementById('action-stat') as HTMLSpanElement;
const nodeDivs = new Map<string, HTMLDivElement>();
let libraryCatalog: LibraryItem[] = [];


// Event admission can run before the deferred RAF render. Read the model
// synchronously so geometry is checked against the state that will consume it.
function currentRenderState(): RenderState {
  return adapter.renderState();
}

function screenToWorld(
  point: [number, number],
  state: RenderState,
): [number, number] | null {
  const { x, y, scale } = state.viewport;
  if (
    !point.every(Number.isFinite) ||
    !Number.isFinite(x) ||
    !Number.isFinite(y) ||
    !Number.isFinite(scale) ||
    scale <= 0
  ) {
    return null;
  }
  const worldPoint: [number, number] = [
    (point[0] - x) / scale,
    (point[1] - y) / scale,
  ];
  return worldPoint.every(Number.isFinite) ? worldPoint : null;
}

function portTypeName(portType: Tagged): string {
  return Array.isArray(portType) ? String(portType[0]) : String(portType);
}

function portTitle(port: PortDef): string {
  return `${port.label}: ${portTypeName(port.port_type)}`;
}



// ─── Connection compatibility (display only) ───────────────────────────────────
// Input-handle previews consume the batched `can_commit_edge` results from
// the render snapshot, so the cosmetic highlight follows the same
// authoritative commit/reject logic as pointerup without a second FFI read.

type InputCompatibility = Map<string, Map<string, boolean>>;

/** Context for the in-flight connection, resolved once per render. */
type ConnectCtx = {
  inputs: InputCompatibility;
};

function inputCompatibilityByTarget(entries: PortCompatibility[]): InputCompatibility {
  const byNode = new Map<string, Map<string, boolean>>();
  for (const entry of entries) {
    let byPort = byNode.get(entry.node_id);
    if (!byPort) {
      byPort = new Map<string, boolean>();
      byNode.set(entry.node_id, byPort);
    }
    byPort.set(entry.port_id, entry.compatible);
  }
  return byNode;
}

function inputCompatible(ctx: ConnectCtx, nodeId: string, portId: string): boolean {
  return ctx.inputs.get(nodeId)?.get(portId) === true;
}

function renderPortHandles(div: HTMLDivElement, node: NodeData, connectCtx: ConnectCtx | null): void {
  div.querySelectorAll(':scope > .handle').forEach((handle) => handle.remove());
  const addHandles = (side: 'input' | 'output', ports: PortDef[]) => {
    ports.forEach((port, index) => {
      const handle = document.createElement('div');
      handle.className = `handle ${side}`;
      handle.dataset.handle = side;
      handle.dataset.nodeId = String(node.id);
      handle.dataset.portId = port.id;
      handle.dataset.portLabel = port.label;
      handle.style.top = `${((index + 1) * 100) / (ports.length + 1)}%`;
      handle.title = `${side === 'input' ? 'Input' : 'Output'} ${portTitle(port)}`;
      handle.setAttribute('aria-label', `${node.title} ${side} ${portTitle(port)}`);
      if (connectCtx && side === 'input') {
        handle.classList.add(
          inputCompatible(connectCtx, node.id, port.id)
            ? 'compatible-target'
            : 'incompatible-target',
        );
      }
      div.appendChild(handle);
    });
  };
  addHandles('input', node.inputs);
  addHandles('output', node.outputs);
}

// ─── RAF render loop ─────────────────────────────────────────────────────────

function scheduleRender(): void {
  if (rafPending) return;
  rafPending = true;
  requestAnimationFrame(render);
}

function render(): void {
  rafPending = false;
  const state = adapter.publishRenderState();

  const { x, y, scale } = state.viewport;
  const transform = `translate(${x}px, ${y}px) scale(${scale})`;
  world.style.transform = transform;

  // Nodes ────────────────────────────────────────────────────────────────────
  const seenNodes = new Set<string>();
  const selected = new Set(state.selected_nodes ?? []);
  const invalidNodeIds = new Set(
    state.validation.filter((msg) => msg.node_id != null).map((msg) => msg.node_id as string),
  );

  // Resolve the in-flight connection from the same render snapshot as the
  // nodes, so every input handle observes one compatibility decision.
  let connectCtx: ConnectCtx | null = null;
  const connecting = state.connecting;
  if (connecting) {
    connectCtx = {
      inputs: inputCompatibilityByTarget(state.input_compatibility),
    };
  }

  for (const node of state.nodes) {
    seenNodes.add(node.id);
    let div = nodeDivs.get(node.id);
    if (!div) {
      div = document.createElement('div');
      div.className = 'canvas-node workflow-node';
      div.dataset.nodeId = String(node.id);

      const body = document.createElement('div');
      body.className = 'node-body';
      body.innerHTML = `
        <div class="node-kicker">Workflow step</div>
        <div class="node-title"></div>
        <div class="node-subtitle"></div>
        <div class="ports" aria-label="typed ports"></div>
      `;
      div.appendChild(body);

      world.appendChild(div);
      nodeDivs.set(node.id, div);
    }

    div.style.left   = `${node.x}px`;
    div.style.top    = `${node.y}px`;
    div.style.width  = `${node.w}px`;
    div.style.height = `${node.h}px`;
    div.dataset.kind = node.kind[0];
    div.classList.toggle('selected', selected.has(node.id));
    div.classList.toggle('invalid', invalidNodeIds.has(node.id));
    div.classList.toggle('unconfigured', !node.configured);
    div.classList.toggle('connecting-source', connecting?.from === node.id);
    div.title = `${node.title}\n${node.subtitle}`;

    const title = div.querySelector('.node-title') as HTMLDivElement;
    const subtitle = div.querySelector('.node-subtitle') as HTMLDivElement;
    const ports = div.querySelector('.ports') as HTMLDivElement;
    title.textContent = node.title;
    subtitle.textContent = node.subtitle;
    renderPortHandles(div, node, connectCtx);
    ports.replaceChildren(
      ...[...node.inputs.map((p) => ['in', p] as const), ...node.outputs.map((p) => ['out', p] as const)]
        .map(([direction, port]) => {
          const pill = document.createElement('span');
          pill.className = `port-pill ${direction}`;
          pill.textContent = `${direction}:${port.label}`;
          pill.title = portTitle(port);
          return pill;
        }),
    );
  }
  for (const [id, div] of nodeDivs) {
    if (!seenNodes.has(id)) { div.remove(); nodeDivs.delete(id); }
  }

  renderValidation(state);
  renderInspector(state);
}

function renderValidation(state: RenderState): void {
  actionStat.textContent = `${state.action_count} action${state.action_count === 1 ? '' : 's'} logged`;
  validation.replaceChildren();
  if (state.validation.length === 0) {
    const ok = document.createElement('div');
    ok.className = 'validation-ok';
    ok.textContent = 'Workflow is structurally valid.';
    validation.appendChild(ok);
    return;
  }
  for (const message of state.validation) {
    const item = document.createElement('button');
    item.className = `validation-item ${message.severity}`;
    item.type = 'button';
    item.textContent = message.message;
    if (message.node_id != null) {
      item.addEventListener('click', () => focusNode(message.node_id as string));
    }
    validation.appendChild(item);
  }
}

function commitSourceRename(nodeId: string, currentName: string, nextName: string): void {
  const trimmed = nextName.trim();
  if (trimmed === currentName || trimmed.length === 0) return;
  const result = adapter.renameNode(nodeId, trimmed);
  if (!result) return;
  updateSourceOperationStatus(
    result,
    'Renamed node binding through graph-dsl source.',
    'Source rename rejected',
  );
  adapter.clearSelectedEdge();
  scheduleRender();
}

function commitSourceParam(
  nodeId: string,
  param: NodeParamData,
  nextValue: string,
): void {
  const trimmed = nextValue.trim();
  if (trimmed === param.value || trimmed.length === 0) return;
  const result = adapter.setNodeParam(nodeId, param.name, trimmed);
  if (!result) return;
  updateSourceOperationStatus(
    result,
    `Updated ${param.name} through graph-dsl source.`,
    'Source parameter edit rejected',
  );
  adapter.clearSelectedEdge();
  scheduleRender();
}

function bindCommitOnChange(
  input: HTMLInputElement,
  originalValue: string,
  commit: (value: string) => void,
): void {
  let committed = false;
  const commitOnce = () => {
    if (committed) return;
    committed = true;
    commit(input.value);
  };
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      commitOnce();
      input.blur();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      committed = true;
      input.value = originalValue;
      input.blur();
    }
  });
  input.addEventListener('change', commitOnce);
}

function safeParamInputId(paramName: string): string {
  return `node-param-${paramName.replace(/[^a-z0-9_-]/gi, '-')}`;
}

function renderSourceNodeEditor(node: NodeData): HTMLDivElement {
  const editor = document.createElement('div');
  editor.className = 'inspector-source-editor';

  const bindingLabel = document.createElement('label');
  bindingLabel.className = 'inspector-field';
  bindingLabel.htmlFor = 'node-rename-input';
  const bindingText = document.createElement('span');
  bindingText.textContent = 'Binding';
  const bindingInput = document.createElement('input');
  bindingInput.id = 'node-rename-input';
  bindingInput.type = 'text';
  bindingInput.value = node.title;
  bindingInput.autocomplete = 'off';
  bindingInput.spellcheck = false;
  bindingInput.setAttribute('aria-label', 'Node binding');
  bindCommitOnChange(bindingInput, node.title, (value) => {
    commitSourceRename(node.id, node.title, value);
  });
  bindingLabel.replaceChildren(bindingText, bindingInput);
  editor.appendChild(bindingLabel);

  const params = node.params ?? [];
  if (params.length === 0) return editor;

  const paramList = document.createElement('div');
  paramList.className = 'inspector-param-list';
  for (const param of params) {
    const row = document.createElement('label');
    row.className = `inspector-field param ${param.editable ? 'editable' : 'readonly'}`;
    const id = safeParamInputId(param.name);
    row.htmlFor = id;
    const name = document.createElement('span');
    name.textContent = param.name;
    if (param.editable) {
      const input = document.createElement('input');
      input.id = id;
      input.type = 'text';
      input.inputMode = 'decimal';
      input.value = param.value;
      input.autocomplete = 'off';
      input.spellcheck = false;
      input.setAttribute('aria-label', `Parameter ${param.name}`);
      bindCommitOnChange(input, param.value, (value) => {
        commitSourceParam(node.id, param, value);
      });
      if (param.unit) {
        const unit = document.createElement('span');
        unit.className = 'param-unit';
        unit.textContent = param.unit;
        row.replaceChildren(name, input, unit);
      } else {
        row.replaceChildren(name, input);
      }
    } else {
      const value = document.createElement('span');
      value.className = 'param-readonly-value';
      value.textContent = param.unit ? `${param.value}${param.unit}` : param.value;
      row.replaceChildren(name, value);
    }
    paramList.appendChild(row);
  }
  editor.appendChild(paramList);
  return editor;
}

function renderInspector(state: RenderState): void {
  inspectorNode.replaceChildren();
  const selectedNodeId = state.selected ?? state.selected_nodes?.[0];
  const selectedNode = selectedNodeId != null
    ? state.nodes.find((candidate) => candidate.id === selectedNodeId)
    : undefined;
  const inspector = state.inspector ?? (
    adapter.isSourceBacked && selectedNode
      ? {
          id: selectedNode.id,
          title: selectedNode.title,
          subtitle: selectedNode.subtitle,
          configured: selectedNode.configured,
          input_count: selectedNode.inputs.length,
          output_count: selectedNode.outputs.length,
          source: 'selected',
        }
      : undefined
  );
  if (!inspector) {
    const empty = document.createElement('div');
    empty.className = 'inspector-empty';
    empty.textContent = 'Select or hover a node to inspect its sparse derived details.';
    inspectorNode.appendChild(empty);
    return;
  }

  const item = inspector;
  const status = item.configured ? 'Configured' : 'Needs config';
  const source = item.source === 'selected' ? 'Selected node' : 'Hovered node';

  const eyebrow = document.createElement('div');
  eyebrow.className = 'inspector-eyebrow';
  eyebrow.textContent = source;
  const title = document.createElement('div');
  title.className = 'inspector-title';
  title.textContent = item.title;
  const subtitle = document.createElement('div');
  subtitle.className = 'inspector-subtitle';
  subtitle.textContent = item.subtitle;
  const meta = document.createElement('div');
  meta.className = 'inspector-meta';
  const statusSpan = document.createElement('span');
  statusSpan.textContent = status;
  const portsSpan = document.createElement('span');
  portsSpan.textContent = `${item.input_count} in · ${item.output_count} out`;
  meta.replaceChildren(statusSpan, portsSpan);

  const children: HTMLElement[] = [eyebrow, title, subtitle, meta];
  if (adapter.isSourceBacked && item.source === 'selected') {
    const node = state.nodes.find((candidate) => candidate.id === item.id);
    if (node) children.push(renderSourceNodeEditor(node));
  }
  inspectorNode.replaceChildren(...children);
}

function focusNode(nodeId: string): void {
  const node = nodeDivs.get(nodeId);
  if (!node) return;
  node.animate([
    { boxShadow: '0 0 0 2px rgba(255,255,255,.9), 0 0 0 8px rgba(130,80,223,.35)' },
    { boxShadow: '' },
  ], { duration: 900, easing: 'cubic-bezier(.2,.8,.2,1)' });
}

function addNodeAt(kindKey: string, point: [number, number]): void {
  if (!adapter.isSourceBacked) {
    if (!screenToWorld(point, currentRenderState())) return;
  }
  adapter.clearSelectedEdge();
  if (adapter.isSourceBacked) {
    adapter.insertUniqueNode(kindKey, kindKey);
  } else {
    adapter.addNode(kindKey, point[0], point[1]);
  }
  scheduleRender();
}

function editableKeyboardTarget(target: EventTarget | null): boolean {
  const element = target instanceof HTMLElement ? target : null;
  if (!element) return false;
  if (element.isContentEditable) return true;
  const editable = element.closest('input, textarea, select, [contenteditable="true"]');
  return editable != null;
}

function sourceOperationDetail(result: SourceGraphOperationResult): string {
  return result.message ?? (result.diagnostics.length > 0 ? result.diagnostics.join('; ') : 'operation was rejected');
}

function updateSourceOperationStatus(
  result: SourceGraphOperationResult,
  successMessage: string,
  failurePrefix: string,
): void {
  const status = document.getElementById('source-status');
  if (!status) return;
  status.setAttribute('data-tone', result.applied ? 'success' : 'error');
  status.textContent = result.applied
    ? successMessage
    : `${failurePrefix}: ${sourceOperationDetail(result)}`;
}

function handleContextSourceResult(json: string): void {
  const result = JSON.parse(json) as SourceGraphOperationResult;
  if (!result.applied || result.message != null) {
    updateSourceOperationStatus(
      result,
      result.message ?? 'Context operation applied through graph-dsl source.',
      'Source context operation rejected',
    );
  }
}

function renderLibrary(filter = ''): void {
  const lower = filter.trim().toLowerCase();
  libraryEl.replaceChildren();
  for (const item of libraryCatalog) {
    if (lower && !`${item.label} ${item.description}`.toLowerCase().includes(lower)) continue;
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'library-item';
    button.innerHTML = `<strong>${item.label}</strong><span>${item.description}</span>`;
    button.title = item.description;
    button.addEventListener('click', () => addNodeAt(item.key, [root.clientWidth * 0.52, root.clientHeight * 0.48]));
    libraryEl.appendChild(button);
  }
}

document.addEventListener('keydown', (e: KeyboardEvent) => {
  if (
    (e.key === 'Delete' || e.key === 'Backspace') &&
    !e.metaKey &&
    !e.ctrlKey &&
    !e.altKey &&
    !editableKeyboardTarget(e.target)
  ) {
    const result = adapter.deleteSelection();
    if (result.handled) {
      const sourceResult = result.sourceResult;
      if (
        adapter.isSourceBacked &&
        sourceResult &&
        (sourceResult.applied || sourceResult.message != null)
      ) {
        updateSourceOperationStatus(
          sourceResult,
          sourceResult.message ?? 'Deleted selection through graph-dsl source.',
          'Source delete rejected',
        );
      }
      adapter.dismissContextMenu();
      e.preventDefault();
      scheduleRender();
    }
    return;
  }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'l') {
    e.preventDefault();
    console.table(adapter.actionLog());
  }
});

search.addEventListener('input', () => renderLibrary(search.value));

// ─── Bootstrap ────────────────────────────────────────────────────────────────

function sourceDemoRequested(searchParams = window.location.search): boolean {
  return new URLSearchParams(searchParams).get('source') === '1';
}

function requireSourceDemoModule(mb: CanvasModule): SourceDemoModule {
  if (typeof mb.sample_graph_dsl_source !== 'function') {
    throw new Error('Canvas module is missing source demo export: sample_graph_dsl_source');
  }
  if (typeof mb.mount_source_demo !== 'function') {
    throw new Error('Canvas module is missing source demo export: mount_source_demo');
  }
  if (typeof mb.get_workflow_node_catalog !== 'function') {
    throw new Error('Canvas module is missing workflow catalog export: get_workflow_node_catalog');
  }
  if (typeof mb.mount_canvas_context_menu !== 'function') {
    throw new Error('Canvas module is missing context menu export: mount_canvas_context_menu');
  }
  if (typeof mb.dismiss_canvas_context_menu !== 'function') {
    throw new Error('Canvas module is missing context menu export: dismiss_canvas_context_menu');
  }
  if (typeof mb.mount_canvas_pointer_session !== 'function') {
    throw new Error('Canvas module is missing pointer session export: mount_canvas_pointer_session');
  }
  return mb as SourceDemoModule;
}

// The source-panel CodeMirror editor loads via `mount(source="global:…")`,
// so bundle the CM6 namespace and publish it before the MoonBit module mounts.
// This keeps the editor deterministic and offline (no esm.sh fetch at runtime).
const canopyGlobal = globalThis as typeof globalThis & {
  __canopy_codemirror?: Record<string, unknown>;
};

async function init(): Promise<void> {
  canopyGlobal.__canopy_codemirror = { ...cmState, ...cmView, ...cmCommands };
  const raw = await import('@moonbit/canopy-canvas');
  const mod: CanvasModule = adaptMoonBitModule(raw, {
    createFunctions: ['create_source_graph'],
    destroyFunctions: ['destroy_source_graph'],
    tryDestroyFunctions: ['try_destroy_source_graph'],
  });
  const sourceDemoModule = requireSourceDemoModule(mod);
  const sourceMode = sourceDemoRequested();
  adapter = sourceMode
    ? GraphAdapter.createSourceBacked(mod, sourceDemoModule.sample_graph_dsl_source())
    : GraphAdapter.create(mod);
  libraryCatalog = JSON.parse(
    sourceDemoModule.get_workflow_node_catalog(),
  ) as LibraryItem[];
  sourceDemoModule.mount_canvas_context_menu(
    adapter.handleId,
    sourceMode,
    () => {
      scheduleRender();
      return undefined;
    },
    result => {
      handleContextSourceResult(result);
      return undefined;
    },
  );
  sourceDemoModule.mount_canvas_edge_layer();
  sourceDemoModule.mount_source_demo(adapter.handleId, sourceMode, () => {
    scheduleRender();
    return undefined;
  });
  sourceDemoModule.mount_canvas_pointer_session(
    adapter.handleId,
    sourceMode,
    () => {
      scheduleRender();
      return undefined;
    },
  );
  renderLibrary();
  render();
}

init();
