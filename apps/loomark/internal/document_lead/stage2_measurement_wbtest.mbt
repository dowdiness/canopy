///|
/// Stage 2 uses one deterministic corpus for every phase. The setup is kept
/// outside timed spans; only the named operation is measured.
fn stage2_sources() -> Array[String] {
  let block = "# Heading 😀\n\nparagraph with **inline** text and a [link](https://example.com)\n\n" +
    "- [ ] task item\n  - nested child\n\n    indented code line\n"
  [
    "# Unicode 😀 lead\n\nline one\nline two\n",
    block.repeat(4),
    block.repeat(32),
    block.repeat(256),
  ]
}

///|
/// The exact large specimens used by the original lead_wbtest benchmarks.
/// Keep this recipe in one place: every decomposition phase and the original
/// whole-extract tests consume these same generated strings.
fn stage2_large_sources() -> Array[String] {
  let mixed = StringBuilder::StringBuilder()
  for i in 0..<20000 {
    if i % 4 == 0 {
      mixed.write_string(
        "# Heading \{i} padding padding padding padding padding padding\n\n",
      )
    } else if i % 4 == 1 {
      mixed.write_string(
        "- [ ] task \{i} padding padding padding padding padding\n",
      )
    } else if i % 4 == 2 {
      mixed.write_string("```moonbit\n  let x = \{i}\n    let y = x\n```\n\n")
    } else {
      mixed.write_string(
        "paragraph \{i} with **inline** text and a [link](https://example.com) padding padding\n\n",
      )
    }
  }
  [
    mixed.to_string(),
    "paragraph with a distinct large source payload. ".repeat(22000),
  ]
}

///|
/// Parse every corpus member once for downstream phase setup.
fn stage2_parsed(
  sources : Array[String],
) -> Array[(@seam.CstNode, @loom.DiagnosticSet)] {
  sources.map(source => {
    @markdown.parse_cst(name_source_id, source) catch {
      error => abort("stage2 fixture parser failure: \{error}")
    }
  })
}

///|
test "stage2 fixture manifest" {
  let expected = [(39, 36), (556, 544), (4448, 4352), (35584, 34816)]
  for index, source in stage2_sources() {
    let (bytes, chars) = expected[index]
    assert_eq(@utf8.encode(source).length(), bytes)
    assert_eq(source.char_length(), chars)
    println(
      "fixture[\{index}] bytes=\{@utf8.encode(source).length()} chars=\{source.char_length()}",
    )
  }
}

///|
test "stage2 recomposition matches extract for every corpus member" {
  let limits = test_limits(primary=80, description=160)
  for source in stage2_sources() {
    let parsed = @markdown.parse_cst(name_source_id, source) catch {
      error => abort("stage2 fixture parser failure: \{error}")
    }
    let (cst, diagnostics) = parsed
    let root = @seam.SyntaxNode::from_cst(cst)
    let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
      name_source_id,
      root,
      diagnostics,
      extensions=@markdown.MarkdownExtensions::task_list(),
    )
    let children = document.children()
    let recomposed = match first_readable_index(document, source) {
      Some(index) =>
        match lead_from_node(children[index], source, limits) {
          Some(lead) => finish_lead(lead, children, index, source, limits)
          None => fallback_lead(source, limits)
        }
      None => fallback_lead(source, limits)
    }
    assert_eq(recomposed, extract(source, limits~))
  }
  for source in stage2_large_sources() {
    let parsed = @markdown.parse_cst(name_source_id, source) catch {
      error => abort("large fixture parser failure: \{error}")
    }
    let (cst, diagnostics) = parsed
    let root = @seam.SyntaxNode::from_cst(cst)
    let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
      name_source_id,
      root,
      diagnostics,
      extensions=@markdown.MarkdownExtensions::task_list(),
    )
    let children = document.children()
    let index = first_readable_index(document, source).unwrap()
    let lead = lead_from_node(children[index], source, limits).unwrap()
    assert_eq(
      finish_lead(lead, children, index, source, limits),
      extract(source, limits~),
    )
  }
}

