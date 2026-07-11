// Type declaration for the MoonBit CRDT module.
// The actual module is resolved via Vite alias at build time.
// At tsc time, this declaration provides the types.
declare module '@moonbit/crdt' {
  export function create_editor_with_undo(agent_id: string, capture_timeout_ms: number): number;
  export function create_editor(agent_id: string): number;
  export function destroy_editor(handle: number): void;
  export function get_text(handle: number): string;
  export function set_text(handle: number, new_text: string): void;
  export function set_text_and_record(handle: number, new_text: string, timestamp_ms: number): void;
  export function undo_manager_undo(handle: number): boolean;
  export function undo_manager_redo(handle: number): boolean;
  export function undo_manager_can_undo(handle: number): boolean;
  export function undo_manager_can_redo(handle: number): boolean;
  export function undo_manager_set_tracking(handle: number, enabled: boolean): void;
  export function undo_manager_clear(handle: number): void;
  export function get_errors_json(handle: number): string;
  export function get_view_tree_json(handle: number): string;
  export function compute_view_patches_json(handle: number): string;
  export function export_all_json(handle: number): string;
  export function export_since_json(handle: number, peer_version_json: string): string;
  export function apply_sync_json(handle: number, sync_json: string): string;
  export function get_version_json(handle: number): string;
  export function undo_and_export_json(handle: number): string;
  export function redo_and_export_json(handle: number): string;
}
