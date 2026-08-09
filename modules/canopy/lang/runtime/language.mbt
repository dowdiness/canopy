// Deepened generic language SPI (ADR 2026-08-07): one `Language` per
// language family bundles the closures that differ between languages; the
// editor-construction and structural-edit bridge machinery lives here once.
//
// Compared to the superseded `LanguageSpec`, this record:
//   - returns a language-owned extras value `E` alongside the editor at
//     construction (no caller-threaded Ref side-channels),
//   - carries structured `EditError`s and the applied `SpanEdit` trace out
//     of the apply path,
//   - makes per-op identity hints first-class in the edit result,
//   - keeps the edit-port signature uniform so moves are ordinary edit
//     computation (Lambda `Drop` selects its binding-row or `compute_move`
//     policy, Markdown `MoveBlock` uses `compute_move_block`).
//
// Closure record rather than a trait: MoonBit traits are Self-based without
// type parameters, and the orphan rule blocks downstream impls — closures
// also discharge per-language bounds (Eq, Show) at construction time so the
// record itself stays unbounded.

///|
/// Language-neutral context the framework builds before invoking the edit
/// port. `resolve` is bound-free (map lookup + range lookup need no bounds
/// on `T`), so languages never reimplement node resolution.
pub(all) struct EditContext[T] {
  source_text : String
  source_map : @core.SourceMap
  registry : Map[@core.NodeId, @core.ProjNode[T]]
  /// Non-optional: the framework returns `ProjectionUnavailable` before
  /// invoking language code when no projection root exists.
  proj_node : @core.ProjNode[T]
}

///|
/// Resolve a node id to its projection node and source range.
/// Raises `NodeNotInSourceMap` / `NodeNotInRegistry`.
pub fn[T] EditContext::resolve(
  self : EditContext[T],
  node_id : @core.NodeId,
) -> (@core.ProjNode[T], @loom_core.Range) raise @core.EditError {
  guard self.source_map.get_range(node_id) is Some(range) else {
    raise @core.EditError::NodeNotInSourceMap(action="Resolve", node_id~)
  }
  guard self.registry.get(node_id) is Some(node) else {
    raise @core.EditError::NodeNotInRegistry(action="Resolve", node_id~)
  }
  (node, range)
}

///|
/// The three possible outcomes of structural-edit computation.
///
/// `Edits` carries the span edits, the cursor `FocusHint`, and an optional
/// identity transform for projection-ID preservation across the edit
/// (`Opaque` degrades to LCS matching — e.g. Lambda `Drop`).
/// `NoEdit` is the language's silent no-op (e.g. Markdown merge on first
/// block). Languages that treat an unhandled op as an error raise
/// `EditError::UnsupportedOperation` from the edit closure instead.
pub(all) enum EditResult {
  Edits(Array[@core.SpanEdit], @core.FocusHint, @core.IdentityTransform?)
  NoEdit
}

///|
/// Per-language capability record for the generic companion runtime.
///
/// `T` is the language's projection payload (e.g. JsonValue, Block, Term);
/// `Op` is its structural-edit operation enum; `E` is the language-owned
/// extras value returned alongside the editor at construction (companion
/// memos, semantic attachments — `Unit` for languages without extras).
///
/// `project` receives the parser and an opaque consumer for the editor-owned
/// identity-hint queue, then returns the 3 standard
/// projection memos plus `E`. `edit` computes span edits from an
/// `EditContext` the framework builds. `capabilities` builds the view
/// pipeline closures from the freshly constructed `E` — this ordering (data
/// before behavior) is what eliminates construction-time Ref side-channels.
pub struct Language[T, Op, E] {
  priv parse : (@loom_core.SourceId, String, @incr.Runtime?) -> @loom.Parser[T] raise Failure
  priv project : (@loom.Parser[T], @core.IdentityHintConsumer) -> (
    @incr.Derived[@core.ProjNode[T]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]],
    @incr.Derived[@core.SourceMap],
    E,
  )
  priv edit : (Op, EditContext[T]) -> EditResult raise @core.EditError
  priv capabilities : (E) -> @editor.LanguageCapabilities[T]
}

///|
pub fn[T, Op, E] Language::Language(
  parse~ : (@loom_core.SourceId, String, @incr.Runtime?) -> @loom.Parser[T] raise Failure,
  project~ : (@loom.Parser[T], @core.IdentityHintConsumer) -> (
    @incr.Derived[@core.ProjNode[T]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]],
    @incr.Derived[@core.SourceMap],
    E,
  ),
  edit~ : (Op, EditContext[T]) -> EditResult raise @core.EditError,
  capabilities~ : (E) -> @editor.LanguageCapabilities[T],
) -> Language[T, Op, E] {
  { parse, project, edit, capabilities }
}

///|
/// Construct a `SyncEditor` from this language definition, returning the
/// language-owned extras alongside it. The framework owns construction
/// order: parser → memos + extras → capabilities → editor.
/// Raises `TextError::EmptyReplicaId` when `agent_id` is empty.
pub fn[T, Op, E] Language::build(
  self : Language[T, Op, E],
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> (@editor.SyncEditor[T], E) raise {
  @editor.SyncEditor::new_with_builder(
    agent_id,
    self.parse,
    fn(parser, hints) {
      let (cached_proj_node, registry_memo, source_map_memo, extras) = (self.project)(
        parser, hints,
      )
      (
        cached_proj_node,
        registry_memo,
        source_map_memo,
        (self.capabilities)(extras),
        extras,
      )
    },
    capture_timeout_ms~,
    parent_runtime?,
  )
}

///|
/// Bridge a structural edit op into the text CRDT: compute span-level edits
/// via the language's edit port, then apply them through
/// `SyncEditor::apply_span_edits` (incremental-parser-aware, recorded for
/// undo, cursor per `FocusHint`, identity hint threaded). Returns the
/// applied `SpanEdit` trace for callers that instrument patches.
///
/// A resolved legality failure (`InvalidTarget`) invalidates any previously
/// queued identity hint before the error escapes; node-resolution failures do
/// not. Errors stay structured (`core.EditError`); mapping to the user-facing
/// `TreeEditError` happens at the editor/FFI boundary, not here.
pub fn[T : Eq, Op, E] Language::apply_edit(
  self : Language[T, Op, E],
  editor : @editor.SyncEditor[T],
  op : Op,
  timestamp_ms : Int,
) -> Result[Array[@core.SpanEdit], @core.EditError] raise Failure {
  let projection = editor.get_proj_node()
  let source_map = editor.get_source_map()
  let registry = editor.get_registry()
  let computed : Result[EditResult, @core.EditError] = Ok(
    {
      guard projection is Some(proj) else {
        raise @core.EditError::ProjectionUnavailable
      }
      let ctx : EditContext[T] = {
        source_text: editor.get_text(),
        source_map,
        registry,
        proj_node: proj,
      }
      (self.edit)(op, ctx)
    },
  ) catch {
    error => Err(error)
  }
  match computed {
    Err(@core.EditError::InvalidTarget(detail~)) => {
      editor.invalidate_pending_identity_hints()
      Err(@core.EditError::InvalidTarget(detail~))
    }
    Err(error) => Err(error)
    Ok(Edits(edits, focus_hint, hint)) => {
      editor.apply_span_edits(edits, focus_hint, timestamp_ms, hint?)
      Ok(edits)
    }
    Ok(NoEdit) => Ok([])
  }
}
