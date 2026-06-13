export type CanvasModule = {
  create_canvas: () => number;
  pointer_down: (h: number, nodeId: string, sx: number, sy: number) => void;
  pointer_down_handle: (
    h: number,
    nodeId: string,
    portId: string,
    sx: number,
    sy: number,
  ) => void;
  pointer_move: (h: number, sx: number, sy: number) => void;
  pointer_up: (
    h: number,
    nodeId: string,
    targetPortId: string,
    additive: boolean,
  ) => void;
  hover_node: (h: number, nodeId: string) => void;
  zoom: (h: number, delta: number, cx: number, cy: number) => void;
  add_node: (h: number, kindKey: string, sx: number, sy: number) => void;
  delete_nodes: (h: number, nodeIdsJson: string) => void;
  disconnect_ports: (
    h: number,
    source: string,
    sourcePort: string,
    target: string,
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
  source_graph_pointer_down?: (h: number, nodeId: string, sx: number, sy: number) => void;
  source_graph_pointer_move?: (h: number, sx: number, sy: number) => void;
  source_graph_pointer_up?: (
    h: number,
    nodeId: string,
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
  source_graph_pointer_down: (h: number, nodeId: string, sx: number, sy: number) => void;
  source_graph_pointer_move: (h: number, sx: number, sy: number) => void;
  source_graph_pointer_up: (
    h: number,
    nodeId: string,
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
export type EdgeData = {
  id: string;
  source: string;
  source_port: string;
  target: string;
  target_port: string;
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
  edges: EdgeData[];
  selected?: string;
  selected_nodes: string[];
  connecting?: Connecting;
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
    id: '',
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
      version: 2,
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
    sourceNodeId: string,
    targetNodeId: string,
    targetPortId = 'input',
  ): SourceGraphOperationResult {
    return this.applyOperation({
      version: 2,
      type: 'ConnectPorts',
      source: sourceNodeId,
      source_port: 'out',
      target: targetNodeId,
      target_port: targetPortId,
    });
  }

  deleteNodes(nodeIds: string[]): SourceGraphOperationResult | null {
    this.assertLive();
    const uniqueNodeIds = [...new Set(nodeIds)].filter((id) => id.length > 0);
    if (uniqueNodeIds.length === 0) return null;
    const operation: GraphOperation = {
      version: 2,
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

  renameNode(nodeId: string, name: string): SourceGraphOperationResult | null {
    this.assertLive();
    const nextName = name.trim();
    if (!this.isSourceBacked || nodeId.length === 0 || nextName.length === 0) {
      return null;
    }
    return this.applyOperation({
      version: 2,
      type: 'RenameNode',
      node_id: nodeId,
      name: nextName,
    });
  }

  setNodeParam(
    nodeId: string,
    parameter: string,
    value: string,
  ): SourceGraphOperationResult | null {
    this.assertLive();
    const nextParameter = parameter.trim();
    const nextValue = value.trim();
    if (
      !this.isSourceBacked ||
      nodeId.length === 0 ||
      nextParameter.length === 0 ||
      nextValue.length === 0
    ) {
      return null;
    }
    return this.applyOperation({
      version: 2,
      type: 'SetNodeParam',
      node_id: nodeId,
      parameter: nextParameter,
      value: nextValue,
    });
  }

  disconnectPorts(
    sourceNodeId: string,
    sourcePortId: string,
    targetNodeId: string,
    targetPortId: string,
  ): SourceGraphOperationResult | null {
    this.assertLive();
    if (
      sourceNodeId.length === 0 ||
      targetNodeId.length === 0 ||
      sourcePortId.length === 0 ||
      targetPortId.length === 0
    ) {
      return null;
    }
    const operation: GraphOperation = {
      version: 2,
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

  pointerDown(nodeId: string, sx: number, sy: number): void {
    this.assertLive();
    if (this.isSourceBacked) {
      this.sourceModule().source_graph_pointer_down(this.handle, nodeId, sx, sy);
    } else {
      this.mb.pointer_down(this.handle, nodeId, sx, sy);
    }
  }

  pointerDownHandle(
    nodeId: string,
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

  pointerUp(nodeId: string, targetPortId: string, additive: boolean): void {
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

  hoverNode(nodeId: string): void {
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
