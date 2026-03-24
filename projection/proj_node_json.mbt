// ToJson implementations for ProjNode and SourceMap.
// These enable the ProseMirror bridge to read AST structure
// and position mappings from JavaScript via FFI.

///|
pub impl[T : ToJson] ToJson for ProjNode[T] with to_json(self) {
  let children_json : Array[Json] = self.children.map(fn(c) { c.to_json() })
  {
    "node_id": self.node_id,
    "kind": self.kind.to_json(),
    "children": children_json,
    "start": self.start,
    "end": self.end,
  }
}

///|
pub impl ToJson for SourceMap with to_json(self) {
  let entries : Array[Json] = []
  for node_id, range in self.node_to_range {
    let entry : Map[String, Json] = {}
    entry["node_id"] = node_id.0.to_json()
    entry["start"] = range.start.to_json()
    entry["end"] = range.end.to_json()
    // Include token spans if present for this node
    match self.token_spans.get(node_id) {
      Some(roles) => {
        let token_spans_json : Map[String, Json] = {}
        for role, span in roles {
          token_spans_json[role] = { "start": span.start, "end": span.end }
        }
        entry["token_spans"] = Json::object(token_spans_json)
      }
      None => ()
    }
    entries.push(Json::object(entry))
  }
  Json::array(entries)
}
