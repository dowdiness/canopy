import { Transaction } from "prosemirror-state";
import { EditorState } from "prosemirror-state";
import { projNodeToDoc } from "./convert";
import { ProjNodeJson } from "./types";

export function reconcile(
  state: EditorState,
  newProj: ProjNodeJson,
): Transaction | null {
  const newDoc = projNodeToDoc(newProj);
  const oldDoc = state.doc;

  // Full-doc replace strategy.
  // WARNING: This destroys all CM6 NodeView instances, causing focus loss.
  // Phase 5 (Task 5.2) replaces with subtree diffing.
  if (oldDoc.eq(newDoc)) return null;

  const tr = state.tr;
  tr.replaceWith(0, oldDoc.content.size, newDoc.content);
  tr.setMeta("fromCrdt", true);
  return tr;
}
