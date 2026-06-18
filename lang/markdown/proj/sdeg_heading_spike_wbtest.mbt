///| Whitebox spike tests for the Stable Document Entity Graph Phase 0 idea.

///|
/// These tests intentionally do not add a public SDEG API. They treat Markdown
/// headings as session-local entities backed by existing `NodeId`, `ProjNode`,
/// and `SourceMap` data, then pin what the current projection identity pipeline
/// already preserves and where it is still only position-stable.

///|
struct HeadingObservation {
  id : @core.NodeId
  level : Int
  text : String
  range : @loomcore.Range
  marker : @loomcore.Range?
  text_span : @loomcore.Range?
} derive(Eq, Debug)

///|
fn inline_text_to(
  inlines : Array[@markdown.Inline],
  buf : StringBuilder,
) -> Unit {
  for inline in inlines {
    match inline {
      Text(s) => buf.write_string(s)
      Bold(children) => inline_text_to(children, buf)
      Italic(children) => inline_text_to(children, buf)
      InlineCode(s) => buf.write_string(s)
      Link(children, _url) => inline_text_to(children, buf)
      Error(s) => buf.write_string(s)
    }
  }
}

///|
fn inline_text(inlines : Array[@markdown.Inline]) -> String {
  let buf = StringBuilder::new()
  inline_text_to(inlines, buf)
  buf.to_string()
}

///|
fn heading_observation(
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
) -> HeadingObservation? {
  match node.kind {
    Heading(level, inlines) =>
      match source_map.get_range(node.id()) {
        Some(range) =>
          Some({
            id: node.id(),
            level,
            text: inline_text(inlines),
            range,
            marker: source_map.get_token_span(node.id(), "marker"),
            text_span: source_map.get_token_span(node.id(), "text"),
          })
        None => None
      }
    _ => None
  }
}

///|
fn collect_heading_observations_into(
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
  out : Array[HeadingObservation],
) -> Unit {
  match heading_observation(node, source_map) {
    Some(obs) => out.push(obs)
    None => ()
  }
  for child in node.children {
    collect_heading_observations_into(child, source_map, out)
  }
}

///|
fn collect_heading_observations(
  root : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
) -> Array[HeadingObservation] {
  let out : Array[HeadingObservation] = []
  collect_heading_observations_into(root, source_map, out)
  out
}

///|
fn source_map_for(
  source : String,
  proj : @core.ProjNode[@markdown.Block],
) -> @core.SourceMap raise @loomcore.LexError {
  let source_map = @core.SourceMap::from_ast(proj)
  let (cst, _) = @markdown.parse_cst(source)
  let syntax_root = @seam.SyntaxNode::from_cst(cst)
  populate_token_spans(source_map, syntax_root, proj)
  source_map
}

///|
fn project_source(
  source : String,
) -> (@core.ProjNode[@markdown.Block], @core.SourceMap) raise @loomcore.LexError {
  let (proj, _) = parse_to_proj_node(source)
  (proj, source_map_for(source, proj))
}

///|
fn project_after_reconcile(
  old : @core.ProjNode[@markdown.Block],
  next_source : String,
  counter : Ref[Int],
) -> (@core.ProjNode[@markdown.Block], @core.SourceMap) raise @loomcore.LexError {
  let (cst, _) = @markdown.parse_cst(next_source)
  let syntax_root = @seam.SyntaxNode::from_cst(cst)
  let raw = syntax_to_proj_node(syntax_root, counter)
  let reconciled = @core.reconcile(old, raw, counter)
  (reconciled, source_map_for(next_source, reconciled))
}

///|
fn find_heading(
  observations : Array[HeadingObservation],
  text : String,
) -> HeadingObservation? {
  observations.iter().find_first(fn(obs) { obs.text == text })
}

///|
fn range_contains(outer : @loomcore.Range, inner : @loomcore.Range) -> Bool {
  outer.start <= inner.start && inner.end <= outer.end
}

///|
test "sdeg phase0: heading observation is backed by SourceMap ranges" {
  let (proj, source_map) = project_source("# Title\n\nBody")
  let observations = collect_heading_observations(proj, source_map)
  inspect(observations.length(), content="1")
  let heading = observations[0]
  inspect(heading.level, content="1")
  inspect(heading.text, content="Title")
  inspect(heading.range.start, content="0")
  inspect(heading.marker is Some(_), content="true")
  inspect(heading.text_span is Some(_), content="true")
  match (heading.marker, heading.text_span) {
    (Some(marker), Some(text_span)) => {
      inspect(range_contains(heading.range, marker), content="true")
      inspect(range_contains(heading.range, text_span), content="true")
    }
    _ => fail("expected heading marker and text spans")
  }
}

