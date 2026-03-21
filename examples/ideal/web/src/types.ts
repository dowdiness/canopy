export interface ProjNodeJson {
  node_id: number;
  kind: any[];
  children: ProjNodeJson[];
  start: number;
  end: number;
}

export type TermKindTag =
  | "Int"
  | "Var"
  | "Lam"
  | "App"
  | "Bop"
  | "If"
  | "Module"
  | "Unit"
  | "Unbound"
  | "Error";

const VALID_TAGS = new Set<string>(["Int", "Var", "Lam", "App", "Bop", "If", "Module", "Unit", "Unbound", "Error"]);

export function getKindTag(kind: any[]): TermKindTag {
  if (!Array.isArray(kind) || kind.length === 0) {
    throw new Error(`Invalid kind: expected non-empty array, got ${JSON.stringify(kind)}`);
  }
  const tag = kind[0];
  if (!VALID_TAGS.has(tag)) {
    throw new Error(`Unknown kind tag: "${tag}"`);
  }
  return tag as TermKindTag;
}

export interface CrdtModule {
  create_editor_with_undo(agentId: string, timeoutMs: number): number;
  get_text(handle: number): string;
  set_text(handle: number, text: string): void;
  set_text_and_record?(handle: number, text: string, timestampMs: number): void;
  get_proj_node_json(handle: number): string;
  get_source_map_json(handle: number): string;
  get_errors_json(handle: number): string;
  get_version_json(handle: number): string;
  insert_at(handle: number, pos: number, char: string, timestamp: number): void;
  delete_at(handle: number, pos: number, timestamp: number): boolean;
  undo_manager_undo(handle: number): boolean;
  undo_manager_redo(handle: number): boolean;
  apply_sync_json(handle: number, json: string): void;
  export_all_json(handle: number): string;
  export_since_json(handle: number, peerVersionJson: string): string;
  apply_tree_edit_json(handle: number, opJson: string, timestampMs: number): string;
  ephemeral_encode_all(handle: number): Uint8Array;
  ephemeral_apply(handle: number, data: Uint8Array): void;
  ephemeral_set_presence(handle: number, name: string, color: string): void;
  ephemeral_set_presence_with_selection(handle: number, name: string, color: string, selStart: number, selEnd: number): void;
  ephemeral_delete_presence(handle: number): void;
  ephemeral_get_peer_cursors_json(handle: number): string;
  ephemeral_remove_outdated(handle: number): void;
  [key: string]: any;
}
