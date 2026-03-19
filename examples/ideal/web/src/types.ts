export interface CrdtModule {
  create_editor_with_undo(agentId: string, timeoutMs: number): number;
  get_text(handle: number): string;
  get_proj_node_json(handle: number): string;
  get_source_map_json(handle: number): string;
  get_errors_json(handle: number): string;
  insert_at(handle: number, pos: number, char: string, timestamp: number): void;
  delete_at(handle: number, pos: number, timestamp: number): boolean;
  undo_manager_undo(handle: number): boolean;
  undo_manager_redo(handle: number): boolean;
  apply_sync_json(handle: number, json: string): void;
  export_all_json(handle: number): string;
  get_version_json(handle: number): string;
}

export interface ProjNodeJson {
  id: string;
  kind: string;
  label: string;
  span: [number, number];
  children: ProjNodeJson[];
}
