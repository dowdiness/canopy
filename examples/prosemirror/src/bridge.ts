import { EditorView as PmView } from "prosemirror-view";
import { Transaction } from "prosemirror-state";
import { reconcile } from "./reconciler";
import { ProjNodeJson } from "./types";

export class CrdtBridge {
  private pmView!: PmView;
  private handle: number;
  private crdt: any;
  private reconcileRafId: number | null = null;

  constructor(handle: number, crdt: any) {
    this.handle = handle;
    this.crdt = crdt;
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

    // Process changes sequentially, tracking position offset
    let posOffset = 0;
    for (const change of changes) {
      const deleteLen = change.to - change.from;
      // Delete in reverse order to preserve positions
      for (let i = deleteLen - 1; i >= 0; i--) {
        this.crdt.delete_at(this.handle, basePos + change.from + i + posOffset, ts);
      }
      posOffset -= deleteLen;
      // Insert character-at-a-time
      for (let i = 0; i < change.insert.length; i++) {
        this.crdt.insert_at(this.handle, basePos + change.from + posOffset + i, change.insert[i], ts);
      }
      posOffset += change.insert.length;
    }

    // Schedule reconcile on next frame
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
