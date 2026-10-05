export type CanvasModule = {
  create_canvas: () => number;
  mount_canvas_ui: (
    h: number,
    renderTarget: Element,
    onChange: () => undefined,
    onRendered: () => undefined,
  ) => undefined;
  publish_render_state: (h: number, target: Element) => string;
  get_render_state: (h: number) => string;
  get_action_log: (h: number) => string;
  create_source_graph?: (source: string) => number;
  destroy_source_graph?: (h: number) => void;
  get_source_graph_source?: (h: number) => string;
  get_source_graph_render_state?: (h: number) => string;
  get_source_graph_action_log?: (h: number) => string;
  sample_graph_dsl_source: () => string;
};

type SourceCanvasModule = CanvasModule & {
  create_source_graph: (source: string) => number;
  destroy_source_graph: (h: number) => void;
  get_source_graph_source: (h: number) => string;
  get_source_graph_render_state: (h: number) => string;
  get_source_graph_action_log: (h: number) => string;
};

const SOURCE_METHODS = [
  'create_source_graph',
  'destroy_source_graph',
  'get_source_graph_source',
  'get_source_graph_render_state',
  'get_source_graph_action_log',
] as const;

export type Tagged = string | [string, ...unknown[]];
export type NodeKind = ['Workflow', Tagged];
export type PortDef = {
  id: string;
  label: string;
  port_type: Tagged;
  allows_fan_in?: boolean;
};
export type NodeParamData = {
  name: string;
  value_kind: string;
  value: string;
  unit?: string;
  editable: boolean;
};
export type NodeData = {
  id: string;
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
  params?: NodeParamData[];
};
export type PortCompatibility = {
  node_id: string;
  port_id: string;
  compatible: boolean;
};
export type Connecting = {
  from: string;
  from_port: string;
  cursor_x: number;
  cursor_y: number;
};
export type ValidationMessage = {
  severity: 'error' | 'warning';
  message: string;
  node_id?: string;
};
export type ViewportData = { x: number; y: number; scale: number };
export type InspectorNode = {
  id: string;
  title: string;
  subtitle: string;
  configured: boolean;
  input_count: number;
  output_count: number;
  source: 'selected' | 'hovered' | string;
};
export type RenderState = {
  viewport: ViewportData;
  nodes: NodeData[];
  selected?: string;
  selected_nodes: string[];
  connecting?: Connecting;
  input_compatibility: PortCompatibility[];
  validation: ValidationMessage[];
  action_count: number;
  inspector?: InspectorNode;
};

export type NodePositionData = { node_id: string; x: number; y: number };

export type GraphOperation =
  | { version: number; type: 'AddNode'; node: NodeData }
  | { version: number; type: 'MoveNodes'; positions: NodePositionData[] }
  | {
      version: number;
      type: 'ConnectPorts';
      source: string;
      source_port: string;
      target: string;
      target_port: string;
    }
  | {
      version: number;
      type: 'DisconnectPorts';
      source: string;
      source_port: string;
      target: string;
      target_port: string;
    }
  | { version: number; type: 'DeleteNodes'; nodes: string[] }
  | { version: number; type: 'RenameNode'; node_id: string; name: string }
  | {
      version: number;
      type: 'SetNodeParam';
      node_id: string;
      parameter: string;
      value: string;
    }
  | { version: number; type: 'SelectNodes'; nodes: string[] }
  | { version: number; type: 'SetViewport'; viewport: ViewportData };

export type GraphOperationCallback = (operation: GraphOperation) => void;

type AdapterMode = 'canvas' | 'source';

function requireSourceModule(mb: CanvasModule): SourceCanvasModule {
  const missing = SOURCE_METHODS.filter((name) => typeof mb[name] !== 'function');
  if (missing.length > 0) {
    throw new Error(`Canvas module is missing source graph exports: ${missing.join(', ')}`);
  }
  return mb as SourceCanvasModule;
}


/**
 * Lifecycle boundary for the canvas graph surface.
 *
 * MoonBit owns canvas/source mutations and UI composition. TypeScript retains
 * lifecycle, render publication, and delivery of canonical action-log entries.
 */
export class GraphAdapter {
  private operationCallback: GraphOperationCallback | null = null;
  private lastActionCount = 0;
  private destroyed = false;

  private constructor(
    private readonly mb: CanvasModule,
    private readonly handle: number,
    private readonly mode: AdapterMode,
  ) {
    this.lastActionCount = this.readActionLog().length;
  }

  static create(mb: CanvasModule): GraphAdapter {
    return new GraphAdapter(mb, mb.create_canvas(), 'canvas');
  }

  static createSourceBacked(mb: CanvasModule, source: string): GraphAdapter {
    const sourceMb = requireSourceModule(mb);
    return new GraphAdapter(mb, sourceMb.create_source_graph(source), 'source');
  }

  get handleId(): number {
    return this.handle;
  }

  get isSourceBacked(): boolean {
    return this.mode === 'source';
  }

  renderState(): RenderState {
    this.assertLive();
    const json = this.isSourceBacked
      ? this.sourceModule().get_source_graph_render_state(this.handle)
      : this.mb.get_render_state(this.handle);
    const state = JSON.parse(json) as RenderState;
    this.emitOperationsThrough(state.action_count);
    return state;
  }

  publishRenderState(target: Element): RenderState {
    this.assertLive();
    const state = JSON.parse(
      this.mb.publish_render_state(this.handle, target),
    ) as RenderState;
    this.emitOperationsThrough(state.action_count);
    return state;
  }

  actionLog(): GraphOperation[] {
    this.assertLive();
    return this.readActionLog();
  }

  onOperation(callback: GraphOperationCallback): void {
    this.assertLive();
    this.operationCallback = callback;
    this.lastActionCount = this.readActionLog().length;
  }

  source(): string {
    this.assertLive();
    return this.sourceModule().get_source_graph_source(this.handle);
  }

  destroy(): void {
    if (!this.destroyed && this.isSourceBacked) {
      this.sourceModule().destroy_source_graph(this.handle);
    }
    this.operationCallback = null;
    this.destroyed = true;
  }

  private readActionLog(): GraphOperation[] {
    const json = this.isSourceBacked
      ? this.sourceModule().get_source_graph_action_log(this.handle)
      : this.mb.get_action_log(this.handle);
    return JSON.parse(json) as GraphOperation[];
  }

  private sourceModule(): SourceCanvasModule {
    if (!this.isSourceBacked) {
      throw new Error('GraphAdapter is not source-backed');
    }
    return this.mb as SourceCanvasModule;
  }

  private emitOperationsThrough(actionCount: number): void {
    if (!this.operationCallback) return;
    if (actionCount <= this.lastActionCount) {
      this.lastActionCount = actionCount;
      return;
    }
    const operations = this.readActionLog();
    for (const operation of operations.slice(this.lastActionCount, actionCount)) {
      this.operationCallback(operation);
    }
    this.lastActionCount = actionCount;
  }

  private assertLive(): void {
    if (this.destroyed) {
      throw new Error('GraphAdapter has been destroyed');
    }
  }

}
