// Companion adapter functions for the JSON SyncEditor:
//   - constructor (`new_json_editor`)
//   - structural-edit bridge (`apply_json_edit`)
//
// Migrated to the deepened language SPI (ADR 2026-08-07): `json_lang`
// bundles parse / project / edit / capabilities; construction returns
// (SyncEditor, Unit) and errors stay structured until this boundary.

///|
/// Capability record for the JSON language family (S3 lang/runtime SPI).
/// JSON reports a no-edit (unhandled) op as an error via
/// `UnsupportedOperation` variant.
let json_lang : @lang_runtime.Language[
  @json.JsonValue,
  @json_edits.JsonEditOp,
  Unit,
] = @lang_runtime.Language::Language(
  parse=(source_id, source, runtime) => {
    @loom.new_parser(source_id, source, @json.json_grammar, runtime?)
  },
  project=(parser, _hints) => {
    let memos = @json_proj.build_json_projection_memos(parser)
    (memos.0, memos.1, memos.2, ())
  },
  edit=(op, ctx) => {
    match
      @json_edits.compute_json_edit(
        op,
        ctx.source_text,
        ctx.proj_node,
        ctx.source_map,
      ) {
      Some((edits, focus_hint)) =>
        @lang_runtime.EditResult::Edits(edits, focus_hint, None)
      None =>
        raise @core.EditError::UnsupportedOperation(
          detail="unhandled edit op: " + op.to_string(),
        )
    }
  },
  capabilities=_e => @editor.LanguageCapabilities::default(),
)

///|
/// Create a new SyncEditor for JSON documents.
/// Raises `TextError::EmptyReplicaId` when `agent_id` is empty.
/// Uses the generic 3-memo projection pipeline.
pub fn new_json_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> @editor.SyncEditor[@json.JsonValue] raise {
  let (editor, _) = json_lang.build(
    agent_id,
    capture_timeout_ms~,
    parent_runtime?,
  )
  editor
}

///|
/// Apply a structural JSON edit by computing span-level text edits
/// and routing them through the text CRDT (incremental-parser-aware).
/// Returns `Unit` + flattened message at this FFI-facing boundary.
pub fn apply_json_edit(
  editor : @editor.SyncEditor[@json.JsonValue],
  op : @json_edits.JsonEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] raise {
  match json_lang.apply_edit(editor, op, timestamp_ms) {
    Ok(_) => Ok(())
    Err(e) => Err(e.message())
  }
}
