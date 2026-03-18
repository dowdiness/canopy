import * as crdt from "@moonbit/crdt";

const handle = crdt.create_editor("pm-agent");
crdt.set_text(handle, "let double = λx.x + x\ndouble 5");

console.log("Text:", crdt.get_text(handle));

const projJson = crdt.get_proj_node_json(handle);
console.log("ProjNode JSON:", projJson);

const smJson = crdt.get_source_map_json(handle);
console.log("SourceMap JSON:", smJson);

document.getElementById("debug")!.textContent = JSON.stringify(
  JSON.parse(projJson), null, 2
);
