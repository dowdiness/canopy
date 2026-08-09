///| Module-private owner of Markdown Language construction and edit application.

///|
/// A verified canonical-to-portable commit with no projection metadata exposed.
pub struct PortableCommit {
  before : String
  after : String
  transform : @core.SpanEdit
} derive(Debug, Eq)

///|
pub fn PortableCommit::before(self : PortableCommit) -> String {
  self.before
}

///|
pub fn PortableCommit::after(self : PortableCommit) -> String {
  self.after
}

///|
pub fn PortableCommit::transform(self : PortableCommit) -> @core.SpanEdit {
  self.transform
}

///|
/// Portable evidence retained when source mutation succeeded but projection of
/// its accepted transform could not be completed. `after` is absent when the
/// post-commit parser/projection state could not be read safely.
pub struct PortableCommitEvidence {
  before : String
  after : String?
} derive(Debug, Eq)

///|
pub fn PortableCommitEvidence::before(self : PortableCommitEvidence) -> String {
  self.before
}

///|
pub fn PortableCommitEvidence::after(self : PortableCommitEvidence) -> String? {
  self.after
}

///|
/// Typed failures that can prevent or interrupt portable commit projection.
pub(all) enum PortableCommitIssue {
  RuntimeFailure(detail~ : String)
  ProjectionUnavailable
  ProjectionFailed(error~ : PortableProjectionError)
  UnexpectedTransformCount(count~ : Int)
} derive(Debug, Eq)

///|
/// A transaction rejection means source mutation did not occur.
pub(all) enum PortableCommitError {
  NotCommitted(issue~ : PortableCommitIssue)
  EditRejected(error~ : @core.EditError)
}

///|
/// The complete outcome of one portable Markdown commit transaction.
pub(all) enum PortableCommitOutcome {
  Applied(PortableCommit)
  Unchanged(source~ : String)
  Committed(evidence~ : PortableCommitEvidence, issue~ : PortableCommitIssue)
}

///|
/// Package-private canonical and projection state used only while completing
/// one transaction. Hidden ranges and canonical coordinates never escape it.
priv struct PortableProjectionState {
  canonical : String
  portable : String
  hidden : Array[@loom.Range]
}

///|
let plain_language : @lang_runtime.Language[
  @markdown.Block,
  @md_edits.MarkdownEditOp,
  @markdown.MarkdownSemanticAttachment?,
] = make_language(false)

///|
fn make_language(
  with_attachment : Bool,
) -> @lang_runtime.Language[
  @markdown.Block,
  @md_edits.MarkdownEditOp,
  @markdown.MarkdownSemanticAttachment?,
] {
  @lang_runtime.Language::Language(
    parse=(source_id, source, runtime) => {
      @loom.new_parser(source_id, source, @markdown.markdown_grammar, runtime?)
    },
    project=(parser, hints) => {
      let memos = @md_proj.build_markdown_projection_memos(
        parser,
        identity_hints=hints,
      )
      let attachment = if with_attachment {
        Some(
          @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
            parser,
          ),
        )
      } else {
        None
      }
      (memos.0, memos.1, memos.2, attachment)
    },
    edit=(op, ctx) => {
      match
        @md_edits.compute_markdown_edit(
          op,
          ctx.source_text,
          ctx.proj_node,
          ctx.source_map,
        ) {
        Some((edits, focus_hint)) =>
          @lang_runtime.EditResult::Edits(
            edits,
            focus_hint,
            markdown_identity_hint(op),
          )
        None => @lang_runtime.EditResult::NoEdit
      }
    },
    capabilities=_ => {
      @editor.LanguageCapabilities::default().with_to_view_node((
        proj,
        source_map,
        annotations,
        source_text,
      ) => {
        @md_proj.proj_to_view_node(proj, source_map, annotations~, source_text~)
      })
    },
  )
}

///|
fn markdown_identity_hint(
  op : @md_edits.MarkdownEditOp,
) -> @core.IdentityTransform? {
  match op {
    MoveBlock(source~, ..) =>
      Some(@core.IdentityTransform::Move(subtree=source))
    _ => None
  }
}

///|
/// Construct the ordinary Markdown editor through the shared Language.
pub fn new_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> @editor.SyncEditor[@markdown.Block] raise {
  let (editor, _) = plain_language.build(
    agent_id,
    capture_timeout_ms~,
    parent_runtime?,
  )
  editor
}

