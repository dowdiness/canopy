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
  hover_node: (h: number, nodeId: number) => void;
  zoom: (h: number, delta: number, cx: number, cy: number) => void;
  add_node: (h: number, kindKey: string, sx: number, sy: number) => void;
  delete_nodes: (h: number, nodeIdsJson: string) => void;
  disconnect_ports: (
    h: number,
    source: number,
    sourcePort: string,
    target: number,
    targetPort: string,
  ) => void;
  get_render_state: (h: number) => string;
  get_action_log: (h: number) => string;
  create_source_graph?: (source: string) => number;
  destroy_source_graph?: (h: number) => void;
  get_source_graph_source?: (h: number) => string;
  set_source_graph_source?: (h: number, source: string) => void;
  set_source_graph_source_result?: (h: number, source: string) => string;
  get_source_graph_render_state?: (h: number) => string;
  get_source_graph_action_log?: (h: number) => string;
  apply_source_graph_operation?: (h: number, operationJson: string) => string;
  source_graph_insert_unique?: (
    h: number,
    bindingBase: string,
    constructorName: string,
  ) => string;
  source_graph_pointer_down?: (h: number, nodeId: number, sx: number, sy: number) => void;
  source_graph_pointer_move?: (h: number, sx: number, sy: number) => void;
  source_graph_pointer_up?: (
    h: number,
    nodeId: number,
    targetPortId: string,
    additive: boolean,
  ) => void;
  source_graph_zoom?: (h: number, delta: number, cx: number, cy: number) => void;
  sample_graph_dsl_source?: () => string;
  mount_source_demo?: (h: number, enabled: boolean, onChange: () => void) => void;
  mount_canvas_context_menu?: (onSelect: (key: string) => void, onClose: () => void) => void;
};

type SourceCanvasModule = CanvasModule & {
  create_source_graph: (source: string) => number;
  destroy_source_graph: (h: number) => void;
  get_source_graph_source: (h: number) => string;
  set_source_graph_source: (h: number, source: string) => void;
  set_source_graph_source_result: (h: number, source: string) => string;
  get_source_graph_render_state: (h: number) => string;
  get_source_graph_action_log: (h: number) => string;
  apply_source_graph_operation: (h: number, operationJson: string) => string;
  source_graph_insert_unique: (
    h: number,
    bindingBase: string,
    constructorName: string,
  ) => string;
  source_graph_pointer_down: (h: number, nodeId: number, sx: number, sy: number) => void;
  source_graph_pointer_move: (h: number, sx: number, sy: number) => void;
  source_graph_pointer_up: (
    h: number,
    nodeId: number,
    targetPortId: string,
    additive: boolean,
  ) => void;
  source_graph_zoom: (h: number, delta: number, cx: number, cy: number) => void;
};

const SOURCE_METHODS = [
  'create_source_graph',
  'destroy_source_graph',
  'get_source_graph_source',
  'set_source_graph_source',
  'set_source_graph_source_result',
  'get_source_graph_render_state',
  'get_source_graph_action_log',
  'apply_source_graph_operation',
  'source_graph_insert_unique',
  'source_graph_pointer_down',
  'source_graph_pointer_move',
  'source_graph_pointer_up',
  'source_graph_zoom',
] as const;

