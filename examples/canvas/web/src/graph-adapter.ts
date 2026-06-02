export type CanvasModule = {
  create_canvas: () => number;
  pointer_down: (h: number, nodeId: number, sx: number, sy: number) => void;
  pointer_down_handle: (
    h: number,
    nodeId: number,
    portId: string,
    sx: number,
    sy: number,
  ) => void;
  pointer_move: (h: number, sx: number, sy: number) => void;
  pointer_up: (
    h: number,
    nodeId: number,
    targetPortId: string,
    additive: boolean,
  ) => void;
  zoom: (h: number, delta: number, cx: number, cy: number) => void;
  add_node: (h: number, kindKey: string, sx: number, sy: number) => void;
  get_render_state: (h: number) => string;
  get_action_log: (h: number) => string;
};

export type Tagged = string | [string, ...unknown[]];
export type NodeKind = ['Workflow', Tagged];
export type PortDef = { id: string; label: string; port_type: Tagged };
export type NodeData = {
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
export type EdgeData = {
  id: number;
  source: number;
  source_port: string;
  target: number;
  target_port: string;
};
export type Connecting = {
  from: number;
  from_port: string;
  cursor_x: number;
  cursor_y: number;
};
export type ValidationMessage = {
  severity: 'error' | 'warning';
  message: string;
  node_id?: number;
};
export type ViewportData = { x: number; y: number; scale: number };
export type RenderState = {
  viewport: ViewportData;
  nodes: NodeData[];
  edges: EdgeData[];
  selected?: number;
  selected_nodes: number[];
  connecting?: Connecting;
  validation: ValidationMessage[];
  action_count: number;
};

export type NodePositionData = { node_id: number; x: number; y: number };

export type GraphOperation =
  | { version: number; type: 'AddNode'; node: NodeData }
  | { version: number; type: 'MoveNodes'; positions: NodePositionData[] }
  | {
      version: number;
      type: 'ConnectPorts';
      source: number;
      source_port: string;
      target: number;
      target_port: string;
    }
  | { version: number; type: 'SelectNodes'; nodes: number[] }
  | { version: number; type: 'SetViewport'; viewport: ViewportData };

export type GraphOperationCallback = (operation: GraphOperation) => void;

/**
 * Lifecycle boundary for the canvas graph surface.
 *
 * The current prototype remains MoonBit-state-backed: DOM rendering still pulls
 * `RenderState` snapshots from the MoonBit canvas model. This adapter is the
 * public TypeScript seam that later source-backed graph panes can reuse for
 * lifecycle, operation notification, and teardown without depending on globals.
 */
export class GraphAdapter {
  private operationCallback: GraphOperationCallback | null = null;
  private lastActionCount = 0;
  private destroyed = false;

  private constructor(
    private readonly mb: CanvasModule,
    private readonly handle: number,
  ) {
    this.lastActionCount = this.readActionLog().length;
  }

  static create(mb: CanvasModule): GraphAdapter {
    return new GraphAdapter(mb, mb.create_canvas());
  }

  get handleId(): number {
    return this.handle;
  }

  renderState(): RenderState {
    this.assertLive();
    const state = JSON.parse(this.mb.get_render_state(this.handle)) as RenderState;
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

  pointerDown(nodeId: number, sx: number, sy: number): void {
    this.assertLive();
    this.mb.pointer_down(this.handle, nodeId, sx, sy);
  }

  pointerDownHandle(
    nodeId: number,
    portId: string,
    sx: number,
    sy: number,
  ): void {
    this.assertLive();
    this.mb.pointer_down_handle(this.handle, nodeId, portId, sx, sy);
  }

  pointerMove(sx: number, sy: number): void {
    this.assertLive();
    this.mb.pointer_move(this.handle, sx, sy);
  }

  pointerUp(nodeId: number, targetPortId: string, additive: boolean): void {
    this.assertLive();
    this.mb.pointer_up(this.handle, nodeId, targetPortId, additive);
    this.emitLatestOperations();
  }

  zoom(delta: number, cx: number, cy: number): void {
    this.assertLive();
    this.mb.zoom(this.handle, delta, cx, cy);
    this.emitLatestOperations();
  }

  addNode(kindKey: string, sx: number, sy: number): void {
    this.assertLive();
    this.mb.add_node(this.handle, kindKey, sx, sy);
    this.emitLatestOperations();
  }

  destroy(): void {
    this.operationCallback = null;
    this.destroyed = true;
  }

  private readActionLog(): GraphOperation[] {
    return JSON.parse(this.mb.get_action_log(this.handle)) as GraphOperation[];
  }

  private emitLatestOperations(): void {
    if (!this.operationCallback) return;
    this.emitOperationsThrough(this.readActionLog().length);
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
