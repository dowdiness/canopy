import { EditorView as PmView } from "prosemirror-view";
import { canopyEditTimestampMs } from "./edit-clock";
import { reconcile } from "./reconciler";
import type { CrdtModule, ProjNodeJson } from "./types";

/**
 * CrdtBridge — connects PM NodeViews to the CRDT backend.
 *
 * Handles:
 * - Leaf text edits (CM6 → bulk-splice via handle_text_intent + source map)
 * - Token edits (lambda param, let-def name)
 * - Structural edits (delete, wrap via TreeEditOp)
 * - Remote sync (apply ops → reconcile PM)
 * - Incremental reconciliation (ProjNode diff → minimal PM transaction)
 *
 * Uses `fromExternal` meta tag to prevent echo loops in the
 * canopy-editor Web Component's dispatchTransaction.
 */
export class CrdtBridge {
  private pmView: PmView | null = null;
  private handle: number;
  private crdt: CrdtModule;
  private reconcileRafId: number | null = null;
  private broadcastFn: (() => void) | null = null;
  private cachedSourceMap: Map<number, any> | null = null;

  constructor(handle: number, crdt: CrdtModule) {
    this.handle = handle;
    this.crdt = crdt;
  }

  /** Register a broadcast callback for sync */
  setBroadcast(fn: (() => void) | null): void {
    this.broadcastFn = fn;
  }

  /** Notify the bridge that the CRDT changed outside the PM edit path. */
  notifyLocalChange(): void {
    this.afterLocalEdit();
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

  private getSourceMap(): Map<number, any> {
    if (this.cachedSourceMap === null) {
      const entries = JSON.parse(this.crdt.get_source_map_json(this.handle)) as any[];
      this.cachedSourceMap = new Map(entries.map((r: any) => [r.node_id, r]));
    }
    return this.cachedSourceMap;
  }

  private invalidateSourceMap(): void {
    this.cachedSourceMap = null;
  }

  /** Called by CM6 NodeViews when leaf text changes (int_literal, var_ref, unbound_ref) */
  handleLeafEdit(nodeId: number, changes: { from: number; to: number; insert: string }[]): void {
    const sm = this.getSourceMap();
    const entry = sm.get(nodeId);
    if (!entry) {
      console.warn("SourceMap entry not found for nodeId:", nodeId);
      this.scheduleReconcile();
      return;
    }
    if (!this.applySpliceChanges(entry.start, canopyEditTimestampMs(), changes)) {
      // CM6/CRDT drift — abort the batch to avoid broadcasting a clamped edit.
      this.scheduleReconcile();
      return;
    }
    this.afterLocalEdit();
  }

  /** Called by CM6 NodeViews when a token sub-span changes (e.g. lambda param, let-def name) */
  handleTokenEdit(nodeId: number, tokenRole: string, changes: { from: number; to: number; insert: string }[]): void {
    const sm = this.getSourceMap();
    const entry = sm.get(nodeId);
    if (!entry?.token_spans?.[tokenRole]) {
      console.warn("Token span not found:", nodeId, tokenRole);
      this.scheduleReconcile();
      return;
    }
    if (!this.applySpliceChanges(entry.token_spans[tokenRole].start, canopyEditTimestampMs(), changes)) {
      this.scheduleReconcile();
      return;
    }
    this.afterLocalEdit();
  }

  /** Apply a structural edit (delete, wrap, etc.) via the CRDT TreeEditOp bridge */
  handleStructuralEdit(opType: string, nodeId: number, extra?: Record<string, unknown>): void {
    const opJson = JSON.stringify({ type: opType, node_id: nodeId, ...extra });
    const ts = canopyEditTimestampMs();
    const result = this.crdt.apply_tree_edit_json(this.handle, opJson, ts);
    if (result !== "ok") {
      console.error("Structural edit failed:", result);
      return;
    }
    this.afterLocalEdit();
  }

  /** Apply remote CRDT ops and reconcile PM state */
  applyRemote(syncJson: string): string {
    const result = this.crdt.apply_sync_json(this.handle, syncJson);
    if (result !== "ok") return result;
    if (this.reconcileRafId !== null) {
      cancelAnimationFrame(this.reconcileRafId);
      this.reconcileRafId = null;
    }
    this.reconcile();
    return "ok";
  }

  /** Reconcile PM state from CRDT's ProjNode */
  reconcile(): void {
    if (!this.pmView) return; // PM may be destroyed (text mode)
    this.invalidateSourceMap();
    const projJsonStr = this.crdt.get_proj_node_json(this.handle);
    if (projJsonStr === "null") return;
    const projJson: ProjNodeJson = JSON.parse(projJsonStr);
    const tr = reconcile(this.pmView.state, projJson);
    if (tr) {
      this.pmView.dispatch(tr);
    }
  }

  /**
   * Apply CM6 changes to the CRDT as bulk splices via `handle_text_intent_checked`.
   *
   * `iterChanges` emits non-overlapping ranges in old-doc order, so each
   * subsequent call must be shifted by the cumulative net delta of prior
   * splices in the same batch (matches the offset bookkeeping the prior
   * per-char loop used).
   *
   * Returns false on drift: `apply_text_edit_internal` would silently clamp
   * an out-of-bounds index, and the bridge would then broadcast that clamped
   * edit to peers before reconcile runs. The checked variant rejects the
   * splice instead, mirroring the old `delete_at`-returns-false recovery path.
   *
   * A multi-change batch where splice K fails leaves splices 0..K-1 applied
   * to the CRDT but un-broadcast on this edit; the next successful edit's
   * `export_since_json` broadcast carries them as part of the CRDT delta.
   * This matches the prior per-char loop's behavior — preserved, not new.
   */
  private applySpliceChanges(
    basePos: number,
    ts: number,
    changes: { from: number; to: number; insert: string }[],
  ): boolean {
    let posOffset = 0;
    for (const change of changes) {
      const deleteLen = change.to - change.from;
      const ok = this.crdt.handle_text_intent_checked(
        this.handle,
        basePos + change.from + posOffset,
        deleteLen,
        change.insert,
        ts,
      );
      if (!ok) {
        console.warn(
          "handle_text_intent_checked drift at",
          basePos + change.from + posOffset,
          "deleteLen=", deleteLen,
        );
        return false;
      }
      posOffset += change.insert.length - deleteLen;
    }
    return true;
  }

  /** Called after any local edit — broadcast to peers + schedule reconcile */
  private afterLocalEdit(): void {
    this.invalidateSourceMap();
    if (this.broadcastFn) this.broadcastFn();
    this.scheduleReconcile();
  }

  private scheduleReconcile(): void {
    if (this.reconcileRafId !== null) return;
    this.reconcileRafId = requestAnimationFrame(() => {
      this.reconcileRafId = null;
      this.reconcile();
    });
  }
}
