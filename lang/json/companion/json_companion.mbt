// Companion adapter functions for the JSON SyncEditor:
//   - constructor (`new_json_editor`)
//   - structural-edit bridge (`apply_json_edit`)

///|
/// Capability record for the JSON language family (S3 lang/runtime SPI).
/// JSON reports a no-edit (unhandled) op as an error, preserving the
/// pre-migration "unhandled edit op: ..." message.
let json_spec : @lang_runtime.LanguageSpec[
  @json.JsonValue,
  @json_edits.JsonEditOp,
] = @lang_runtime.LanguageSpec::LanguageSpec(
  make_parser=fn(s, rt) { @loom.new_parser(s, @json.json_grammar, runtime?=rt) },
  build_memos=@json_proj.build_json_projection_memos,
  compute_edit=@json_edits.compute_json_edit,
  on_no_edit=fn(op) { Err("unhandled edit op: " + op.to_string()) },
)

///|
/// Create a new SyncEditor for JSON documents.
/// Uses the generic 3-memo pipeline (no ModuleProjection).
pub fn new_json_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> @editor.SyncEditor[@json.JsonValue] {
  json_spec.new_editor(agent_id, capture_timeout_ms~, parent_runtime?)
}

///|
/// Apply a structural JSON edit by computing span-level text edits
/// and routing them through the text CRDT (incremental-parser-aware).
pub fn apply_json_edit(
  editor : @editor.SyncEditor[@json.JsonValue],
  op : @json_edits.JsonEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  json_spec.apply_edit(editor, op, timestamp_ms)
}
