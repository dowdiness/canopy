///|
/// Build a Markdown editor whose initial empty projection is valid, then fail
/// its first incremental parser publication after the text engine accepts it.
/// Production Markdown construction never imports this test-support package.
pub fn new_parser_failure_editor(
  agent_id : String,
) -> @editor.SyncEditor[@markdown.Block] raise {
  let full_parse = fn(
    _source_id : @loom_core.SourceId,
    _source : String,
  ) raise Failure {
    let cst = @seam.CstNode::new_unclassified(
      @seam.ToRawKind::to_raw(@markdown.SyntaxKind::DocumentNode),
      [],
    )
    (@seam.SyntaxNode::from_cst(cst), @loom_core.DiagnosticSet::empty(), 0)
  }
  let language = @loom_incremental.ImperativeLanguage::new(
    full_parse~,
    incremental_parse=fn(_source_id, _source, _old, _edit) raise Failure {
      fail("injected parser publication failure")
    },
    to_ast=_syntax => @markdown.Block::Document([]),
  )
  let (editor, _) = @editor.SyncEditor::new_with_builder(
    agent_id,
    (source_id, source, runtime) => {
      @loom_pipeline.Parser::new(source_id, source, language, runtime?)
    },
    (parser, identity_hints) => {
      let memos = @md_proj.build_markdown_projection_memos(
        parser,
        identity_hints~,
      )
      (memos.0, memos.1, memos.2, @editor.LanguageCapabilities::default(), ())
    },
  )
  editor
}
