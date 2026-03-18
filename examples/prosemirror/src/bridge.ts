import { EditorView as PmView } from "prosemirror-view";
import { Transaction } from "prosemirror-state";
import { reconcile } from "./reconciler";
import { ProjNodeJson } from "./types";

/** Type for the MoonBit CRDT FFI module imported as @moonbit/crdt */
export interface CrdtModule {
  create_editor(agentId: string): number;
  get_text(handle: number): string;
  set_text(handle: number, text: string): void;
  insert_at(handle: number, position: number, text: string, timestampMs: number): void;
  delete_at(handle: number, position: number, timestampMs: number): boolean;
  get_proj_node_json(handle: number): string;
  get_source_map_json(handle: number): string;
  get_version_json(handle: number): string;
  export_all_json(handle: number): string;
  export_since_json(handle: number, peerVersionJson: string): string;
  apply_sync_json(handle: number, syncJson: string): void;
  apply_tree_edit_json(handle: number, opJson: string, timestampMs: number): string;
  [key: string]: any;
}

export class CrdtBridge {
  private pmView!: PmView;
  private handle: number;
  private crdt: CrdtModule;
  private reconcileRafId: number | null = null;
  private broadcastFn: (() => void) | null = null;

  constructor(handle: number, crdt: CrdtModule) {
    this.handle = handle;
    this.crdt = crdt;
  }

  /** Register a broadcast callback for sync */
  setBroadcast(fn: () => void): void {
    this.broadcastFn = fn;
  }

  /** Must be called after PM EditorView is created */
  setPmView(pmView: PmView): void {
    this.pmView = pmView;
  }

  /** PM dispatchTransaction override */
  handleTransaction(tr: Transaction): void {
    if (tr.getMeta("fromCrdt")) {
      // Inbound from reconciler — apply directly
      this.pmView.updateState(this.pmView.state.apply(tr));
      return;
    }
    if (!tr.docChanged) {
      // View-only (selection, scroll, IME) — apply directly
      this.pmView.updateState(this.pmView.state.apply(tr));
      return;
    }
    // Doc-changing transaction — for now, log warning
    // Will be implemented in handleLeafEdit for CM6 edits
    console.warn("Doc-changing PM transaction intercepted (not yet routed to CRDT)");
  }

  /** Called by CM6 NodeViews when leaf text changes */
  handleLeafEdit(nodeId: number, changes: { from: number; to: number; insert: string }[]): void {
    const smJson = JSON.parse(this.crdt.get_source_map_json(this.handle));
    const entry = smJson.find((r: any) => r.node_id === nodeId);
    if (!entry) {
      console.warn("SourceMap entry not found for nodeId:", nodeId);
      return;
    }
    const basePos: number = entry.start;
    const ts = Date.now();

    if (!this.applyCharChanges(basePos, ts, changes)) return;
    this.afterLocalEdit();
  }

  /** Called by CM6 NodeViews when a token sub-span changes (e.g. lambda param, let-def name) */
  handleTokenEdit(nodeId: number, tokenRole: string, changes: { from: number; to: number; insert: string }[]): void {
    const smJson = JSON.parse(this.crdt.get_source_map_json(this.handle));
    const entry = smJson.find((r: any) => r.node_id === nodeId);
    if (!entry?.token_spans?.[tokenRole]) {
      console.warn("Token span not found:", nodeId, tokenRole);
      return;
    }
    const basePos: number = entry.token_spans[tokenRole].start;
    const ts = Date.now();

    if (!this.applyCharChanges(basePos, ts, changes)) return;
    this.afterLocalEdit();
  }

  /** Apply a structural edit (delete, wrap, etc.) via the CRDT TreeEditOp bridge */
  handleStructuralEdit(opType: string, nodeId: number, extra?: Record<string, unknown>): void {
    const opJson = JSON.stringify({ type: opType, node_id: nodeId, ...extra });
    const ts = Date.now();
    const result = this.crdt.apply_tree_edit_json(this.handle, opJson, ts);
    if (result !== "ok") {
      console.error("Structural edit failed:", result);
      return;
    }
    this.afterLocalEdit();
  }

  /** Apply remote CRDT ops and reconcile PM state */
  applyRemote(syncJson: string): void {
    this.crdt.apply_sync_json(this.handle, syncJson);
    this.reconcile();
  }

  /** Apply char-at-a-time CRDT changes. Returns false if any delete fails. */
  private applyCharChanges(
    basePos: number,
    ts: number,
    changes: { from: number; to: number; insert: string }[],
  ): boolean {
    let posOffset = 0;
    for (const change of changes) {
      const deleteLen = change.to - change.from;
      for (let i = deleteLen - 1; i >= 0; i--) {
        const ok = this.crdt.delete_at(this.handle, basePos + change.from + i + posOffset, ts);
        if (!ok) {
          console.warn("delete_at failed at", basePos + change.from + i + posOffset);
          return false;
        }
      }
      posOffset -= deleteLen;
      for (let i = 0; i < change.insert.length; i++) {
        this.crdt.insert_at(this.handle, basePos + change.from + posOffset + i, change.insert[i], ts);
      }
      posOffset += change.insert.length;
    }
    return true;
  }

  /** Called after any local edit — broadcast to peers + schedule reconcile */
  private afterLocalEdit(): void {
    if (this.broadcastFn) this.broadcastFn();
    this.scheduleReconcile();
  }

  /** Reconcile PM state from CRDT's ProjNode */
  reconcile(): void {
    const projJsonStr = this.crdt.get_proj_node_json(this.handle);
    if (projJsonStr === "null") return;
    const projJson: ProjNodeJson = JSON.parse(projJsonStr);
    const tr = reconcile(this.pmView.state, projJson);
    if (tr) {
      this.pmView.dispatch(tr);
    }
  }

  private scheduleReconcile(): void {
    if (this.reconcileRafId !== null) return;
    this.reconcileRafId = requestAnimationFrame(() => {
      this.reconcileRafId = null;
      this.reconcile();
    });
  }
}
