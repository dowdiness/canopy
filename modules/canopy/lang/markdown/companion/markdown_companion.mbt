///| Companion adapter functions for the Markdown SyncEditor:
///   - constructor (`new_markdown_editor`)
///   - structural-edit bridge (`apply_markdown_edit`)

///| Construct a SyncEditor[@markdown.Block] using the standard 3-memo pipeline.

///|
/// Raises `TextError::EmptyReplicaId` when `agent_id` is empty.
pub fn new_markdown_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> @editor.SyncEditor[@markdown.Block] raise {
  let (editor, _) = md_lang_plain.build(
    agent_id,
    capture_timeout_ms~,
    parent_runtime?,
  )
  editor
}

///|
/// Construct the standard Markdown editor and one semantic attachment over
/// the exact parser created for it. No parser or reactive handle escapes this
/// Markdown-specific companion boundary.
pub fn new_markdown_editor_with_semantic_attachment(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> (@editor.SyncEditor[@markdown.Block], @markdown.MarkdownSemanticAttachment) raise {
  let (editor, attachment) = make_md_lang(true).build(
    agent_id,
    capture_timeout_ms~,
    parent_runtime?,
  )
  (editor, attachment.unwrap())
}

///|
/// Ordinary Markdown language definition (no semantic attachment). Used for
/// the plain constructor and the apply bridge; the semantic path builds a
/// separate definition that also constructs the attachment in `project`.
let md_lang_plain : @lang_runtime.Language[
  @markdown.Block,
  @md_edits.MarkdownEditOp,
  @markdown.MarkdownSemanticAttachment?,
] = make_md_lang(false)

///|
/// Markdown language definition. `with_attachment` controls whether `project`
/// also constructs a `MarkdownSemanticAttachment` over the exact parser and
/// returns it as the extras value `E`.
fn make_md_lang(
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
    capabilities=_e => {
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
/// Return markdown text with ZWSP placeholder lines stripped structurally.
///
/// Identifies sentinel paragraphs (those whose AST is exactly
/// `Paragraph([Text("\u200B")])`) and removes only the ZWSP character itself,
/// collapsing `prev\n\u200B\nnext` to `prev\n\nnext` (preserving the block
/// separator). Leaves ZWSP inside other content (code blocks, paragraphs with
/// other text) untouched.
pub fn export_markdown_text(
  editor : @editor.SyncEditor[@markdown.Block],
) -> String {
  let src = editor.get_text()
  let root = editor.get_proj_node() catch { Failure::Failure(_) => return src }
  guard root is Some(root) else { return src }
  let source_map = editor.get_source_map() catch {
    Failure::Failure(_) => return src
  }
  let ranges : Array[(Int, Int)] = []
  collect_zwsp_ranges(root, source_map, ranges)
  if ranges.is_empty() {
    return src
  }
  ranges.sort_by(fn(a, b) { a.0.compare(b.0) })
  let buf = StringBuilder::new()
  let mut pos = 0
  for r in ranges {
    let (s, e) = r
    if s > pos {
      buf.write_string(src[pos:s].to_owned())
    }
    pos = e
  }
  if pos < src.length() {
    buf.write_string(src[pos:].to_owned())
  }
  buf.to_string()
}

///|
/// Walk the projection tree and append the source range of every ZWSP-sentinel
/// Paragraph to `out`. The range covers exactly the ZWSP character (the "text"
/// token span), so removing it from source converts `\n\u200B\n` into `\n\n`.
fn collect_zwsp_ranges(
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
  out : Array[(Int, Int)],
) -> Unit {
  if is_zwsp_sentinel(node.kind) {
    match source_map.get_token_span(node.id(), "text") {
      Some(r) => out.push((r.start, r.end))
      None => ()
    }
    return
  }
  for child in node.children {
    collect_zwsp_ranges(child, source_map, out)
  }
}

///|
fn is_zwsp_sentinel(block : @markdown.Block) -> Bool {
  match block {
    Paragraph(inlines) =>
      inlines.length() == 1 &&
      (match inlines[0] {
        Text(s) => @md_sentinel.is_empty_paragraph_text(s)
        _ => false
      })
    _ => false
  }
}

///|
/// Bridge a structural MarkdownEditOp into the text CRDT by computing
/// span-level text edits and applying them via SyncEditor.
pub fn apply_markdown_edit(
  editor : @editor.SyncEditor[@markdown.Block],
  op : @md_edits.MarkdownEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] raise {
  match md_lang_plain.apply_edit(editor, op, timestamp_ms) {
    Ok(_) => Ok(())
    Err(e) => Err(e.message())
  }
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
