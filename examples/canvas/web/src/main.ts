type CanvasModule = {
  create_canvas: () => number;
  pointer_down:  (h: number, nodeId: number, sx: number, sy: number) => void;
  pointer_move:  (h: number, sx: number, sy: number) => void;
  pointer_up:    (h: number, nodeId: number) => void;
  zoom:          (h: number, delta: number, cx: number, cy: number) => void;
  get_render_state: (h: number) => string;
};

type NodeKind   = ['Shape', string] | ['Text', string];
type NodeData   = { id: number; x: number; y: number; w: number; h: number; kind: NodeKind };
type RenderState = { viewport: { x: number; y: number; scale: number }; nodes: NodeData[]; selected?: number };

let mb: CanvasModule;
let handle = -1;
let rafPending = false;

const root     = document.getElementById('canvas-root') as HTMLDivElement;
const world    = document.getElementById('world') as HTMLDivElement;
const nodeDivs = new Map<number, HTMLDivElement>();

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
  world.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;

  const seen = new Set<number>();
  for (const node of state.nodes) {
    seen.add(node.id);
    let div = nodeDivs.get(node.id);
    if (!div) {
      div = document.createElement('div');
      div.className = 'canvas-node';
      div.dataset.nodeId = String(node.id);
      world.appendChild(div);
      nodeDivs.set(node.id, div);
    }
    div.style.left   = `${node.x}px`;
    div.style.top    = `${node.y}px`;
    div.style.width  = `${node.w}px`;
    div.style.height = `${node.h}px`;

    const [kind, value] = node.kind;
    if (kind === 'Shape') {
      div.style.backgroundColor = value;
      div.dataset.kind = 'Shape';
      div.textContent = '';
    } else {
      div.style.backgroundColor = '';
      div.dataset.kind = 'Text';
      div.textContent = value;
    }
    // selected is absent (not null) when nothing is selected — use loose equality
    div.classList.toggle('selected', state.selected != null && state.selected === node.id);
  }

  for (const [id, div] of nodeDivs) {
    if (!seen.has(id)) { div.remove(); nodeDivs.delete(id); }
  }
}

// ─── DOM helpers ─────────────────────────────────────────────────────────────

/** Pointer/wheel position in canvas-local screen space. */
function localCoords(e: MouseEvent): [number, number] {
  const rect = root.getBoundingClientRect();
  return [e.clientX - rect.left, e.clientY - rect.top];
}

/** Walk up from event target to find data-node-id. Returns 0 for background. */
function nodeIdFromTarget(target: EventTarget | null): number {
  let el = target as HTMLElement | null;
  while (el && el !== world) {
    if (el.dataset?.nodeId) return parseInt(el.dataset.nodeId);
    el = el.parentElement;
  }
  return 0;
}

// ─── Event wiring ─────────────────────────────────────────────────────────────

let activePointerId = -1;
let pointerDownNodeId = 0;

root.addEventListener('pointerdown', (e: PointerEvent) => {
  if (activePointerId !== -1) return; // ignore secondary pointers
  root.setPointerCapture(e.pointerId);
  activePointerId = e.pointerId;
  const [sx, sy] = localCoords(e);
  const nodeId = nodeIdFromTarget(e.target);
  pointerDownNodeId = nodeId;
  mb.pointer_down(handle, nodeId, sx, sy);
  if (nodeId === 0) root.classList.add('panning');
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
  mb.pointer_up(handle, pointerDownNodeId);
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