///|
test "sdeg phase0: heading rename preserves session-local NodeId" {
  let counter : Ref[Int] = Ref(0)
  let (initial_cst, _) = @markdown.parse_cst("# Alpha\n")
  let initial = syntax_to_proj_node(
    @seam.SyntaxNode::from_cst(initial_cst),
    counter,
  )
  let initial_map = source_map_for("# Alpha\n", initial)
  let initial_heading = collect_heading_observations(initial, initial_map)[0]

  let (renamed, renamed_map) = project_after_reconcile(
    initial, "# Alpha 2\n", counter,
  )
  let renamed_heading = collect_heading_observations(renamed, renamed_map)[0]

  inspect(renamed_heading.id == initial_heading.id, content="true")
  inspect(renamed_heading.text, content="Alpha 2")
}

///|
test "sdeg phase0: heading reorder is currently position-stable, not semantic-stable" {
  let counter : Ref[Int] = Ref(0)
  let (initial_cst, _) = @markdown.parse_cst("# A\n# B\n")
  let initial = syntax_to_proj_node(
    @seam.SyntaxNode::from_cst(initial_cst),
    counter,
  )
  let initial_map = source_map_for("# A\n# B\n", initial)
  let before = collect_heading_observations(initial, initial_map)
  let a_before = find_heading(before, "A").unwrap()
  let b_before = find_heading(before, "B").unwrap()

  let (reordered, reordered_map) = project_after_reconcile(
    initial, "# B\n# A\n", counter,
  )
  let after = collect_heading_observations(reordered, reordered_map)
  let b_after = find_heading(after, "B").unwrap()
  let a_after = find_heading(after, "A").unwrap()

  // Current generic reconcile matches same-kind siblings by position/LCS. That
  // preserves UI positions, but it does not preserve the semantic identity of a
  // moved heading. This is a Phase 0 finding, not the desired final behavior.
  inspect(b_after.id == a_before.id, content="true")
  inspect(a_after.id == b_before.id, content="true")
}

///|
test "sdeg phase0: duplicate headings remain distinguishable by NodeId and range" {
  let (proj, source_map) = project_source("# A\n# A\n")
  let observations = collect_heading_observations(proj, source_map)
  inspect(observations.length(), content="2")
  inspect(observations[0].text, content="A")
  inspect(observations[1].text, content="A")
  inspect(observations[0].id == observations[1].id, content="false")
  inspect(observations[0].range == observations[1].range, content="false")
}

///|
test "sdeg phase0: delete and restore currently cannot recover the retired heading id" {
  let counter : Ref[Int] = Ref(0)
  let (initial_cst, _) = @markdown.parse_cst("# A\n# B\n")
  let initial = syntax_to_proj_node(
    @seam.SyntaxNode::from_cst(initial_cst),
    counter,
  )
  let initial_map = source_map_for("# A\n# B\n", initial)
  let a_initial = find_heading(
    collect_heading_observations(initial, initial_map),
    "A",
  ).unwrap()

  let (deleted, _) = project_after_reconcile(initial, "# B\n", counter)
  let (restored, restored_map) = project_after_reconcile(
    deleted, "# A\n# B\n", counter,
  )
  let a_restored = find_heading(
    collect_heading_observations(restored, restored_map),
    "A",
  ).unwrap()

  // Without a tombstone/baseline side table, restoring text creates or reuses a
  // projection identity from the current tree, not the retired semantic heading.
  inspect(a_restored.id == a_initial.id, content="false")
}

///|
test "sdeg phase0: inline malformed-to-recovered heading preserves heading NodeId" {
  let counter : Ref[Int] = Ref(0)
  let malformed_source = "# **unclosed\n"
  let (initial_cst, _) = @markdown.parse_cst(malformed_source)
  let initial = syntax_to_proj_node(
    @seam.SyntaxNode::from_cst(initial_cst),
    counter,
  )
  let initial_map = source_map_for(malformed_source, initial)
  let initial_heading = collect_heading_observations(initial, initial_map)[0]

  let recovered_source = "# **unclosed**\n"
  let (recovered, recovered_map) = project_after_reconcile(
    initial, recovered_source, counter,
  )
  let recovered_heading = collect_heading_observations(recovered, recovered_map)[0]

  inspect(recovered_heading.id == initial_heading.id, content="true")
  inspect(recovered_heading.text.contains("unclosed"), content="true")
}

///|
test "sdeg phase0: format-like whitespace rewrite preserves heading NodeIds" {
  let counter : Ref[Int] = Ref(0)
  let (initial_cst, _) = @markdown.parse_cst("# A\n\n# B\n")
  let initial = syntax_to_proj_node(
    @seam.SyntaxNode::from_cst(initial_cst),
    counter,
  )
  let initial_map = source_map_for("# A\n\n# B\n", initial)
  let before = collect_heading_observations(initial, initial_map)
  let a_before = find_heading(before, "A").unwrap()
  let b_before = find_heading(before, "B").unwrap()

  let (rewritten, rewritten_map) = project_after_reconcile(
    initial, "# A\n\n\n# B\n", counter,
  )
  let after = collect_heading_observations(rewritten, rewritten_map)
  let a_after = find_heading(after, "A").unwrap()
  let b_after = find_heading(after, "B").unwrap()

  inspect(a_after.id == a_before.id, content="true")
  inspect(b_after.id == b_before.id, content="true")
}
