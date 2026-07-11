// Re-exports the stub as named exports matching the MoonBit FFI interface.
// Used as the Vite alias target for @moonbit/crdt when MoonBit build is not available.

import { stubCrdtModule } from './crdt-stub';

export const {
  create_editor_with_undo,
  create_editor,
  destroy_editor,
  get_text,
  set_text,
  set_text_and_record,
  undo_manager_undo,
  undo_manager_redo,
  undo_manager_can_undo,
  undo_manager_can_redo,
  undo_manager_set_tracking,
  undo_manager_clear,
  get_errors_json,
  get_view_tree_json,
  compute_view_patches_json,
  export_all_json,
  export_since_json,
  apply_sync_json,
  get_version_json,
  undo_and_export_json,
  redo_and_export_json,
} = stubCrdtModule;
