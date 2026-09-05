import { EditorView as PmView } from "prosemirror-view";
import { reconcile } from "./reconciler";
import type { CrdtModule, ProjNodeJson } from "./types";

/**
 * CrdtBridge — connects PM NodeViews to the CRDT backend.
 *
 * Handles:
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
    const projJsonStr = this.crdt.get_proj_node_json(this.handle);
    if (projJsonStr === "null") return;
    const projJson: ProjNodeJson = JSON.parse(projJsonStr);
    const tr = reconcile(this.pmView.state, projJson);
    if (tr) {
      this.pmView.dispatch(tr);
    }
  }

  /** Called after any local edit — broadcast to peers + schedule reconcile */
  private afterLocalEdit(): void {
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