///|
test "stage2 output manifest" {
  let limits = test_limits(primary=80, description=160)
  for index, source in stage2_sources() {
    let lead = extract(source, limits~)
    println(
      "output[\{index}] primary_chars=\{lead.primary().char_length()} description_chars=\{lead.description().char_length()} primary_truncated=\{lead.primary_truncated()} description_truncated=\{lead.description_truncated()}",
    )
  }
  let max_limits = test_limits(primary=32, description=64)
  let max = extract(
    "# stable prefix abcdefghijklmnopqrstuvwxyz\n\n" + "x".repeat(256),
    limits=max_limits,
  )
  println(
    "max_output primary_chars=\{max.primary().char_length()} description_chars=\{max.description().char_length()} primary_truncated=\{max.primary_truncated()} description_truncated=\{max.description_truncated()}",
  )
  for source in stage2_large_sources() {
    let lead = extract(source, limits~)
    assert_eq(
      lead.primary().char_length(),
      if source == stage2_large_sources()[0] {
        57
      } else {
        80
      },
    )
    assert_eq(
      lead.description().char_length(),
      if source == stage2_large_sources()[0] {
        160
      } else {
        0
      },
    )
    assert_eq(lead.primary_truncated(), source == stage2_large_sources()[1])
    assert_eq(lead.description_truncated(), source == stage2_large_sources()[0])
    println(
      "large_output primary_chars=\{lead.primary().char_length()} description_chars=\{lead.description().char_length()} primary_truncated=\{lead.primary_truncated()} description_truncated=\{lead.description_truncated()}",
    )
  }
}

///|
test "bench stage2 parse_cst" (b : @bench.T) {
  let sources = stage2_sources()
  let mut index = 0
  b.bench(() => {
    let source = sources[index]
    index = (index + 1) % sources.length()
    let parsed = @markdown.parse_cst(name_source_id, source) catch {
      error => abort("stage2 fixture parser failure: \{error}")
    }
    b.keep(parsed)
  })
}

///|
test "bench stage2 CST to SyntaxNode conversion" (b : @bench.T) {
  let parsed = stage2_parsed(stage2_sources())
  let mut index = 0
  b.bench(() => {
    let (cst, _) = parsed[index]
    index = (index + 1) % parsed.length()
    b.keep(@seam.SyntaxNode::from_cst(cst))
  })
}

///|
test "bench stage2 SyntaxNode to MarkdownIR conversion" (b : @bench.T) {
  let parsed = stage2_parsed(stage2_sources())
  let roots = parsed.map(parsed => {
    let (cst, _) = parsed
    @seam.SyntaxNode::from_cst(cst)
  })
  let diagnostics = parsed.map(parsed => parsed.1)
  let mut index = 0
  b.bench(() => {
    let root = roots[index]
    let diagnostic = diagnostics[index]
    index = (index + 1) % roots.length()
    b.keep(
      @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
        name_source_id,
        root,
        diagnostic,
        extensions=@markdown.MarkdownExtensions::task_list(),
      ),
    )
  })
}

///|
test "bench stage2 primary selection" (b : @bench.T) {
  let sources = stage2_sources()
  let parsed = stage2_parsed(sources)
  let documents = parsed.map(parsed => {
    let (cst, diagnostics) = parsed
    let root = @seam.SyntaxNode::from_cst(cst)
    @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
      name_source_id,
      root,
      diagnostics,
      extensions=@markdown.MarkdownExtensions::task_list(),
    )
  })
  let mut index = 0
  b.bench(() => {
    let document = documents[index]
    let source = sources[index]
    index = (index + 1) % documents.length()
    b.keep(first_readable_index(document, source))
  })
}

///|
test "bench stage2 description construction" (b : @bench.T) {
  let sources = stage2_sources()
  let parsed = stage2_parsed(sources)
  let documents = parsed.map(parsed => {
    let (cst, diagnostics) = parsed
    let root = @seam.SyntaxNode::from_cst(cst)
    @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
      name_source_id,
      root,
      diagnostics,
      extensions=@markdown.MarkdownExtensions::task_list(),
    )
  })
  let limits = test_limits(primary=80, description=160)
  let mut source_index = 0
  let indices = documents.map(document => {
    let source = sources[source_index]
    source_index += 1
    first_readable_index(document, source).unwrap()
  })
  source_index = 0
  let leads = documents.map(document => {
    let source = sources[source_index]
    source_index += 1
    let first = first_readable_index(document, source).unwrap()
    lead_from_node(document.children()[first], source, limits).unwrap()
  })
  let mut index = 0
  b.bench(() => {
    let document = documents[index]
    let source = sources[index]
    let lead = leads[index]
    let first = indices[index]
    index = (index + 1) % documents.length()
    b.keep(description_for_lead(lead, document.children(), first, source))
  })
}

