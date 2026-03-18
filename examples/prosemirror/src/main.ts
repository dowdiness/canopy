import * as crdt from "@moonbit/crdt";
import { EditorState } from "prosemirror-state";
import { EditorView } from "prosemirror-view";
import { editorSchema } from "./schema";
import { projNodeToDoc } from "./convert";

// Create CRDT editor with sample text
const handle = crdt.create_editor("pm-agent");
crdt.set_text(handle, "let double = λx.x + x\ndouble 5");

// Convert ProjNode to PM doc
const projJson = JSON.parse(crdt.get_proj_node_json(handle));
const doc = projNodeToDoc(projJson);

// Create PM EditorState and EditorView
const state = EditorState.create({ doc, schema: editorSchema });
const view = new EditorView(document.getElementById("editor")!, { state });

// Debug: show doc structure
document.getElementById("debug")!.textContent = doc.toString();

console.log("PM Doc:", doc.toString());
console.log("ProjNode:", JSON.stringify(projJson, null, 2));
