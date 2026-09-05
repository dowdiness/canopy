import { EditorView as PmView } from "prosemirror-view";
import { reconcile } from "./reconciler";
import type { ProjNodeJson } from "./types";

/** Snapshot renderer retained as the narrow Structure-mode adapter. */
export class CrdtBridge {
  private pmView: PmView | null = null;
  private broadcastFn: (() => void) | null = null;

  setBroadcast(fn: (() => void) | null): void {
    this.broadcastFn = fn;
  }

  /** Local application changes are already rendered from their supplied snapshot. */
  notifyLocalChange(): void {
    this.broadcastFn?.();
  }

  setPmView(pmView: PmView): void {
    this.pmView = pmView;
  }

  destroy(): void {
    this.pmView = null;
  }

  reconcile(snapshot: string): void {
    if (!this.pmView || !snapshot || snapshot === "null") return;
    const projJson: ProjNodeJson = JSON.parse(snapshot);
    const tr = reconcile(this.pmView.state, projJson);
    if (tr) this.pmView.dispatch(tr);
  }
}