export type Tagged = string | [string, ...unknown[]];
export type NodeKind = ['Workflow', Tagged];
export type PortDef = { id: string; label: string; port_type: Tagged };
export type NodeParamData = {
  name: string;
  value_kind: string;
  value: string;
  unit?: string;
  editable: boolean;
};
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
  params?: NodeParamData[];
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
export type InspectorNode = {
  id: number;
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
  edges: EdgeData[];
  selected?: number;
  selected_nodes: number[];
  connecting?: Connecting;
  validation: ValidationMessage[];
  action_count: number;
  inspector?: InspectorNode;
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
  | {
      version: number;
      type: 'DisconnectPorts';
      source: number;
      source_port: string;
      target: number;
      target_port: string;
    }
  | { version: number; type: 'DeleteNodes'; nodes: number[] }
  | { version: number; type: 'RenameNode'; node_id: number; name: string }
  | {
      version: number;
      type: 'SetNodeParam';
      node_id: number;
      parameter: string;
      value: string;
    }
  | { version: number; type: 'SelectNodes'; nodes: number[] }
  | { version: number; type: 'SetViewport'; viewport: ViewportData };

export type GraphOperationCallback = (operation: GraphOperation) => void;

export type SourceGraphOperationResult = {
  applied: boolean;
  source: string;
  diagnostics: string[];
  action_count: number;
  message?: string;
};

type AdapterMode = 'canvas' | 'source';

function requireSourceModule(mb: CanvasModule): SourceCanvasModule {
  const missing = SOURCE_METHODS.filter((name) => typeof mb[name] !== 'function');
  if (missing.length > 0) {
    throw new Error(`Canvas module is missing source graph exports: ${missing.join(', ')}`);
  }
  return mb as SourceCanvasModule;
}

function sourceNodePayload(binding: string, constructorName: string): NodeData {
  return {
    id: 0,
    x: 0,
    y: 0,
    w: 250,
    h: 138,
    kind: ['Workflow', ['Custom', constructorName]],
    title: binding,
    subtitle: constructorName,
    inputs: [],
    outputs: [],
    configured: true,
  };
}

/**
 * Lifecycle boundary for the canvas graph surface.
 *
 * `create()` keeps the original MoonBit-canvas state as the backing store.
 * `createSourceBacked()` keeps graph-dsl source text canonical: operations are
 * sent to MoonBit as `GraphOperation` JSON, lowered through Loom GraphDoc source
 * maps, and rendered from the reparsed source/last-good GraphDoc.
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

  setSource(source: string): SourceGraphOperationResult {
    this.assertLive();
    const result = JSON.parse(
      this.sourceModule().set_source_graph_source_result(this.handle, source),
    ) as SourceGraphOperationResult;
    this.lastActionCount = this.readActionLog().length;
    return result;
  }

  applyOperation(operation: GraphOperation): SourceGraphOperationResult {
    this.assertLive();
    const result = JSON.parse(
      this.sourceModule().apply_source_graph_operation(
        this.handle,
        JSON.stringify(operation),
      ),
    ) as SourceGraphOperationResult;
    this.emitLatestOperations();
    return result;
  }

  insertNode(binding: string, constructorName: string): SourceGraphOperationResult {
    return this.applyOperation({
      version: 1,
      type: 'AddNode',
      node: sourceNodePayload(binding, constructorName),
    });
  }

  insertUniqueNode(bindingBase: string, constructorName: string): SourceGraphOperationResult {
    this.assertLive();
    const result = JSON.parse(
      this.sourceModule().source_graph_insert_unique(
        this.handle,
        bindingBase,
        constructorName,
      ),
    ) as SourceGraphOperationResult;
    this.emitLatestOperations();
    return result;
  }

  connectPorts(
    sourceNodeId: number,
    targetNodeId: number,
    targetPortId = 'input',
  ): SourceGraphOperationResult {
    return this.applyOperation({
      version: 1,
      type: 'ConnectPorts',
      source: sourceNodeId,
      source_port: 'out',
      target: targetNodeId,
      target_port: targetPortId,
    });
  }

  deleteNodes(nodeIds: number[]): SourceGraphOperationResult | null {
    this.assertLive();
    const uniqueNodeIds = [...new Set(nodeIds)].filter((id) => Number.isFinite(id));
    if (uniqueNodeIds.length === 0) return null;
    const operation: GraphOperation = {
      version: 1,
      type: 'DeleteNodes',
      nodes: uniqueNodeIds,
    };
    if (this.isSourceBacked) {
      return this.applyOperation(operation);
    }
    this.mb.delete_nodes(this.handle, JSON.stringify(uniqueNodeIds));
    this.emitLatestOperations();
    return null;
  }

  renameNode(nodeId: number, name: string): SourceGraphOperationResult | null {
    this.assertLive();
    const nextName = name.trim();
    if (!this.isSourceBacked || !Number.isFinite(nodeId) || nextName.length === 0) {
      return null;
    }
    return this.applyOperation({
      version: 1,
      type: 'RenameNode',
      node_id: nodeId,
      name: nextName,
    });
  }

  setNodeParam(
    nodeId: number,
    parameter: string,
    value: string,
  ): SourceGraphOperationResult | null {
    this.assertLive();
    const nextParameter = parameter.trim();
    const nextValue = value.trim();
    if (
      !this.isSourceBacked ||
      !Number.isFinite(nodeId) ||
      nextParameter.length === 0 ||
      nextValue.length === 0
    ) {
      return null;
    }
    return this.applyOperation({
      version: 1,
      type: 'SetNodeParam',
      node_id: nodeId,
      parameter: nextParameter,
      value: nextValue,
    });
  }

  disconnectPorts(
    sourceNodeId: number,
    sourcePortId: string,
    targetNodeId: number,
    targetPortId: string,
  ): SourceGraphOperationResult | null {
    this.assertLive();
    if (
      !Number.isFinite(sourceNodeId) ||
      !Number.isFinite(targetNodeId) ||
      sourcePortId.length === 0 ||
      targetPortId.length === 0
    ) {
      return null;
    }
    const operation: GraphOperation = {
      version: 1,
      type: 'DisconnectPorts',
      source: sourceNodeId,
      source_port: sourcePortId,
      target: targetNodeId,
      target_port: targetPortId,
    };
    if (this.isSourceBacked) {
      return this.applyOperation(operation);
    }
    this.mb.disconnect_ports(
      this.handle,
      sourceNodeId,
      sourcePortId,
      targetNodeId,
      targetPortId,
    );
    this.emitLatestOperations();
    return null;
  }

  pointerDown(nodeId: number, sx: number, sy: number): void {
    this.assertLive();
    if (this.isSourceBacked) {
      this.sourceModule().source_graph_pointer_down(this.handle, nodeId, sx, sy);
    } else {
      this.mb.pointer_down(this.handle, nodeId, sx, sy);
    }
  }

  pointerDownHandle(
    nodeId: number,
    portId: string,
    sx: number,
    sy: number,
  ): void {
    this.assertCanvasBacked('pointerDownHandle');
    this.mb.pointer_down_handle(this.handle, nodeId, portId, sx, sy);
  }

  pointerMove(sx: number, sy: number): void {
    this.assertLive();
    if (this.isSourceBacked) {
      this.sourceModule().source_graph_pointer_move(this.handle, sx, sy);
    } else {
      this.mb.pointer_move(this.handle, sx, sy);
    }
  }

  pointerUp(nodeId: number, targetPortId: string, additive: boolean): void {
    this.assertLive();
    if (this.isSourceBacked) {
      this.sourceModule().source_graph_pointer_up(
        this.handle,
        nodeId,
        targetPortId,
        additive,
      );
    } else {
      this.mb.pointer_up(this.handle, nodeId, targetPortId, additive);
    }
    this.emitLatestOperations();
  }

  hoverNode(nodeId: number): void {
    this.assertCanvasBacked('hoverNode');
    this.mb.hover_node(this.handle, nodeId);
  }

  zoom(delta: number, cx: number, cy: number): void {
    this.assertLive();
    if (this.isSourceBacked) {
      this.sourceModule().source_graph_zoom(this.handle, delta, cx, cy);
    } else {
      this.mb.zoom(this.handle, delta, cx, cy);
    }
    this.emitLatestOperations();
  }

  addNode(kindKey: string, sx: number, sy: number): void {
    this.assertCanvasBacked('addNode');
    this.mb.add_node(this.handle, kindKey, sx, sy);
    this.emitLatestOperations();
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

  private assertCanvasBacked(method: string): void {
    this.assertLive();
    if (this.isSourceBacked) {
      throw new Error(`${method} is only available for canvas-backed graphs`);
    }
  }
}
