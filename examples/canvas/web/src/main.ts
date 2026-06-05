import {
  GraphAdapter,
  type CanvasModule,
  type Connecting,
  type EdgeData,
  type NodeData,
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

type ContextMenuItem = LibraryItem;

type SourceDemoModule = CanvasModule & {
  sample_graph_dsl_source: () => string;
  mount_source_demo: (h: number, enabled: boolean, onChange: () => void) => void;
  mount_canvas_context_menu: (onSelect: (key: string) => void, onClose: () => void) => void;
};

const LIBRARY: LibraryItem[] = [
  { key: 'timer', label: 'Timer trigger', description: 'Start on a schedule' },
  { key: 'http', label: 'HTTP request', description: 'Call an external API' },
  { key: 'formatter', label: 'Format data', description: 'Map and reshape payloads' },
  { key: 'condition', label: 'Condition', description: 'Branch by a rule' },
  { key: 'loop', label: 'Loop', description: 'Repeat over records' },
  { key: 'parallel', label: 'Parallel split', description: 'Run branches together' },
  { key: 'custom', label: 'Custom step', description: 'Reserve an integration point' },
];

const SVG_NS = 'http://www.w3.org/2000/svg';
const CONTEXT_MENU_SHOW_EVENT = 'canopy-canvas-context-menu-show';
const CONTEXT_MENU_HIDE_EVENT = 'canopy-canvas-context-menu-hide';
const EDGE_CONTEXT_MENU_KEY = 'disconnect-edge';

let adapter: GraphAdapter;
let rafPending = false;
let lastState: RenderState | null = null;

const isMacLike = /Mac|iPhone|iPad|iPod/.test(navigator.platform);

const root       = document.getElementById('canvas-root') as HTMLDivElement;
const world      = document.getElementById('world') as HTMLDivElement;
const edgesSvg   = document.getElementById('edges') as unknown as SVGSVGElement;
const search     = document.getElementById('node-search') as HTMLInputElement;
const libraryEl  = document.getElementById('node-library') as HTMLDivElement;
const validation = document.getElementById('validation-list') as HTMLDivElement;
const inspectorNode = document.getElementById('inspector-node') as HTMLDivElement;
const actionStat = document.getElementById('action-stat') as HTMLSpanElement;
const contextMenu = document.getElementById('context-menu') as HTMLDivElement;
const nodeDivs = new Map<number, HTMLDivElement>();
const edgePaths = new Map<number, SVGPathElement>();
let pendingPath: SVGPathElement | null = null;
let contextPoint: [number, number] = [0, 0];
let contextEdge: EdgeData | null = null;
let sourcePointerId = -1;
let sourceConnecting: Connecting | null = null;

type EdgeSelection = Pick<EdgeData, 'source' | 'source_port' | 'target' | 'target_port'>;
let selectedEdge: EdgeSelection | null = null;

// ─── Geometry ────────────────────────────────────────────────────────────────

function portOffset(n: NodeData, side: 'input' | 'output', portId: string): number {
  const ports = side === 'input' ? n.inputs : n.outputs;
  if (ports.length === 0) return n.h / 2;
  const index = Math.max(0, ports.findIndex((p) => p.id === portId));
  return ((index + 1) * n.h) / (ports.length + 1);
}

/** Output handle for a specific port (world coords). */
function outputAnchor(n: NodeData, portId: string): [number, number] { return [n.x + n.w, n.y + portOffset(n, 'output', portId)]; }
/** Input handle for a specific port (world coords). */
function inputAnchor(n: NodeData, portId: string): [number, number]  { return [n.x,       n.y + portOffset(n, 'input', portId)]; }

/** Cubic bezier from src to dst with horizontal handles, react-flow style. */
function bezierPath(sx: number, sy: number, tx: number, ty: number): string {
  const dx = Math.max(40, Math.abs(tx - sx) * 0.5);
  return `M ${sx} ${sy} C ${sx + dx} ${sy}, ${tx - dx} ${ty}, ${tx} ${ty}`;
}

function localCoords(e: MouseEvent): [number, number] {
  const rect = root.getBoundingClientRect();
  return [e.clientX - rect.left, e.clientY - rect.top];
}

function screenToWorld(point: [number, number], state: RenderState): [number, number] {
  const { x, y, scale } = state.viewport;
  return [(point[0] - x) / scale, (point[1] - y) / scale];
}

function eventWorldCoords(e: MouseEvent): [number, number] {
  return screenToWorld(localCoords(e), lastState ?? adapter.renderState());
}

function portTypeName(portType: Tagged): string {
  return Array.isArray(portType) ? String(portType[0]) : String(portType);
}

function portTitle(port: PortDef): string {
  return `${port.label}: ${portTypeName(port.port_type)}`;
}

function edgeSelectionFromEdge(edge: EdgeData): EdgeSelection {
  return {
    source: edge.source,
    source_port: edge.source_port,
    target: edge.target,
    target_port: edge.target_port,
  };
}

function edgeMatchesSelection(edge: EdgeData, selection: EdgeSelection): boolean {
  return edge.source === selection.source &&
    edge.source_port === selection.source_port &&
    edge.target === selection.target &&
    edge.target_port === selection.target_port;
}

function edgeTitle(edge: EdgeData): string {
  return `${edge.source}.${edge.source_port} → ${edge.target}.${edge.target_port}`;
}

function selectEdge(edge: EdgeData): void {
  selectedEdge = edgeSelectionFromEdge(edge);
}

function clearSelectedEdge(): void {
  selectedEdge = null;
}

// ─── Connection compatibility (display only) ───────────────────────────────────
// Mirrors MoonBit `can_commit_edge` so input handles can preview which targets a
// drag could land on. This is purely cosmetic — MoonBit validation stays the
// authoritative commit/reject check on pointerup.

/** Context for the in-flight connection, resolved once per render. */
type ConnectCtx = {
  fromNode: number;
  fromPort: string;
  sourceType: string | null;
  edges: EdgeData[];
};

/** Mirror of MoonBit `port_type_compatible`. */
function portTypesCompatible(source: string, target: string): boolean {
  return source === target || source === 'Any' || target === 'Any';
}

/**
 * Whether dragging from the active source onto this input handle would be
 * accepted, mirroring `can_commit_edge` (self-loop, duplicate edge, type check).
 */
function inputHandleCompatible(ctx: ConnectCtx, targetNode: number, targetPort: PortDef): boolean {
  if (ctx.sourceType == null) return false;
  if (ctx.fromNode === targetNode) return false; // self-loop
  const duplicate = ctx.edges.some(
    (e) =>
      e.source === ctx.fromNode &&
      e.source_port === ctx.fromPort &&
      e.target === targetNode &&
      e.target_port === targetPort.id,
  );
  if (duplicate) return false;
  return portTypesCompatible(ctx.sourceType, portTypeName(targetPort.port_type));
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
          inputHandleCompatible(connectCtx, node.id, port) ? 'compatible-target' : 'incompatible-target',
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
  const state = adapter.renderState();
  const edgeSelection = selectedEdge;
  if (edgeSelection && !state.edges.some((edge) => edgeMatchesSelection(edge, edgeSelection))) {
    selectedEdge = null;
  }
  lastState = state;

  const { x, y, scale } = state.viewport;
  const transform = `translate(${x}px, ${y}px) scale(${scale})`;
  world.style.transform    = transform;
  edgesSvg.style.transform = transform;

  // Nodes ────────────────────────────────────────────────────────────────────
  const nodesById = new Map<number, NodeData>();
  const seenNodes = new Set<number>();
  const selected = new Set(state.selected_nodes ?? []);
  const invalidNodeIds = new Set(
    state.validation.filter((msg) => msg.node_id != null).map((msg) => msg.node_id as number),
  );

  // Resolve the in-flight connection's source port type once, so each input
  // handle can preview compatibility while the drag is live.
  let connectCtx: ConnectCtx | null = null;
  const connecting = state.connecting ?? sourceConnecting ?? undefined;
  if (connecting) {
    const from = connecting;
    const srcNode = state.nodes.find((n) => n.id === from.from);
    const srcPort = srcNode?.outputs.find((p) => p.id === from.from_port);
    connectCtx = {
      fromNode: from.from,
      fromPort: from.from_port,
      sourceType: srcPort ? portTypeName(srcPort.port_type) : null,
      edges: state.edges,
    };
  }

  for (const node of state.nodes) {
    seenNodes.add(node.id);
    nodesById.set(node.id, node);

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

  // Edges ────────────────────────────────────────────────────────────────────
  const seenEdges = new Set<number>();
  for (const edge of state.edges) {
    const src = nodesById.get(edge.source);
    const dst = nodesById.get(edge.target);
    if (!src || !dst) continue;
    seenEdges.add(edge.id);
    const [sx, sy] = outputAnchor(src, edge.source_port);
    const [tx, ty] = inputAnchor(dst, edge.target_port);
    let path = edgePaths.get(edge.id);
    if (!path) {
      path = document.createElementNS(SVG_NS, 'path');
      path.setAttribute('class', 'edge');
      edgesSvg.appendChild(path);
      edgePaths.set(edge.id, path);
    }
    path.setAttribute('d', bezierPath(sx, sy, tx, ty));
    path.setAttribute('data-edge-id', String(edge.id));
    path.classList.toggle('selected', selectedEdge != null && edgeMatchesSelection(edge, selectedEdge));
    path.setAttribute('role', 'button');
    path.setAttribute('tabindex', '0');
    path.setAttribute('aria-label', `Disconnect ${edgeTitle(edge)}`);
  }
  for (const [id, path] of edgePaths) {
    if (!seenEdges.has(id)) { path.remove(); edgePaths.delete(id); }
  }

  // In-flight connection ─────────────────────────────────────────────────────
  if (connecting) {
    const src = nodesById.get(connecting.from);
    if (src) {
      const [sx, sy] = outputAnchor(src, connecting.from_port);
      const tx = connecting.cursor_x;
      const ty = connecting.cursor_y;
      if (!pendingPath) {
        pendingPath = document.createElementNS(SVG_NS, 'path');
        pendingPath.setAttribute('class', 'edge-pending');
        edgesSvg.appendChild(pendingPath);
      }
      pendingPath.setAttribute('d', bezierPath(sx, sy, tx, ty));
    }
  } else if (pendingPath) {
    pendingPath.remove();
    pendingPath = null;
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
      item.addEventListener('click', () => focusNode(message.node_id as number));
    }
    validation.appendChild(item);
  }
}

function renderInspector(state: RenderState): void {
  inspectorNode.replaceChildren();
  if (!state.inspector) {
    const empty = document.createElement('div');
    empty.className = 'inspector-empty';
    empty.textContent = 'Select or hover a node to inspect its sparse derived details.';
    inspectorNode.appendChild(empty);
    return;
  }

  const item = state.inspector;
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
  inspectorNode.replaceChildren(eyebrow, title, subtitle, meta);
}

function focusNode(nodeId: number): void {
  const node = nodeDivs.get(nodeId);
  if (!node) return;
  node.animate([
    { boxShadow: '0 0 0 2px rgba(255,255,255,.9), 0 0 0 8px rgba(130,80,223,.35)' },
    { boxShadow: '' },
  ], { duration: 900, easing: 'cubic-bezier(.2,.8,.2,1)' });
}

// ─── DOM helpers ─────────────────────────────────────────────────────────────

type HitTarget =
  | { kind: 'background' }
  | { kind: 'node'; nodeId: number }
  | { kind: 'edge'; edge: EdgeData }
  | { kind: 'handle'; nodeId: number; side: 'input' | 'output'; portId: string };

function hitFromTarget(target: EventTarget | null): HitTarget {
  let el = target instanceof Element ? target : null;
  while (el && el !== root) {
    const element = el as HTMLElement | SVGElement;
    if (element.dataset?.edgeId) {
      const edgeId = parseInt(element.dataset.edgeId);
      const state = lastState ?? adapter.renderState();
      const edge = state.edges.find((candidate) => candidate.id === edgeId);
      if (edge) return { kind: 'edge', edge };
    }
    if (element.dataset?.handle && element.dataset?.nodeId && element.dataset?.portId) {
      return {
        kind: 'handle',
        nodeId: parseInt(element.dataset.nodeId),
        side: element.dataset.handle as 'input' | 'output',
        portId: element.dataset.portId,
      };
    }
    if (element.dataset?.nodeId && element.classList.contains('canvas-node')) {
      return { kind: 'node', nodeId: parseInt(element.dataset.nodeId) };
    }
    el = el.parentElement;
  }
  return { kind: 'background' };
}

function addNodeAt(kindKey: string, point: [number, number]): void {
  clearSelectedEdge();
  if (adapter.isSourceBacked) {
    adapter.insertUniqueNode(kindKey, kindKey);
    hideContextMenu();
    scheduleRender();
    return;
  }
  adapter.addNode(kindKey, point[0], point[1]);
  hideContextMenu();
  scheduleRender();
}

function hoverNodeId(hit: HitTarget): number {
  return hit.kind === 'node' || hit.kind === 'handle' ? hit.nodeId : 0;
}

function updateHover(hit: HitTarget): void {
  if (adapter.isSourceBacked) return;
  adapter.hoverNode(hoverNodeId(hit));
}

function startSourceConnection(e: PointerEvent, hit: HitTarget): void {
  if (hit.kind !== 'handle' || hit.side !== 'output') return;
  clearSelectedEdge();
  hideContextMenu();
  root.setPointerCapture(e.pointerId);
  sourcePointerId = e.pointerId;
  const [cursor_x, cursor_y] = eventWorldCoords(e);
  sourceConnecting = {
    from: hit.nodeId,
    from_port: hit.portId,
    cursor_x,
    cursor_y,
  };
  scheduleRender();
}

function moveSourceConnection(e: PointerEvent): void {
  if (e.pointerId !== sourcePointerId || !sourceConnecting) return;
  const [cursor_x, cursor_y] = eventWorldCoords(e);
  sourceConnecting = { ...sourceConnecting, cursor_x, cursor_y };
  scheduleRender();
}

function finishSourceConnection(e: PointerEvent): void {
  if (e.pointerId !== sourcePointerId) return;
  const connecting = sourceConnecting;
  const under = document.elementFromPoint(e.clientX, e.clientY);
  const hit = hitFromTarget(under);
  sourcePointerId = -1;
  sourceConnecting = null;
  if (connecting && hit.kind === 'handle' && hit.side === 'input') {
    adapter.connectPorts(connecting.from, hit.nodeId, hit.portId);
  }
  scheduleRender();
}

function cancelSourceConnection(e: PointerEvent): void {
  if (e.pointerId !== sourcePointerId) return;
  sourcePointerId = -1;
  sourceConnecting = null;
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

function syncSourceEditorFromResult(result: SourceGraphOperationResult): void {
  if (!result.applied) return;
  const editor = document.getElementById('source-editor') as HTMLTextAreaElement | null;
  if (editor) editor.value = result.source;
}

function disconnectEdge(edge: EdgeData): boolean {
  const result = adapter.disconnectPorts(
    edge.source,
    edge.source_port,
    edge.target,
    edge.target_port,
  );
  if (result) {
    syncSourceEditorFromResult(result);
    updateSourceOperationStatus(
      result,
      'Disconnected selected edge through graph-dsl source.',
      'Source disconnect rejected',
    );
  }
  clearSelectedEdge();
  hideContextMenu();
  scheduleRender();
  return true;
}

function deleteSelectedEdge(): boolean {
  const edgeSelection = selectedEdge;
  if (!edgeSelection) return false;
  const state = lastState ?? adapter.renderState();
  const edge = state.edges.find((candidate) => edgeMatchesSelection(candidate, edgeSelection));
  if (!edge) {
    clearSelectedEdge();
    scheduleRender();
    return true;
  }
  return disconnectEdge(edge);
}

function deleteSelectedNodes(): boolean {
  const state = lastState ?? adapter.renderState();
  const selectedNodes = state.selected_nodes ?? [];
  if (selectedNodes.length === 0) return false;
  const result = adapter.deleteNodes(selectedNodes);
  if (result) {
    syncSourceEditorFromResult(result);
    updateSourceOperationStatus(
      result,
      'Deleted selected nodes through graph-dsl source.',
      'Source delete rejected',
    );
  }
  clearSelectedEdge();
  hideContextMenu();
  scheduleRender();
  return true;
}

function hideContextMenuElement(): void {
  contextMenu.hidden = true;
  contextEdge = null;
}

function hideContextMenu(): void {
  const wasOpen = !contextMenu.hidden;
  hideContextMenuElement();
  if (wasOpen) {
    contextMenu.dispatchEvent(new CustomEvent(CONTEXT_MENU_HIDE_EVENT));
  }
}

function showContextMenu(anchor: Point, items: ContextMenuItem[]): void {
  contextMenu.hidden = false;
  contextMenu.dispatchEvent(new CustomEvent(CONTEXT_MENU_SHOW_EVENT, {
    detail: JSON.stringify({ x: anchor.x, y: anchor.y, items }),
  }));
}

function renderLibrary(filter = ''): void {
  const lower = filter.trim().toLowerCase();
  libraryEl.replaceChildren();
  for (const item of LIBRARY) {
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

function renderEdgeContextMenu(edge: EdgeData, anchor: Point): void {
  contextEdge = edge;
  showContextMenu(anchor, [
    { key: EDGE_CONTEXT_MENU_KEY, label: 'Disconnect edge', description: edgeTitle(edge) },
  ]);
}

function renderContextMenu(anchor: Point): void {
  contextEdge = null;
  showContextMenu(anchor, LIBRARY);
}

function handleContextMenuSelect(key: string): void {
  if (key === EDGE_CONTEXT_MENU_KEY) {
    if (contextEdge) disconnectEdge(contextEdge);
    return;
  }
  addNodeAt(key, contextPoint);
}

// ─── Event wiring ─────────────────────────────────────────────────────────────

let activePointerId = -1;
let pointerDownNodeId = 0;
let pointerUpAdditive = false;

root.addEventListener('pointerdown', (e: PointerEvent) => {
  if (adapter.isSourceBacked) {
    if (e.button !== 0) return;
    const hit = hitFromTarget(e.target);
    if (hit.kind === 'edge') {
      hideContextMenu();
      selectEdge(hit.edge);
      scheduleRender();
      return;
    }
    if (hit.kind === 'handle') {
      startSourceConnection(e, hit);
      return;
    }
    if (activePointerId !== -1) return;
    clearSelectedEdge();
    hideContextMenu();
    root.setPointerCapture(e.pointerId);
    activePointerId = e.pointerId;
    pointerUpAdditive = e.shiftKey || e.metaKey || e.ctrlKey;
    const [sx, sy] = localCoords(e);
    pointerDownNodeId = hit.kind === 'node' ? hit.nodeId : 0;
    adapter.pointerDown(pointerDownNodeId, sx, sy);
    if (hit.kind === 'background') root.classList.add('panning');
    scheduleRender();
    return;
  }
  // macOS Ctrl+click is a secondary-click gesture but still reports button 0.
  // Let the contextmenu handler own it without breaking Ctrl-additive
  // selection on non-Mac platforms.
  if (e.button !== 0 || (isMacLike && e.ctrlKey)) return;
  if (activePointerId !== -1) return;
  hideContextMenu();
  const hit = hitFromTarget(e.target);
  if (hit.kind === 'edge') {
    selectEdge(hit.edge);
    scheduleRender();
    return;
  }
  clearSelectedEdge();
  root.setPointerCapture(e.pointerId);
  activePointerId = e.pointerId;
  pointerUpAdditive = e.shiftKey || e.metaKey || e.ctrlKey;
  const [sx, sy] = localCoords(e);

  switch (hit.kind) {
    case 'handle':
      // Only output handles initiate a connection in the prototype.
      if (hit.side === 'output') {
        adapter.pointerDownHandle(hit.nodeId, hit.portId, sx, sy);
        pointerDownNodeId = 0; // pointerup uses hover target, not down target
      } else {
        // Input handle clicks are inert for now; do not start background pan.
        pointerDownNodeId = 0;
      }
      break;
    case 'node':
      pointerDownNodeId = hit.nodeId;
      adapter.pointerDown(hit.nodeId, sx, sy);
      break;
    case 'background':
      pointerDownNodeId = 0;
      adapter.pointerDown(0, sx, sy);
      root.classList.add('panning');
      break;
  }
  scheduleRender();
});

root.addEventListener('pointermove', (e: PointerEvent) => {
  if (adapter.isSourceBacked) {
    if (e.pointerId === sourcePointerId) {
      moveSourceConnection(e);
      return;
    }
    if (e.pointerId !== activePointerId) {
      scheduleRender();
      return;
    }
    const [sx, sy] = localCoords(e);
    adapter.pointerMove(sx, sy);
    scheduleRender();
    return;
  }
  updateHover(hitFromTarget(e.target));
  if (e.pointerId !== activePointerId) {
    scheduleRender();
    return;
  }
  const [sx, sy] = localCoords(e);
  adapter.pointerMove(sx, sy);
  scheduleRender();
});

root.addEventListener('pointerleave', () => {
  if (adapter.isSourceBacked) return;
  updateHover({ kind: 'background' });
  scheduleRender();
});

root.addEventListener('pointerup', (e: PointerEvent) => {
  if (adapter.isSourceBacked) {
    if (e.pointerId === sourcePointerId) {
      finishSourceConnection(e);
      return;
    }
    if (e.pointerId !== activePointerId) return;
    const under = document.elementFromPoint(e.clientX, e.clientY);
    const hit = hitFromTarget(under);
    const upNodeId =
      hit.kind === 'node'   ? hit.nodeId :
      hit.kind === 'handle' ? hit.nodeId :
      pointerDownNodeId;
    adapter.pointerUp(upNodeId, '', pointerUpAdditive);
    activePointerId = -1;
    pointerDownNodeId = 0;
    pointerUpAdditive = false;
    root.classList.remove('panning');
    scheduleRender();
    return;
  }
  if (e.pointerId !== activePointerId) return;
  // setPointerCapture redirects later events to the capturer, so e.target is
  // unreliable for hit-testing on release. Use elementFromPoint instead.
  const under = document.elementFromPoint(e.clientX, e.clientY);
  const hit = hitFromTarget(under);
  const upNodeId =
    hit.kind === 'node'   ? hit.nodeId :
    hit.kind === 'handle' ? hit.nodeId :
    pointerDownNodeId;
  const targetPortId = hit.kind === 'handle' && hit.side === 'input' ? hit.portId : '';
  adapter.pointerUp(upNodeId, targetPortId, pointerUpAdditive);
  activePointerId = -1;
  pointerDownNodeId = 0;
  pointerUpAdditive = false;
  root.classList.remove('panning');
  scheduleRender();
});

root.addEventListener('pointercancel', (e: PointerEvent) => {
  if (adapter.isSourceBacked) {
    if (e.pointerId === sourcePointerId) {
      cancelSourceConnection(e);
      return;
    }
    if (e.pointerId !== activePointerId) return;
    adapter.pointerUp(0, '', false);
    activePointerId = -1;
    pointerDownNodeId = 0;
    pointerUpAdditive = false;
    root.classList.remove('panning');
    scheduleRender();
    return;
  }
  if (e.pointerId !== activePointerId) return;
  adapter.pointerUp(0, '', false);
  activePointerId = -1;
  pointerDownNodeId = 0;
  pointerUpAdditive = false;
  root.classList.remove('panning');
  scheduleRender();
});

root.addEventListener('wheel', (e: WheelEvent) => {
  e.preventDefault();
  const [cx, cy] = localCoords(e);
  adapter.zoom(e.deltaY, cx, cy);
  scheduleRender();
}, { passive: false });

root.addEventListener('contextmenu', (e: MouseEvent) => {
  e.preventDefault();
  const hit = hitFromTarget(e.target);
  const anchor = { x: Math.round(e.clientX), y: Math.round(e.clientY) };
  if (hit.kind === 'edge') {
    selectEdge(hit.edge);
    renderEdgeContextMenu(hit.edge, anchor);
  } else {
    clearSelectedEdge();
    contextPoint = localCoords(e);
    renderContextMenu(anchor);
  }
  scheduleRender();
});

document.addEventListener('keydown', (e: KeyboardEvent) => {
  if (e.key === 'Escape') hideContextMenu();
  if (
    (e.key === 'Delete' || e.key === 'Backspace') &&
    !e.metaKey &&
    !e.ctrlKey &&
    !e.altKey &&
    !editableKeyboardTarget(e.target)
  ) {
    if (selectedEdge) {
      if (deleteSelectedEdge()) e.preventDefault();
      return;
    }
    if (deleteSelectedNodes()) e.preventDefault();
    return;
  }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'l') {
    e.preventDefault();
    console.table(adapter.actionLog());
  }
});

document.addEventListener('pointerdown', (e: PointerEvent) => {
  if (!contextMenu.contains(e.target as Node)) hideContextMenu();
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
  if (typeof mb.mount_canvas_context_menu !== 'function') {
    throw new Error('Canvas module is missing context menu export: mount_canvas_context_menu');
  }
  return mb as SourceDemoModule;
}

async function init(): Promise<void> {
  const mod = await import('@moonbit/canopy-canvas') as CanvasModule;
  const sourceDemoModule = requireSourceDemoModule(mod);
  const sourceMode = sourceDemoRequested();
  adapter = sourceMode
    ? GraphAdapter.createSourceBacked(mod, sourceDemoModule.sample_graph_dsl_source())
    : GraphAdapter.create(mod);
  sourceDemoModule.mount_canvas_context_menu(handleContextMenuSelect, hideContextMenuElement);
  sourceDemoModule.mount_source_demo(adapter.handleId, sourceMode, scheduleRender);
  renderLibrary();
  render();
}

init();
