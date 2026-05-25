type CanvasModule = {
  create_canvas: () => number;
  pointer_down:        (h: number, nodeId: number, sx: number, sy: number) => void;
  pointer_down_handle: (h: number, nodeId: number, portId: string, sx: number, sy: number) => void;
  pointer_move:        (h: number, sx: number, sy: number) => void;
  pointer_up:          (h: number, nodeId: number, targetPortId: string, additive: boolean) => void;
  zoom:                (h: number, delta: number, cx: number, cy: number) => void;
  add_node:            (h: number, kindKey: string, sx: number, sy: number) => void;
  get_render_state:    (h: number) => string;
  get_action_log:      (h: number) => string;
};

type Tagged = string | [string, ...unknown[]];
type NodeKind = ['Workflow', Tagged];
type PortDef = { id: string; label: string; port_type: Tagged };
type NodeData = {
  id: number;
  x: number;
  y: number;
  w: number;
  h: number;
  kind: NodeKind;
  title: string;
  subtitle: string;
  inputs: PortDef[];
  outputs: PortDef[];
  configured: boolean;
};
type EdgeData = { id: number; source: number; source_port: string; target: number; target_port: string };
type Connecting = { from: number; from_port: string; cursor_x: number; cursor_y: number };
type ValidationMessage = { severity: 'error' | 'warning'; message: string; node_id?: number };
type RenderState = {
  viewport: { x: number; y: number; scale: number };
  nodes: NodeData[];
  edges: EdgeData[];
  selected?: number;
  selected_nodes: number[];
  connecting?: Connecting;
  validation: ValidationMessage[];
  action_count: number;
};

