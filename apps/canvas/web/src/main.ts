import { adaptMoonBitModule } from '@canopy/editor-adapter/moonbit-result';
import * as cmCommands from '@codemirror/commands';
import * as cmState from '@codemirror/state';
import * as cmView from '@codemirror/view';
import * as canvasModule from '@moonbit/canopy-canvas';
import {
  GraphAdapter,
  type CanvasModule,
  type RenderState,
} from './graph-adapter';

export { GraphAdapter } from './graph-adapter';
export type {
  GraphOperation,
  RenderState,
} from './graph-adapter';

let adapter: GraphAdapter;
let rafPending = false;

const renderTarget = document.getElementById('canvas-render-layer') as HTMLDivElement;
const validation = document.getElementById('validation-list') as HTMLDivElement;
const actionStat = document.getElementById('action-stat') as HTMLSpanElement;
const validationTargets: { button: HTMLButtonElement; nodeId: string }[] = [];

// ─── RAF render loop ─────────────────────────────────────────────────────────

function scheduleRender(): void {
  if (rafPending) return;
  rafPending = true;
  requestAnimationFrame(render);
}

function render(): void {
  rafPending = false;
  const state = adapter.publishRenderState(renderTarget);
  renderValidation(state);
}

function renderValidation(state: RenderState): void {
  actionStat.textContent = `${state.action_count} action${state.action_count === 1 ? '' : 's'} logged`;
  validation.replaceChildren();
  validationTargets.length = 0;
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
      validationTargets.push({ button: item, nodeId: message.node_id });
    }
    validation.appendChild(item);
  }
}

// Called by the MoonBit render host after its DOM patch, never by a click handler.
function connectValidationTargets(): undefined {
  for (const { button, nodeId } of validationTargets) {
    const node = renderTarget.querySelector<HTMLElement>(
      `.canvas-node[data-node-id="${CSS.escape(nodeId)}"]`,
    );
    button.onclick = node ? () => focusNode(node) : null;
  }
  return undefined;
}

function focusNode(node: HTMLElement): void {
  node.animate([
    { boxShadow: '0 0 0 2px rgba(255,255,255,.9), 0 0 0 8px rgba(130,80,223,.35)' },
    { boxShadow: '' },
  ], { duration: 900, easing: 'cubic-bezier(.2,.8,.2,1)' });
}

document.addEventListener('keydown', (e: KeyboardEvent) => {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'l') {
    e.preventDefault();
    console.table(adapter.actionLog());
  }
});


// ─── Bootstrap ────────────────────────────────────────────────────────────────

function sourceDemoRequested(searchParams = window.location.search): boolean {
  return new URLSearchParams(searchParams).get('source') === '1';
}


// The source-panel CodeMirror editor loads via `mount(source="global:…")`,
// so bundle the CM6 namespace and publish it before the MoonBit module mounts.
// This keeps the editor deterministic and offline (no esm.sh fetch at runtime).
const canopyGlobal = globalThis as typeof globalThis & {
  __canopy_codemirror?: Record<string, unknown>;
};

function init(): void {
  canopyGlobal.__canopy_codemirror = { ...cmState, ...cmView, ...cmCommands };
  const mod: CanvasModule = adaptMoonBitModule(canvasModule, {
    createFunctions: ['create_source_graph'],
    destroyFunctions: ['destroy_source_graph'],
    tryDestroyFunctions: ['try_destroy_source_graph'],
  });
  const sourceMode = sourceDemoRequested();
  adapter = sourceMode
    ? GraphAdapter.createSourceBacked(mod, mod.sample_graph_dsl_source())
    : GraphAdapter.create(mod);
  mod.mount_canvas_ui(
    adapter.handleId,
    renderTarget,
    () => {
      scheduleRender();
      return undefined;
    },
    connectValidationTargets,
  );
  render();
}

init();
