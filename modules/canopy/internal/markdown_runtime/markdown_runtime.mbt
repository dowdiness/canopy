///| Module-private owner of Markdown Language construction and edit application.

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
