type CanvasModule = {
  create_canvas: () => number;
  pointer_down:        (h: number, nodeId: number, sx: number, sy: number) => void;
  pointer_down_handle: (h: number, nodeId: number, sx: number, sy: number) => void;
  pointer_move:        (h: number, sx: number, sy: number) => void;
  pointer_up:          (h: number, nodeId: number) => void;
  zoom:                (h: number, delta: number, cx: number, cy: number) => void;
  get_render_state:    (h: number) => string;
};

type NodeKind = ['Shape', string] | ['Text', string];
type NodeData = { id: number; x: number; y: number; w: number; h: number; kind: NodeKind };
type EdgeData = { id: number; source: number; target: number };
type Connecting = { from: number; cursor_x: number; cursor_y: number };
type RenderState = {
  viewport: { x: number; y: number; scale: number };
  nodes: NodeData[];
  edges: EdgeData[];
  selected?: number;
  connecting?: Connecting;
};

const SVG_NS = 'http://www.w3.org/2000/svg';

let mb: CanvasModule;
let handle = -1;
let rafPending = false;

const root     = document.getElementById('canvas-root') as HTMLDivElement;
const world    = document.getElementById('world') as HTMLDivElement;
const edgesSvg = document.getElementById('edges') as unknown as SVGSVGElement;
const nodeDivs = new Map<number, HTMLDivElement>();
const edgePaths = new Map<number, SVGPathElement>();
let pendingPath: SVGPathElement | null = null;

// ─── Geometry ────────────────────────────────────────────────────────────────

/** Output handle = right-center of node (world coords). */
function outputAnchor(n: NodeData): [number, number] { return [n.x + n.w, n.y + n.h / 2]; }
/** Input handle = left-center of node (world coords). */
function inputAnchor(n: NodeData): [number, number]  { return [n.x,       n.y + n.h / 2]; }

/** Cubic bezier from src to dst with horizontal handles, react-flow style. */
function bezierPath(sx: number, sy: number, tx: number, ty: number): string {
  const dx = Math.max(40, Math.abs(tx - sx) * 0.5);
  return `M ${sx} ${sy} C ${sx + dx} ${sy}, ${tx - dx} ${ty}, ${tx} ${ty}`;
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

  const { x, y, scale } = state.viewport;
  const transform = `translate(${x}px, ${y}px) scale(${scale})`;
  world.style.transform    = transform;
  edgesSvg.style.transform = transform;

  // Nodes ────────────────────────────────────────────────────────────────────
  const nodesById = new Map<number, NodeData>();
  const seenNodes = new Set<number>();
  for (const node of state.nodes) {
    seenNodes.add(node.id);
    nodesById.set(node.id, node);

    let div = nodeDivs.get(node.id);
    if (!div) {
      div = document.createElement('div');
      div.className = 'canvas-node';
      div.dataset.nodeId = String(node.id);

      const inH = document.createElement('div');
      inH.className = 'handle input';
      inH.dataset.handle = 'input';
      inH.dataset.nodeId = String(node.id);
      div.appendChild(inH);

      const outH = document.createElement('div');
      outH.className = 'handle output';
      outH.dataset.handle = 'output';
      outH.dataset.nodeId = String(node.id);
      div.appendChild(outH);

      const label = document.createElement('span');
      label.className = 'node-label';
      div.appendChild(label);

      world.appendChild(div);
      nodeDivs.set(node.id, div);
    }
    div.style.left   = `${node.x}px`;
    div.style.top    = `${node.y}px`;
    div.style.width  = `${node.w}px`;
    div.style.height = `${node.h}px`;

    const [kind, value] = node.kind;
    const label = div.querySelector('.node-label') as HTMLSpanElement;
    if (kind === 'Shape') {
      div.style.backgroundColor = value;
      div.dataset.kind = 'Shape';
      label.textContent = '';
    } else {
      div.style.backgroundColor = '';
      div.dataset.kind = 'Text';
      label.textContent = value;
    }
    div.classList.toggle('selected', state.selected != null && state.selected === node.id);
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
    const [sx, sy] = outputAnchor(src);
    const [tx, ty] = inputAnchor(dst);
    let path = edgePaths.get(edge.id);
    if (!path) {
      path = document.createElementNS(SVG_NS, 'path');
      path.setAttribute('class', 'edge');
      edgesSvg.appendChild(path);
      edgePaths.set(edge.id, path);
    }
    path.setAttribute('d', bezierPath(sx, sy, tx, ty));
  }
  for (const [id, path] of edgePaths) {
    if (!seenEdges.has(id)) { path.remove(); edgePaths.delete(id); }
  }

  // In-flight connection ─────────────────────────────────────────────────────
  if (state.connecting) {
    const src = nodesById.get(state.connecting.from);
    if (src) {
      const [sx, sy] = outputAnchor(src);
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
}

// ─── DOM helpers ─────────────────────────────────────────────────────────────

function localCoords(e: MouseEvent): [number, number] {
  const rect = root.getBoundingClientRect();
  return [e.clientX - rect.left, e.clientY - rect.top];
}

type HitTarget =
  | { kind: 'background' }
  | { kind: 'node'; nodeId: number }
  | { kind: 'handle'; nodeId: number; side: 'input' | 'output' };

function hitFromTarget(target: EventTarget | null): HitTarget {
  let el = target as HTMLElement | null;
  while (el && el !== root) {
    if (el.dataset?.handle && el.dataset?.nodeId) {
      return {
        kind: 'handle',
        nodeId: parseInt(el.dataset.nodeId),
        side: el.dataset.handle as 'input' | 'output',
      };
    }
    if (el.dataset?.nodeId && el.classList.contains('canvas-node')) {
      return { kind: 'node', nodeId: parseInt(el.dataset.nodeId) };
    }
    el = el.parentElement;
  }
  return { kind: 'background' };
}

// ─── Event wiring ─────────────────────────────────────────────────────────────

let activePointerId = -1;
let pointerDownNodeId = 0;

root.addEventListener('pointerdown', (e: PointerEvent) => {
  if (activePointerId !== -1) return;
  root.setPointerCapture(e.pointerId);
  activePointerId = e.pointerId;
  const [sx, sy] = localCoords(e);
  const hit = hitFromTarget(e.target);

  switch (hit.kind) {
    case 'handle':
      // Only output handles initiate a connection in the prototype.
      if (hit.side === 'output') {
        mb.pointer_down_handle(handle, hit.nodeId, sx, sy);
        pointerDownNodeId = 0; // pointerup uses hover target, not down target
      } else {
        // Input handle clicks are inert for now.
        mb.pointer_down(handle, 0, sx, sy);
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
  mb.pointer_up(handle, upNodeId);
  activePointerId = -1;
  pointerDownNodeId = 0;
  root.classList.remove('panning');
  scheduleRender();
});

root.addEventListener('pointercancel', (e: PointerEvent) => {
  if (e.pointerId !== activePointerId) return;
  mb.pointer_up(handle, 0);
  activePointerId = -1;
  pointerDownNodeId = 0;
  root.classList.remove('panning');
  scheduleRender();
});

root.addEventListener('wheel', (e: WheelEvent) => {
  e.preventDefault();
  const [cx, cy] = localCoords(e);
  mb.zoom(handle, e.deltaY, cx, cy);
  scheduleRender();
}, { passive: false });

// ─── Bootstrap ────────────────────────────────────────────────────────────────

async function init(): Promise<void> {
  const mod = await import('@moonbit/canopy-canvas') as CanvasModule;
  mb = mod;
  handle = mb.create_canvas();
  render();
}

init();
