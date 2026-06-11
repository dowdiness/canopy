// Generic companion runtime (architecture redesign S3, Tier 2 language SPI —
// docs/decisions/2026-06-11-library-api-boundary.md). One LanguageSpec per
// language bundles the closures that differ between language families; the
// editor-construction and structural-edit bridge machinery lives here once.
// Closure record rather than a trait: MoonBit traits are Self-based without
// type parameters, and the orphan rule blocks downstream impls — closures
// also discharge per-language bounds (Eq, Show) at construction time so the
// record itself stays unbounded.

///|
/// Policy for a `compute_edit` that returns `Ok(None)` (no span edits
/// computed). Language families differ here: JSON treats an unhandled op as
/// an error; Markdown treats it as a silent no-op (e.g. merge on first
/// block).
///
/// `pub(all)`: language packages construct their policy variant when building
/// their LanguageSpec — cross-package construction is the end-state use, not
/// a migration transient (pub enum constructors are read-only cross-package).
pub(all) enum NoEditPolicy {
  ErrorUnhandled
  SilentNoOp
}

///|
/// Per-language capability record for the generic companion runtime.
///
/// `T` is the language's projection payload (e.g. JsonValue, Block, Term);
/// `Op` is its structural-edit operation enum. `describe_op` renders an op
/// for the `ErrorUnhandled` message — a closure field rather than a `Show`
/// bound so the record stays unbounded.
pub struct LanguageSpec[T, Op] {
  priv make_parser : (String, @incr.Runtime?) -> @loom.Parser[T]
  priv build_memos : (@loom.Parser[T]) -> (
    @incr.Derived[@core.ProjNode[T]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]],
    @incr.Derived[@core.SourceMap],
  )
  priv compute_edit : (Op, String, @core.ProjNode[T], @core.SourceMap) -> Result[
    (Array[@core.SpanEdit], @core.FocusHint)?,
    String,
  ]
  priv describe_op : (Op) -> String
  priv no_edit_policy : NoEditPolicy
}

///|
pub fn[T, Op] LanguageSpec::LanguageSpec(
  make_parser~ : (String, @incr.Runtime?) -> @loom.Parser[T],
  build_memos~ : (@loom.Parser[T]) -> (
    @incr.Derived[@core.ProjNode[T]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]],
    @incr.Derived[@core.SourceMap],
  ),
  compute_edit~ : (Op, String, @core.ProjNode[T], @core.SourceMap) -> Result[
    (Array[@core.SpanEdit], @core.FocusHint)?,
    String,
  ],
  describe_op~ : (Op) -> String,
  no_edit_policy? : NoEditPolicy = ErrorUnhandled,
) -> LanguageSpec[T, Op] {
  { make_parser, build_memos, compute_edit, describe_op, no_edit_policy }
}

///|
/// Construct a SyncEditor from this spec (standard 3-memo pipeline).
/// Per-instance capabilities (e.g. lambda's eval/semantic closures capturing
/// instance memos) are passed here, not stored in the spec.
pub fn[T, Op] LanguageSpec::new_editor(
  self : LanguageSpec[T, Op],
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
  capabilities? : @editor.LanguageCapabilities[T] = @editor.LanguageCapabilities::default(),
) -> @editor.SyncEditor[T] {
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
  guard editor.get_proj_node() is Some(proj) else {
    return Err("no projection available")
  }
  let source_map = editor.get_source_map()
  match (self.compute_edit)(op, source, proj, source_map) {
    Ok(Some((edits, focus_hint))) => {
      editor.apply_span_edits(edits, focus_hint, timestamp_ms)
      Ok(())
    }
    Ok(None) =>
      match self.no_edit_policy {
        ErrorUnhandled => Err("unhandled edit op: " + (self.describe_op)(op))
        SilentNoOp => Ok(())
      }
    Err(msg) => Err(msg)
  }
}