///|
test "bench stage2 bounded result construction" (b : @bench.T) {
  let sources = stage2_sources()
  let parsed = stage2_parsed(sources)
  let documents = parsed.map(parsed => {
    let (cst, diagnostics) = parsed
    let root = @seam.SyntaxNode::from_cst(cst)
    @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
      name_source_id,
      root,
      diagnostics,
      extensions=@markdown.MarkdownExtensions::task_list(),
    )
  })
  let limits = test_limits(primary=80, description=160)
  let mut source_index = 0
  let indices = documents.map(document => {
    let source = sources[source_index]
    source_index += 1
    first_readable_index(document, source).unwrap()
  })
  source_index = 0
  let leads = documents.map(document => {
    let source = sources[source_index]
    source_index += 1
    let first = first_readable_index(document, source).unwrap()
    lead_from_node(document.children()[first], source, limits).unwrap()
  })
  let mut index = 0
  b.bench(() => {
    let document = documents[index]
    let source = sources[index]
    let lead = leads[index]
    let first = indices[index]
    index = (index + 1) % documents.length()
    b.keep(finish_lead(lead, document.children(), first, source, limits))
  })
}

///|
test "bench stage2 whole extract same corpus" (b : @bench.T) {
  let sources = stage2_sources()
  let limits = test_limits(primary=80, description=160)
  let mut index = 0
  b.bench(() => {
    let source = sources[index]
    index = (index + 1) % sources.length()
    b.keep(extract(source, limits~))
  })
}

///|
test "stage2 Eq max-primary outputs are equal with bounds" (b : @bench.T) {
  let limits = test_limits(primary=32, description=64)
  let left = extract(
    "# stable prefix abcdefghijklmnopqrstuvwxyz\n\n" + "x".repeat(256),
    limits~,
  )
  let right = extract(
    "# stable prefix abcdefghijklmnopqrstuvwxyzZZZZZZZZZZ\n\n" + "x".repeat(256),
    limits~,
  )
  assert_eq(left.primary(), "stable prefix abcdefghijklmnopqr")
  assert_eq(left.description(), "x".repeat(64))
  assert_true(left.primary_truncated())
  assert_true(left.description_truncated())
  assert_eq(left, right)
  b.bench(() => b.keep(left == right))
}

///|
test "stage2 Eq max-description outputs are equal with bounds" (b : @bench.T) {
  let limits = test_limits(primary=32, description=64)
  let left = extract("# stable\n\n" + "x".repeat(256), limits~)
  let right = extract("# stable\n\n" + "x".repeat(256) + "y", limits~)
  assert_eq(left.primary(), "stable")
  assert_eq(left.description(), "x".repeat(64))
  assert_true(!left.primary_truncated())
  assert_true(left.description_truncated())
  assert_eq(left, right)
  b.bench(() => b.keep(left == right))
}

///|
test "stage2 Eq final fields remain unequal" (b : @bench.T) {
  let limits = test_limits(primary=32, description=64)
  let left = extract(
    "# stable prefix abcdefghijklmnopqrstuvwxyz\n\n" + "x".repeat(64),
    limits~,
  )
  let right = extract(
    "# stable prefix abcdefghijklmnopqrstuvwxyz\n\n" + "x".repeat(65),
    limits~,
  )
  assert_eq(left.form(), right.form())
  assert_eq(left.primary(), right.primary())
  assert_eq(left.description(), right.description())
  assert_eq(left.primary_truncated(), right.primary_truncated())
  assert_true(left.primary_truncated())
  assert_true(!left.description_truncated())
  assert_true(right.description_truncated())
  assert_true(left != right)
  b.bench(() => b.keep(left != right))
}

///|
priv struct Stage2LargeFixture {
  source : String
  cst : @seam.CstNode
  diagnostics : @loom.DiagnosticSet
  root : @seam.SyntaxNode
  document : @markdown.MarkdownIR
  first : Int
  lead : DocumentLead
  description : String
}

///|
fn stage2_large_fixture(index : Int) -> Stage2LargeFixture {
  let source = stage2_large_sources()[index]
  let (cst, diagnostics) = @markdown.parse_cst(name_source_id, source) catch {
    error => abort("large fixture parser failure: \{error}")
  }
  let root = @seam.SyntaxNode::from_cst(cst)
  let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    name_source_id,
    root,
    diagnostics,
    extensions=@markdown.MarkdownExtensions::task_list(),
  )
  let limits = test_limits(primary=80, description=160)
  let first = first_readable_index(document, source).unwrap()
  let lead = lead_from_node(document.children()[first], source, limits).unwrap()
  let description = description_for_lead(
    lead,
    document.children(),
    first,
    source,
  )
  { source, cst, diagnostics, root, document, first, lead, description }
}

///|
test "stage2 large fixture manifest" {
  let expected = [(1268890, 1268890), (1056000, 1056000)]
  for index, source in stage2_large_sources() {
    let (bytes, chars) = expected[index]
    assert_eq(@utf8.encode(source).length(), bytes)
    assert_eq(source.char_length(), chars)
    println(
      "large_fixture[\{index}] bytes=\{@utf8.encode(source).length()} chars=\{source.char_length()}",
    )
  }
}

