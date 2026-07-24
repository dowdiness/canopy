// Generic companion runtime (architecture redesign S3, Tier 2 language SPI —
// docs/decisions/2026-06-11-library-api-boundary.md). One LanguageSpec per
// language bundles the closures that differ between language families; the
// editor-construction and structural-edit bridge machinery lives here once.
// Closure record rather than a trait: MoonBit traits are Self-based without
// type parameters, and the orphan rule blocks downstream impls — closures
// also discharge per-language bounds (Eq, Show) at construction time so the
// record itself stays unbounded.

///|
/// Per-language capability record for the generic companion runtime.
///
/// `T` is the language's projection payload (e.g. JsonValue, Block, Term);
/// `Op` is its structural-edit operation enum. `on_no_edit` answers "what
/// should this language do when `compute_edit` produced no span edits
/// (`None`)? — JSON reports an unhandled-op error, Markdown treats it
/// as a silent no-op (e.g. merge on first block). A closure field rather
/// than a policy enum + `Show` bound, so the no-edit behavior (and any
/// message rendering it needs) stays language-owned and the record stays
/// unbounded.
pub struct LanguageSpec[T, Op] {
  priv make_parser : (String, @incr.Runtime?) -> @loom.Parser[T]
  priv build_memos : (@loom.Parser[T]) -> (
    @incr.Derived[@core.ProjNode[T]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]],
    @incr.Derived[@core.SourceMap],
  )
  priv compute_edit : (Op, String, @core.ProjNode[T], @core.SourceMap) -> (
    Array[@core.SpanEdit],
    @core.FocusHint,
  )? raise @core.EditError
  priv on_no_edit : (Op) -> Unit raise @core.EditError
}

///|
pub fn[T, Op] LanguageSpec::LanguageSpec(
  make_parser~ : (String, @incr.Runtime?) -> @loom.Parser[T],
  build_memos~ : (@loom.Parser[T]) -> (
    @incr.Derived[@core.ProjNode[T]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]],
    @incr.Derived[@core.SourceMap],
  ),
  compute_edit~ : (Op, String, @core.ProjNode[T], @core.SourceMap) -> (
    Array[@core.SpanEdit],
    @core.FocusHint,
  )? raise @core.EditError,
  on_no_edit~ : (Op) -> Unit raise @core.EditError,
) -> LanguageSpec[T, Op] {
  { make_parser, build_memos, compute_edit, on_no_edit }
}

///|
/// Construct a SyncEditor from this spec (standard 3-memo pipeline).
/// Raises `TextError::EmptyReplicaId` when `agent_id` is empty.
/// Per-instance capabilities (e.g. lambda's eval/semantic closures capturing
/// instance memos) are passed here, not stored in the spec.
pub fn[T, Op] LanguageSpec::new_editor(
  self : LanguageSpec[T, Op],
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
  capabilities? : @editor.LanguageCapabilities[T] = @editor.LanguageCapabilities::default(),
) -> @editor.SyncEditor[T] raise @text.TextError {
  @editor.SyncEditor::new_generic(
    agent_id,
    self.make_parser,
    self.build_memos,
    capture_timeout_ms~,
    parent_runtime?,
    capabilities~,
  )
}

///|
/// Bridge a structural edit op into the text CRDT: compute span-level edits
/// via the spec, then apply them through `SyncEditor::apply_span_edits`
/// (incremental-parser-aware, recorded for undo, cursor per FocusHint).
pub fn[T : Eq, Op] LanguageSpec::apply_edit(
  self : LanguageSpec[T, Op],
  editor : @editor.SyncEditor[T],
  op : Op,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let source = editor.get_text()
  let source_map = editor.get_source_map()
  try {
    guard editor.get_proj_node() is Some(proj) else {
      raise @core.EditError::ProjectionUnavailable
    }
    match (self.compute_edit)(op, source, proj, source_map) {
      Some((edits, focus_hint)) => {
        editor.apply_span_edits(edits, focus_hint, timestamp_ms)
        Ok(())
      }
      None => {
        (self.on_no_edit)(op)
        Ok(())
      }
    }
  } catch {
    e => Err(e.message())
  }
}
