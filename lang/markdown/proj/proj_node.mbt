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
    UnorderedList(_) =>
      // The current Markdown Block API folds both unordered and ordered CST
      // list nodes to UnorderedList payloads. Preserve either CST container by
      // collecting its ListItemNode children from the original syntax node.
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
    | ErrorNode => true
    _ => false
  }
}

///|
/// Convert a Markdown projection to the wire ViewNode shape while preserving
/// CST list orderedness that the current Block payload does not carry.
pub fn proj_to_view_node(
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
  annotations? : Map[@core.NodeId, Array[@protocol.ViewAnnotation]] = {},
  source_text? : String? = None,
) -> @protocol.ViewNode {
  let view = @protocol.proj_to_view_node(
    node,
    source_map,
    annotations~,
    source_text~,
  )
  refine_markdown_view_node(view, node, source_map)
}

///|
fn refine_markdown_view_node(
  view : @protocol.ViewNode,
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
) -> @protocol.ViewNode {
  let children : Array[@protocol.ViewNode] = view.children
    .iter()
    .zip(node.children.iter())
    .map(pair => refine_markdown_view_node(pair.0, pair.1, source_map))
    .collect()
  let kind_tag = markdown_view_kind_tag(view.kind_tag, node, source_map)
  @protocol.ViewNode::ViewNode(
    id=view.id,
    kind_tag~,
    label=view.label,
    text?=view.text,
    text_range=view.text_range,
    token_spans=view.token_spans,
    editable=view.editable,
    css_class=kind_tag,
    children~,
    annotations=view.annotations,
  )
}

///|
fn markdown_view_kind_tag(
  fallback : String,
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
) -> String {
  match node.kind {
    UnorderedList(_) =>
      if source_map.get_token_span(node.id(), ORDERED_LIST_KIND_ROLE) is Some(_) {
        "OrderedList"
      } else {
        fallback
      }
    _ => fallback
  }
}

///|
/// Build the 3-memo pipeline (proj, registry, source_map) for the Markdown
/// projection.
pub fn build_markdown_projection_memos(
  parser : @loom.Parser[@markdown.Block],
) -> (
  @incr.Derived[@core.ProjNode[@markdown.Block]?],
  @incr.Derived[Map[@core.NodeId, @core.ProjNode[@markdown.Block]]],
  @incr.Derived[@core.SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    syntax_to_proj_node,
    populate_token_spans,
    label="markdown",
  )
}