type LibraryItem = {
  key: string;
  label: string;
  description: string;
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

let mb: CanvasModule;
let handle = -1;
let rafPending = false;
let lastState: RenderState | null = null;

const isMacLike = /Mac|iPhone|iPad|iPod/.test(navigator.platform);

const root       = document.getElementById('canvas-root') as HTMLDivElement;
const world      = document.getElementById('world') as HTMLDivElement;
const edgesSvg   = document.getElementById('edges') as unknown as SVGSVGElement;
const search     = document.getElementById('node-search') as HTMLInputElement;
const libraryEl  = document.getElementById('node-library') as HTMLDivElement;
const validation = document.getElementById('validation-list') as HTMLDivElement;
const actionStat = document.getElementById('action-stat') as HTMLSpanElement;
const contextMenu = document.getElementById('context-menu') as HTMLDivElement;
const nodeDivs = new Map<number, HTMLDivElement>();
const edgePaths = new Map<number, SVGPathElement>();
let pendingPath: SVGPathElement | null = null;
let contextPoint: [number, number] = [0, 0];

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

function portTypeName(portType: Tagged): string {
  return Array.isArray(portType) ? String(portType[0]) : String(portType);
}

function portTitle(port: PortDef): string {
  return `${port.label}: ${portTypeName(port.port_type)}`;
}

function renderPortHandles(div: HTMLDivElement, node: NodeData): void {
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
  const state: RenderState = JSON.parse(mb.get_render_state(handle));
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
    div.classList.toggle('connecting-source', state.connecting?.from === node.id);
    div.title = `${node.title}\n${node.subtitle}`;

    const title = div.querySelector('.node-title') as HTMLDivElement;
    const subtitle = div.querySelector('.node-subtitle') as HTMLDivElement;
    const ports = div.querySelector('.ports') as HTMLDivElement;
    title.textContent = node.title;
    subtitle.textContent = node.subtitle;
    renderPortHandles(div, node);
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
  }
  for (const [id, path] of edgePaths) {
    if (!seenEdges.has(id)) { path.remove(); edgePaths.delete(id); }
  }

  // In-flight connection ─────────────────────────────────────────────────────
  if (state.connecting) {
    const src = nodesById.get(state.connecting.from);
    if (src) {
      const [sx, sy] = outputAnchor(src, state.connecting.from_port);
      const tx = state.connecting.cursor_x;
      const ty = state.connecting.cursor_y;
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
  | { kind: 'handle'; nodeId: number; side: 'input' | 'output'; portId: string };

function hitFromTarget(target: EventTarget | null): HitTarget {
  let el = target as HTMLElement | null;
  while (el && el !== root) {
    if (el.dataset?.handle && el.dataset?.nodeId && el.dataset?.portId) {
      return {
        kind: 'handle',
        nodeId: parseInt(el.dataset.nodeId),
        side: el.dataset.handle as 'input' | 'output',
        portId: el.dataset.portId,
      };
    }
    if (el.dataset?.nodeId && el.classList.contains('canvas-node')) {
      return { kind: 'node', nodeId: parseInt(el.dataset.nodeId) };
    }
    el = el.parentElement;
  }
  return { kind: 'background' };
}

function addNodeAt(kindKey: string, point: [number, number]): void {
  mb.add_node(handle, kindKey, point[0], point[1]);
  hideContextMenu();
  scheduleRender();
}

function hideContextMenu(): void {
  contextMenu.hidden = true;
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

function renderContextMenu(): void {
  contextMenu.replaceChildren();
  for (const item of LIBRARY) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = item.label;
    button.title = item.description;
    button.addEventListener('click', () => addNodeAt(item.key, contextPoint));
    contextMenu.appendChild(button);
  }
}

// ─── Event wiring ─────────────────────────────────────────────────────────────

let activePointerId = -1;
let pointerDownNodeId = 0;
let pointerUpAdditive = false;

root.addEventListener('pointerdown', (e: PointerEvent) => {
  // macOS Ctrl+click is a secondary-click gesture but still reports button 0.
  // Let the contextmenu handler own it without breaking Ctrl-additive
  // selection on non-Mac platforms.
  if (e.button !== 0 || (isMacLike && e.ctrlKey)) return;
  if (activePointerId !== -1) return;
  hideContextMenu();
  root.setPointerCapture(e.pointerId);
  activePointerId = e.pointerId;
  pointerUpAdditive = e.shiftKey || e.metaKey || e.ctrlKey;
  const [sx, sy] = localCoords(e);
  const hit = hitFromTarget(e.target);

  switch (hit.kind) {
    case 'handle':
      // Only output handles initiate a connection in the prototype.
      if (hit.side === 'output') {
        mb.pointer_down_handle(handle, hit.nodeId, hit.portId, sx, sy);
        pointerDownNodeId = 0; // pointerup uses hover target, not down target
      } else {
        // Input handle clicks are inert for now; do not start background pan.
        pointerDownNodeId = 0;
      }
      break;
    case 'node':
      pointerDownNodeId = hit.nodeId;
      mb.pointer_down(handle, hit.nodeId, sx, sy);
      break;
    case 'background':
      pointerDownNodeId = 0;
      mb.pointer_down(handle, 0, sx, sy);
      root.classList.add('panning');
      break;
  }
  scheduleRender();
});

root.addEventListener('pointermove', (e: PointerEvent) => {
  if (e.pointerId !== activePointerId) return;
  const [sx, sy] = localCoords(e);
  mb.pointer_move(handle, sx, sy);
  scheduleRender();
});

root.addEventListener('pointerup', (e: PointerEvent) => {
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
  mb.pointer_up(handle, upNodeId, targetPortId, pointerUpAdditive);
  activePointerId = -1;
  pointerDownNodeId = 0;
  pointerUpAdditive = false;
  root.classList.remove('panning');
  scheduleRender();
});

root.addEventListener('pointercancel', (e: PointerEvent) => {
  if (e.pointerId !== activePointerId) return;
  mb.pointer_up(handle, 0, '', false);
  activePointerId = -1;
  pointerDownNodeId = 0;
  pointerUpAdditive = false;
  root.classList.remove('panning');
  scheduleRender();
});

root.addEventListener('wheel', (e: WheelEvent) => {
  e.preventDefault();
  const [cx, cy] = localCoords(e);
  mb.zoom(handle, e.deltaY, cx, cy);
  scheduleRender();
}, { passive: false });

root.addEventListener('contextmenu', (e: MouseEvent) => {
  e.preventDefault();
  contextPoint = localCoords(e);
  renderContextMenu();
  contextMenu.style.left = `${e.clientX}px`;
  contextMenu.style.top = `${e.clientY}px`;
  contextMenu.hidden = false;
});

document.addEventListener('keydown', (e: KeyboardEvent) => {
  if (e.key === 'Escape') hideContextMenu();
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'l') {
    e.preventDefault();
    console.table(JSON.parse(mb.get_action_log(handle)));
  }
});

document.addEventListener('pointerdown', (e: PointerEvent) => {
  if (!contextMenu.contains(e.target as Node)) hideContextMenu();
});

search.addEventListener('input', () => renderLibrary(search.value));

// ─── Bootstrap ────────────────────────────────────────────────────────────────

async function init(): Promise<void> {
  const mod = await import('@moonbit/canopy-canvas') as CanvasModule;
  mb = mod;
  handle = mb.create_canvas();
  renderLibrary();
  render();
}

init();