///|
test "bench stage2 large mixed parse" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  b.bench(() => {
    let parsed = @markdown.parse_cst(name_source_id, fixture.source) catch {
      error => abort("large fixture parser failure: \{error}")
    }
    b.keep(parsed)
  })
}

///|
test "bench stage2 large distinct parse" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  b.bench(() => {
    let parsed = @markdown.parse_cst(name_source_id, fixture.source) catch {
      error => abort("large fixture parser failure: \{error}")
    }
    b.keep(parsed)
  })
}

///|
test "bench stage2 large mixed CST" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  b.bench(() => b.keep(@seam.SyntaxNode::from_cst(fixture.cst)))
}

///|
test "bench stage2 large distinct CST" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  b.bench(() => b.keep(@seam.SyntaxNode::from_cst(fixture.cst)))
}

///|
test "bench stage2 large mixed IR" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  b.bench(() => {
    b.keep(
      @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
        name_source_id,
        fixture.root,
        fixture.diagnostics,
        extensions=@markdown.MarkdownExtensions::task_list(),
      ),
    )
  })
}

///|
test "bench stage2 large distinct IR" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  b.bench(() => {
    b.keep(
      @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
        name_source_id,
        fixture.root,
        fixture.diagnostics,
        extensions=@markdown.MarkdownExtensions::task_list(),
      ),
    )
  })
}

///|
test "bench stage2 large mixed primary selection" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  b.bench(() => b.keep(first_readable_index(fixture.document, fixture.source)))
}

///|
test "bench stage2 large mixed primary construction" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  let limits = test_limits(primary=80, description=160)
  b.bench(() => {
    b.keep(
      lead_from_node(
        fixture.document.children()[fixture.first],
        fixture.source,
        limits,
      ),
    )
  })
}

///|
test "bench stage2 large distinct primary selection" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  b.bench(() => b.keep(first_readable_index(fixture.document, fixture.source)))
}

///|
test "bench stage2 large distinct primary construction" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  let limits = test_limits(primary=80, description=160)
  b.bench(() => {
    b.keep(
      lead_from_node(
        fixture.document.children()[fixture.first],
        fixture.source,
        limits,
      ),
    )
  })
}

///|
test "bench stage2 large mixed description" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  b.bench(() => {
    b.keep(
      description_for_lead(
        fixture.lead,
        fixture.document.children(),
        fixture.first,
        fixture.source,
      ),
    )
  })
}

///|
test "bench stage2 large distinct description" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  b.bench(() => {
    b.keep(
      description_for_lead(
        fixture.lead,
        fixture.document.children(),
        fixture.first,
        fixture.source,
      ),
    )
  })
}

///|
test "bench stage2 large mixed bound" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  b.bench(() => b.keep(bound_text(fixture.description, 160)))
}

///|
test "bench stage2 large distinct bound" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  b.bench(() => b.keep(bound_text(fixture.description, 160)))
}

///|
test "bench stage2 large mixed result" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  let limits = test_limits(primary=80, description=160)
  let (description, truncated) = bound_text(
    fixture.description,
    limits.description,
  )
  b.bench(() => {
    b.keep(
      result_from_bounded_description(fixture.lead, description, truncated),
    )
  })
}

///|
test "bench stage2 large distinct result" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  let limits = test_limits(primary=80, description=160)
  let (description, truncated) = bound_text(
    fixture.description,
    limits.description,
  )
  b.bench(() => {
    b.keep(
      result_from_bounded_description(fixture.lead, description, truncated),
    )
  })
}

///|
test "bench stage2 large mixed Eq" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  let left = extract(
    fixture.source,
    limits=test_limits(primary=80, description=160),
  )
  let right = extract(
    fixture.source,
    limits=test_limits(primary=80, description=160),
  )
  b.bench(() => b.keep(left == right))
}

///|
test "bench stage2 large distinct Eq" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  let left = extract(
    fixture.source,
    limits=test_limits(primary=80, description=160),
  )
  let right = extract(
    fixture.source,
    limits=test_limits(primary=80, description=160),
  )
  b.bench(() => b.keep(left == right))
}

///|
test "bench stage2 large mixed whole" (b : @bench.T) {
  let fixture = stage2_large_fixture(0)
  let limits = test_limits(primary=80, description=160)
  b.bench(() => b.keep(extract(fixture.source, limits~)))
}

///|
test "bench stage2 large distinct whole" (b : @bench.T) {
  let fixture = stage2_large_fixture(1)
  let limits = test_limits(primary=80, description=160)
  b.bench(() => b.keep(extract(fixture.source, limits~)))
}
