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
