///| CST → ProjNode[@markdown.Block] projection for Markdown.
///
/// Uses CstFold to get fully-populated Block values (with inline content,
/// heading levels, code text). The ProjNode tree structure mirrors the
/// CST block structure; Block payloads carry the semantic content.

///|
/// Convenience: parse source and project in one call (for tests and REPL).
pub fn parse_to_proj_node(
  text : String,
) -> (@core.ProjNode[@markdown.Block], Array[String]) raise @loomcore.LexError {
  let (cst, diagnostics) = @markdown.parse_cst(text)
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = syntax_to_proj_node(syntax_node, Ref(0))
  (root, errors)
}

///|
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  // CstFold produces a fully-populated Block with inline content
  let fold = @loomcore.CstFold::new(@markdown.markdown_fold_node)
  let block = fold.fold(node)
  build_proj_tree(node, block, counter)
}

///|
fn build_proj_tree(
  syntax_node : @seam.SyntaxNode,
  block : @markdown.Block,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  match block {
    Document(_) =>
      build_container(
        syntax_node,
        block,
        collect_block_children(syntax_node),
        counter,
      )
    UnorderedList(_) | OrderedList(_, _) =>
      build_container(
        syntax_node,
        block,
        collect_syntax_children(syntax_node, @markdown.SyntaxKind::ListItemNode),
        counter,
      )
    _ => @core.ProjNode::leaf(block, syntax_node, counter)
  }
}

///|
fn build_container(
  syntax_node : @seam.SyntaxNode,
  block : @markdown.Block,
  syntax_children : Array[@seam.SyntaxNode],
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let block_children = block.children()
  let len = syntax_children.length().min(block_children.length())
  let children : Array[@core.ProjNode[@markdown.Block]] = []
  for i in 0..<len {
    children.push(
      build_proj_tree(syntax_children[i], block_children[i], counter),
    )
  }
  @core.ProjNode::branch(
    block,
    syntax_node.start(),
    syntax_node.end(),
    children,
    counter,
  )
}

///|
fn collect_block_children(node : @seam.SyntaxNode) -> Array[@seam.SyntaxNode] {
  let result : Array[@seam.SyntaxNode] = []
  for child in node.children() {
    if is_block_node(@markdown.SyntaxKind::from_raw(child.kind())) {
      result.push(child)
    }
  }
  result
}

///|
fn collect_syntax_children(
  node : @seam.SyntaxNode,
  kind : @markdown.SyntaxKind,
) -> Array[@seam.SyntaxNode] {
  let result : Array[@seam.SyntaxNode] = []
  for child in node.children() {
    if @markdown.SyntaxKind::from_raw(child.kind()) == kind {
      result.push(child)
    }
  }
  result
}

///|
fn is_block_node(kind : @markdown.SyntaxKind) -> Bool {
  match kind {
    HeadingNode
    | ParagraphNode
    | UnorderedListNode
    | OrderedListNode
    | ListItemNode
    | CodeBlockNode
    | HtmlBlockNode
    | ErrorNode => true
    _ => false
  }
}

///|
/// Convert a Markdown projection to the wire ViewNode shape.
pub fn proj_to_view_node(
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
  annotations? : Map[@core.NodeId, Array[@protocol.ViewAnnotation]] = {},
  source_text? : String? = None,
) -> @protocol.ViewNode {
  @protocol.proj_to_view_node(node, source_map, annotations~, source_text~)
}

///|
/// Build the 3-memo pipeline (proj, registry, source_map) for the Markdown
/// projection.
pub fn build_markdown_projection_memos(
  parser : @loom.Parser[@markdown.Block],
  identity_hints? : Ref[Array[@core.IdentityTransform]],
) -> (
  @incr.Derived[@core.ProjNode[@markdown.Block]?],
  @incr.Derived[Map[@core.NodeId, @core.ProjNode[@markdown.Block]]],
  @incr.Derived[@core.SourceMap],
) {
  let bundle = build_markdown_projection_memos_with_heading_side_table(
    parser,
    identity_hints?,
  )
  (bundle.proj_memo, bundle.registry_memo, bundle.source_map_memo)
}

///|
#warnings("-struct_never_constructed-unused_field")
priv struct MarkdownProjectionMemoBundle {
  proj_memo : @incr.Derived[@core.ProjNode[@markdown.Block]?]
  registry_memo : @incr.Derived[
    Map[@core.NodeId, @core.ProjNode[@markdown.Block]],
  ]
  source_map_memo : @incr.Derived[@core.SourceMap]
  heading_side_table_memo : @incr.Derived[HeadingSideTable]
}

///|
fn build_markdown_projection_memos_with_heading_side_table(
  parser : @loom.Parser[@markdown.Block],
  identity_hints? : Ref[Array[@core.IdentityTransform]],
) -> MarkdownProjectionMemoBundle {
  let (proj_memo, registry_memo, source_map_memo) = @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    syntax_to_proj_node,
    populate_token_spans,
    reconcile_node=(old, new_, counter) => {
      match identity_hints {
        None => @core.reconcile(old, new_, counter)
        Some(hints_ref) => {
          let hints = build_markdown_hints_map(hints_ref.val)
          hints_ref.val = []
          reconcile_markdown_projection_hinted(old, new_, counter, hints)
        }
      }
    },
    label="markdown",
  )
  let heading_side_table_memo = build_markdown_heading_side_table_memo(
    parser, proj_memo, source_map_memo,
  )
  let source_map_with_heading_side_table : @incr.Derived[@core.SourceMap] = @incr.Derived::Derived(
    parser.runtime(),
    () => {
      let source_map = source_map_memo.get_or_abort()
      let _ = heading_side_table_memo.get_or_abort()
      source_map
    },
    label="markdown_source_map_with_heading_side_table",
  )
  {
    proj_memo,
    registry_memo,
    source_map_memo: source_map_with_heading_side_table,
    heading_side_table_memo,
  }
}
