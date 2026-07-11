// Typed wrapper around MoonBit CRDT FFI exports.
//
// Abstracts the raw JS module import so the rest of the app deals with
// typed functions instead of dynamic imports and string results.
//
// The Vite alias resolves `@moonbit/crdt` to either the real MoonBit build
// (when `moon build --target js` has been run) or the in-memory stub module.
// The import is static, so the module is available synchronously.

import * as crdtRaw from '@moonbit/crdt';

export interface CrdtModule {
  create_editor_with_undo(agent_id: string, capture_timeout_ms: number): number;
  create_editor(agent_id: string): number;
  destroy_editor(handle: number): void;
  get_text(handle: number): string;
  set_text(handle: number, new_text: string): void;
  set_text_and_record(handle: number, new_text: string, timestamp_ms: number): void;
  undo_manager_undo(handle: number): boolean;
  undo_manager_redo(handle: number): boolean;
  undo_manager_can_undo(handle: number): boolean;
  undo_manager_can_redo(handle: number): boolean;
  undo_manager_set_tracking(handle: number, enabled: boolean): void;
  undo_manager_clear(handle: number): void;
  get_errors_json(handle: number): string;
  get_view_tree_json(handle: number): string;
  compute_view_patches_json(handle: number): string;
  export_all_json(handle: number): string;
  export_since_json(handle: number, peer_version_json: string): string;
  apply_sync_json(handle: number, sync_json: string): string;
  get_version_json(handle: number): string;
  undo_and_export_json(handle: number): string;
  redo_and_export_json(handle: number): string;
}

const crdtModule: CrdtModule = crdtRaw as unknown as CrdtModule;

/**
 * Get the CRDT module (synchronous — available immediately).
 */
export function getCrdtModule(): CrdtModule {
  return crdtModule;
}

/**
 * Editor handle wrapper — provides a typed, object-oriented API
 * around the handle-based FFI.
 */
export class EditorHandle {
  readonly handle: number;
  private readonly crdt: CrdtModule;

  constructor(crdt: CrdtModule, agentId: string, undoEnabled = true, captureTimeoutMs = 300) {
    this.crdt = crdt;
    this.handle = undoEnabled
      ? crdt.create_editor_with_undo(agentId, captureTimeoutMs)
      : crdt.create_editor(agentId);
  }

  destroy(): void {
    this.crdt.destroy_editor(this.handle);
  }

  getText(): string {
    return this.crdt.get_text(this.handle);
  }

  setText(text: string): void {
    this.crdt.set_text(this.handle, text);
  }

  setTextAndRecord(text: string, timestampMs?: number): void {
    this.crdt.set_text_and_record(this.handle, text, timestampMs ?? Date.now());
  }

  undo(): boolean {
    return this.crdt.undo_manager_undo(this.handle);
  }

  redo(): boolean {
    return this.crdt.undo_manager_redo(this.handle);
  }

  canUndo(): boolean {
    return this.crdt.undo_manager_can_undo(this.handle);
  }

  canRedo(): boolean {
    return this.crdt.undo_manager_can_redo(this.handle);
  }

  setTracking(enabled: boolean): void {
    this.crdt.undo_manager_set_tracking(this.handle, enabled);
  }

  clearUndo(): void {
    this.crdt.undo_manager_clear(this.handle);
  }

  getErrorsJson(): string {
    return this.crdt.get_errors_json(this.handle);
  }

  getViewTreeJson(): string {
    return this.crdt.get_view_tree_json(this.handle);
  }

  computeViewPatchesJson(): string {
    return this.crdt.compute_view_patches_json(this.handle);
  }

  exportAllJson(): string {
    return this.crdt.export_all_json(this.handle);
  }

  exportSinceJson(peerVersionJson: string): string {
    return this.crdt.export_since_json(this.handle, peerVersionJson);
  }

  applySyncJson(syncJson: string): string {
    return this.crdt.apply_sync_json(this.handle, syncJson);
  }

  getVersionJson(): string {
    return this.crdt.get_version_json(this.handle);
  }

  undoAndExportJson(): string {
    return this.crdt.undo_and_export_json(this.handle);
  }

  redoAndExportJson(): string {
    return this.crdt.redo_and_export_json(this.handle);
  }
}
