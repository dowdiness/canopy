import * as crdt from "@moonbit/crdt";
import { EditorState } from "prosemirror-state";
import { EditorView } from "prosemirror-view";
import { editorSchema } from "./schema";
import { projNodeToDoc } from "./convert";
import { TermLeafView } from "./leaf-view";
import { LambdaView } from "./lambda-view";
import { LetDefView } from "./let-def-view";
import { CrdtBridge } from "./bridge";

// Create CRDT editor with sample text
const handle = crdt.create_editor("pm-agent");
crdt.set_text(handle, "let double = λx.x + x\ndouble 5");

// Convert ProjNode to PM doc
const projJson = JSON.parse(crdt.get_proj_node_json(handle));
const doc = projNodeToDoc(projJson);

// Create bridge
const bridge = new CrdtBridge(handle, crdt);

// Create PM EditorState and EditorView
const state = EditorState.create({ doc, schema: editorSchema });
const view = new EditorView(document.getElementById("editor")!, {
  state,
  dispatchTransaction: (tr) => bridge.handleTransaction(tr),
  nodeViews: {
    int_literal: (node, view, getPos) => new TermLeafView(node, view, getPos, bridge),
    var_ref: (node, view, getPos) => new TermLeafView(node, view, getPos, bridge),
    unbound_ref: (node, view, getPos) => new TermLeafView(node, view, getPos, bridge),
    lambda: (node, view, getPos) => new LambdaView(node, view, getPos),
    let_def: (node, view, getPos) => new LetDefView(node, view, getPos),
  },
});

bridge.setPmView(view);

// Debug: show doc structure
document.getElementById("debug")!.textContent = doc.toString();

console.log("PM Doc:", doc.toString());
console.log("ProjNode:", JSON.stringify(projJson, null, 2));