///|
/// Construct a Markdown editor and semantic attachment over one live parser.
pub fn new_editor_with_semantic_attachment(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> (@editor.SyncEditor[@markdown.Block], @markdown.MarkdownSemanticAttachment) raise {
  let (editor, attachment) = make_language(true).build(
    agent_id,
    capture_timeout_ms~,
    parent_runtime?,
  )
  (editor, attachment.unwrap())
}

///|
/// Apply one Markdown structural edit and return its exact source transforms.
pub fn apply_edit(
  editor : @editor.SyncEditor[@markdown.Block],
  op : @md_edits.MarkdownEditOp,
  timestamp_ms : Int,
) -> Result[Array[@core.SpanEdit], @core.EditError] raise Failure {
  plain_language.apply_edit(editor, op, timestamp_ms)
}

///|
/// Apply one Markdown operation exactly once and return only sentinel-free
/// UTF-16 source evidence and its verified portable transform. Failures after
/// source mutation are outcomes, not edit rejections.
pub fn commit_portable_edit(
  editor : @editor.SyncEditor[@markdown.Block],
  op : @md_edits.MarkdownEditOp,
  timestamp_ms : Int,
) -> Result[PortableCommitOutcome, PortableCommitError] {
  let before = match capture_portable_projection_state(editor) {
    Ok(state) => state
    Err(issue) => return Err(PortableCommitError::NotCommitted(issue~))
  }
  let version_before = editor.get_version()
  let applied = apply_edit(editor, op, timestamp_ms) catch {
    Failure::Failure(detail) =>
      return classify_interrupted_portable_commit(
        before.portable,
        committed=editor.get_version() != version_before,
        PortableCommitIssue::RuntimeFailure(detail~),
      )
  }
  let edits = match applied {
    Ok(edits) => edits
    Err(error) => return Err(PortableCommitError::EditRejected(error~))
  }
  editor.refresh() catch {
    Failure::Failure(detail) =>
      return classify_interrupted_portable_commit(
        before.portable,
        committed=editor.get_version() != version_before,
        PortableCommitIssue::RuntimeFailure(detail~),
      )
  }
  let after = match capture_portable_projection_state(editor) {
    Ok(state) => state
    Err(issue) =>
      return classify_interrupted_portable_commit(
        before.portable,
        committed=editor.get_version() != version_before,
        issue,
      )
  }
  if edits.is_empty() && editor.get_version() == version_before {
    return Ok(PortableCommitOutcome::Unchanged(source=after.portable))
  }
  guard edits is [canonical_edit] else {
    let issue = PortableCommitIssue::UnexpectedTransformCount(
      count=edits.length(),
    )
    if editor.get_version() == version_before {
      return Err(PortableCommitError::NotCommitted(issue~))
    }
    let evidence = PortableCommitEvidence::{
      before: before.portable,
      after: Some(after.portable),
    }
    return Ok(PortableCommitOutcome::Committed(evidence~, issue~))
  }
  if before.canonical == after.canonical {
    return Ok(PortableCommitOutcome::Unchanged(source=after.portable))
  }
  let transform = match
    project_markdown_edit(
      before.canonical,
      before.hidden,
      canonical_edit,
      after.canonical,
      after.hidden,
    ) {
    Ok(transform) => transform
    Err(error) => {
      let evidence = PortableCommitEvidence::{
        before: before.portable,
        after: Some(after.portable),
      }
      let issue = PortableCommitIssue::ProjectionFailed(error~)
      return Ok(PortableCommitOutcome::Committed(evidence~, issue~))
    }
  }
  Ok(
    PortableCommitOutcome::Applied(PortableCommit::{
      before: before.portable,
      after: after.portable,
      transform,
    }),
  )
}

///|
/// Capture canonical parser state, but expose only its portable projection to
/// transaction results. The mutable range array is fresh and package-private.
fn capture_portable_projection_state(
  editor : @editor.SyncEditor[@markdown.Block],
) -> Result[PortableProjectionState, PortableCommitIssue] {
  let canonical = editor.get_text()
  let root = editor.get_proj_node() catch {
    Failure::Failure(detail) =>
      return Err(PortableCommitIssue::RuntimeFailure(detail~))
  }
  guard root is Some(root) else {
    return Err(PortableCommitIssue::ProjectionUnavailable)
  }
  let source_map = editor.get_source_map() catch {
    Failure::Failure(detail) =>
      return Err(PortableCommitIssue::RuntimeFailure(detail~))
  }
  let hidden : Array[@loom.Range] = []
  collect_hidden_sentinel_ranges(root, source_map, hidden)
  let portable = match project_source(canonical, hidden) {
    Ok(portable) => portable
    Err(error) => return Err(PortableCommitIssue::ProjectionFailed(error~))
  }
  Ok({ canonical, portable, hidden })
}

///|
/// Classify an interrupted transaction from causal-version evidence rather
/// than source equality: replacing text with the same value may still advance
/// history, while a parser failure before mutation leaves the version stable.
fn classify_interrupted_portable_commit(
  before : String,
  committed~ : Bool,
  issue : PortableCommitIssue,
) -> Result[PortableCommitOutcome, PortableCommitError] {
  if !committed {
    return Err(PortableCommitError::NotCommitted(issue~))
  }
  let evidence = PortableCommitEvidence::{ before, after: None }
  Ok(PortableCommitOutcome::Committed(evidence~, issue~))
}

///|
/// Return Markdown text with only structural empty-paragraph sentinels
/// removed. Projection and source-map failures retain the canonical source.
pub fn export_markdown_text(
  editor : @editor.SyncEditor[@markdown.Block],
) -> String {
  let source = editor.get_text()
  let root = editor.get_proj_node() catch {
    Failure::Failure(_) => return source
  }
  guard root is Some(root) else { return source }
  let source_map = editor.get_source_map() catch {
    Failure::Failure(_) => return source
  }
  let ranges : Array[@loom.Range] = []
  collect_hidden_sentinel_ranges(root, source_map, ranges)
  match project_source(source, ranges) {
    Ok(projected) => projected
    Err(_) => source
  }
}

///|
/// Collect only the token span owned by an exact sentinel paragraph.
fn collect_hidden_sentinel_ranges(
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
  out : Array[@loom.Range],
) -> Unit {
  if is_hidden_sentinel(node.kind) {
    match source_map.get_token_span(node.id(), "text") {
      Some(range) => out.push(range)
      None => ()
    }
    return
  }
  for child in node.children {
    collect_hidden_sentinel_ranges(child, source_map, out)
  }
}

///|
/// Recognize the private paragraph shape without hiding legitimate content.
fn is_hidden_sentinel(block : @markdown.Block) -> Bool {
  match block {
    Paragraph(inlines) =>
      inlines.length() == 1 &&
      (match inlines[0] {
        Text(text) => @md_sentinel.is_empty_paragraph_text(text)
        _ => false
      })
    _ => false
  }
}
