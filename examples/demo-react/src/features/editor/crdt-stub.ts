// Stub CRDT module for development/testing without MoonBit build.
//
// Provides the same API as the real MoonBit FFI module but with an in-memory
// implementation. Used as a fallback when @moonbit/crdt is not available.

import type { CrdtModule } from './crdt-api';

interface EditorState {
  text: string;
  undoStack: string[];
  redoStack: string[];
  tracking: boolean;
  version: number;
}

const editors = new Map<number, EditorState>();
let nextHandle = 1;

function getEditor(handle: number): EditorState | undefined {
  return editors.get(handle);
}

export const stubCrdtModule: CrdtModule = {
  create_editor_with_undo(_agent_id: string, _capture_timeout_ms: number): number {
    const handle = nextHandle++;
    editors.set(handle, {
      text: '',
      undoStack: [],
      redoStack: [],
      tracking: true,
      version: 0,
    });
    return handle;
  },

  create_editor(_agent_id: string): number {
    const handle = nextHandle++;
    editors.set(handle, {
      text: '',
      undoStack: [],
      redoStack: [],
      tracking: false,
      version: 0,
    });
    return handle;
  },

  destroy_editor(handle: number): void {
    editors.delete(handle);
  },

  get_text(handle: number): string {
    return getEditor(handle)?.text ?? '';
  },

  set_text(handle: number, new_text: string): void {
    const ed = getEditor(handle);
    if (ed) ed.text = new_text;
  },

  set_text_and_record(handle: number, new_text: string, _timestamp_ms: number): void {
    const ed = getEditor(handle);
    if (!ed) return;
    if (ed.tracking && new_text !== ed.text) {
      ed.undoStack.push(ed.text);
      ed.redoStack.length = 0;
    }
    ed.text = new_text;
    ed.version++;
  },

  undo_manager_undo(handle: number): boolean {
    const ed = getEditor(handle);
    if (!ed || ed.undoStack.length === 0) return false;
    ed.redoStack.push(ed.text);
    ed.text = ed.undoStack.pop()!;
    ed.version++;
    return true;
  },

  undo_manager_redo(handle: number): boolean {
    const ed = getEditor(handle);
    if (!ed || ed.redoStack.length === 0) return false;
    ed.undoStack.push(ed.text);
    ed.text = ed.redoStack.pop()!;
    ed.version++;
    return true;
  },

  undo_manager_can_undo(handle: number): boolean {
    return (getEditor(handle)?.undoStack.length ?? 0) > 0;
  },

  undo_manager_can_redo(handle: number): boolean {
    return (getEditor(handle)?.redoStack.length ?? 0) > 0;
  },

  undo_manager_set_tracking(handle: number, enabled: boolean): void {
    const ed = getEditor(handle);
    if (ed) {
      ed.tracking = enabled;
    }
  },

  undo_manager_clear(handle: number): void {
    const ed = getEditor(handle);
    if (ed) {
      ed.undoStack.length = 0;
      ed.redoStack.length = 0;
    }
  },

  get_errors_json(_handle: number): string {
    return '[]';
  },

  get_view_tree_json(_handle: number): string {
    return 'null';
  },

  compute_view_patches_json(_handle: number): string {
    return '[]';
  },

  export_all_json(handle: number): string {
    const ed = getEditor(handle);
    if (!ed) return '{"ops":[],"heads":[]}';
    // Encode the text as a simple sync message for the stub
    return JSON.stringify({
      ops: [{ type: 'snapshot', text: ed.text, version: ed.version }],
      heads: [ed.version],
    });
  },

  export_since_json(handle: number, _peer_version_json: string): string {
    // Same as export_all for the stub
    return stubCrdtModule.export_all_json(handle);
  },

  apply_sync_json(handle: number, sync_json: string): string {
    const ed = getEditor(handle);
    if (!ed) return '{"error":"invalid handle"}';
    try {
      const msg = JSON.parse(sync_json);
      if (msg.ops && msg.ops.length > 0) {
        const lastOp = msg.ops[msg.ops.length - 1];
        if (lastOp.type === 'snapshot' && typeof lastOp.text === 'string') {
          // Apply snapshot — don't record in undo (it's a remote change)
          const wasTracking = ed.tracking;
          ed.tracking = false;
          ed.text = lastOp.text;
          ed.version = Math.max(ed.version, lastOp.version ?? 0);
          ed.tracking = wasTracking;
        }
      }
      return 'ok';
    } catch {
      return '{"error":"parse error"}';
    }
  },

  get_version_json(handle: number): string {
    const ed = getEditor(handle);
    return JSON.stringify(ed?.version ?? 0);
  },

  undo_and_export_json(handle: number): string {
    const ed = getEditor(handle);
    if (!ed || ed.undoStack.length === 0) return '';
    stubCrdtModule.undo_manager_undo(handle);
    return stubCrdtModule.export_all_json(handle);
  },

  redo_and_export_json(handle: number): string {
    const ed = getEditor(handle);
    if (!ed || ed.redoStack.length === 0) return '';
    stubCrdtModule.undo_manager_redo(handle);
    return stubCrdtModule.export_all_json(handle);
  },
};
