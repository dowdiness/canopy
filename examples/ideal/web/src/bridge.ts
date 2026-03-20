import { EditorView as PmView } from "prosemirror-view";
import { reconcile } from "./reconciler";
import type { CrdtModule, ProjNodeJson } from "./types";

/**
 * CrdtBridge — connects PM NodeViews to the CRDT backend.
 *
 * Handles:
 * - Leaf text edits (CM6 → char-at-a-time CRDT ops via source map)
 * - Token edits (lambda param, let-def name)
 * - Structural edits (delete, wrap via TreeEditOp)
 * - Remote sync (apply ops → reconcile PM)
 * - Incremental reconciliation (ProjNode diff → minimal PM transaction)
 *
 * Uses `fromExternal` meta tag to prevent echo loops in the
 * canopy-editor Web Component's dispatchTransaction.
 */
export class CrdtBridge {
  private pmView!: PmView;
  private handle: number;
  private crdt: CrdtModule;
  private reconcileRafId: number | null = null;
  private broadcastFn: (() => void) | null = null;
  private cachedSourceMap: any[] | null = null;

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

  /** Cancel pending RAF on teardown */
  destroy(): void {
    if (this.reconcileRafId !== null) {
      cancelAnimationFrame(this.reconcileRafId);
      this.reconcileRafId = null;
    }
  }

  private getSourceMap(): any[] {
    if (this.cachedSourceMap === null) {
      this.cachedSourceMap = JSON.parse(this.crdt.get_source_map_json(this.handle)) as any[];
    }
    return this.cachedSourceMap;
  }

  private invalidateSourceMap(): void {
    this.cachedSourceMap = null;
  }

  /** Called by CM6 NodeViews when leaf text changes (int_literal, var_ref, unbound_ref) */
  handleLeafEdit(nodeId: number, changes: { from: number; to: number; insert: string }[]): void {
    const smJson = this.getSourceMap();
    const entry = smJson.find((r: any) => r.node_id === nodeId);
    if (!entry) {
      console.warn("SourceMap entry not found for nodeId:", nodeId);
      this.scheduleReconcile();
      return;
    }
    const basePos: number = entry.start;
    const ts = Date.now();

    if (!this.applyCharChanges(basePos, ts, changes)) {
      // Delete failed — CM6 is out of sync with CRDT. Reconcile to resync.
      this.scheduleReconcile();
      return;
    }
    this.afterLocalEdit();
  }

  /** Called by CM6 NodeViews when a token sub-span changes (e.g. lambda param, let-def name) */
  handleTokenEdit(nodeId: number, tokenRole: string, changes: { from: number; to: number; insert: string }[]): void {
    const smJson = this.getSourceMap();
    const entry = smJson.find((r: any) => r.node_id === nodeId);
    if (!entry?.token_spans?.[tokenRole]) {
      console.warn("Token span not found:", nodeId, tokenRole);
      this.scheduleReconcile();
      return;
    }
    const basePos: number = entry.token_spans[tokenRole].start;
    const ts = Date.now();

    if (!this.applyCharChanges(basePos, ts, changes)) {
      this.scheduleReconcile();
      return;
    }
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
    if (this.reconcileRafId !== null) {
      cancelAnimationFrame(this.reconcileRafId);
      this.reconcileRafId = null;
    }
    this.reconcile();
  }

  /** Reconcile PM state from CRDT's ProjNode */
  reconcile(): void {
    this.invalidateSourceMap();
    const projJsonStr = this.crdt.get_proj_node_json(this.handle);
    if (projJsonStr === "null") return;
    const projJson: ProjNodeJson = JSON.parse(projJsonStr);
    const tr = reconcile(this.pmView.state, projJson);
    if (tr) {
      this.pmView.dispatch(tr);
    }
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
    this.invalidateSourceMap();
    if (this.broadcastFn) this.broadcastFn();
    this.scheduleReconcile();
  }

  scheduleReconcile(): void {
    if (this.reconcileRafId !== null) return;
    this.reconcileRafId = requestAnimationFrame(() => {
      this.reconcileRafId = null;
      this.reconcile();
    });
  }
}
