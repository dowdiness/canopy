///|
/// Match the existing browser-sized Markdown workload while measuring the
/// authoritative apply + refresh + canonical-to-portable transaction.
fn portable_commit_benchmark_source(block_count : Int) -> String {
  Array::makei(block_count, index => {
    let number = index.to_string()
    "## Heading " +
    number +
    "\n\nParagraph " +
    number +
    " with **bold** and [link](https://example.com/" +
    number +
    ").\n"
  }).join("\n")
}

///|
fn portable_commit_sentinel_dense_source(block_count : Int) -> String {
  Array::makei(block_count, index => {
    if index % 2 == 0 {
      "\u{200B}\n"
    } else {
      "Paragraph 😀 " + index.to_string() + " keeps A\u{200B}B visible.\n"
    }
  }).join("\n")
}

///|
test "perf: project source without hidden ranges (250 blocks)" (b : @bench.T) {
  let sources = [
    portable_commit_benchmark_source(250),
    portable_commit_benchmark_source(250) + "x",
  ]
  let mut tick = 0
  b.bench(() => {
    let projected = project_source(sources[tick % sources.length()], [])
    tick += 1
    b.keep(projected)
  })
}

///|
test "perf: project accepted edit without hidden ranges (250 blocks)" (
  b : @bench.T,
) {
  let before = portable_commit_benchmark_source(250)
  let forward : @core.SpanEdit = {
    start: 3,
    delete_len: 9,
    inserted: "Heading 0 changed",
  }
  let after = apply_span_edit(before, forward)
  let reverse : @core.SpanEdit = {
    start: 3,
    delete_len: 17,
    inserted: "Heading 0",
  }
  let cases = [(before, forward, after), (after, reverse, before)]
  let mut tick = 0
  b.bench(() => {
    let (source_before, edit, source_after) = cases[tick % cases.length()]
    let projected = project_markdown_edit(
      source_before,
      [],
      edit,
      source_after,
      [],
    )
    tick += 1
    b.keep(projected)
  })
}

///|
test "perf: capture portable projection state (250 blocks)" (b : @bench.T) {
  let editors = [
    try! new_editor("portable-capture-benchmark-a"),
    try! new_editor("portable-capture-benchmark-b"),
  ]
  editors[0].set_text(portable_commit_benchmark_source(250))
  editors[1].set_text(portable_commit_benchmark_source(250) + "x")
  editors.each(editor => editor.refresh())
  let mut tick = 0
  b.bench(() => {
    let state = capture_portable_projection_state(
      editors[tick % editors.length()],
    )
    tick += 1
    b.keep(state)
  })
}

///|
test "perf: capture sentinel-dense coordinate map (250 blocks)" (b : @bench.T) {
  let sources = [
    portable_commit_sentinel_dense_source(250),
    portable_commit_sentinel_dense_source(250) + "x",
  ]
  let editors = [
    try! new_editor("portable-capture-sentinel-dense-a"),
    try! new_editor("portable-capture-sentinel-dense-b"),
  ]
  editors.eachi((index, editor) => {
    editor.set_text(sources[index])
    editor.refresh()
  })
  let mut tick = 0
  b.bench(() => {
    let coordinates = capture_portable_coordinates(
      editors[tick % editors.length()],
    )
    tick += 1
    b.keep(coordinates)
  })
}

///|
test "perf: baseline Markdown apply plus refresh (250 blocks)" (b : @bench.T) {
  let editor = try! new_editor("portable-commit-baseline-benchmark")
  editor.set_text(portable_commit_benchmark_source(250))
  editor.refresh()
  guard editor.get_proj_node() is Some(root) && root.children is [heading, ..] else {
    abort("portable commit baseline requires a first heading")
  }
  let mut changed = false
  b.bench(() => {
    let new_text = if changed { "Heading 0" } else { "Heading 0 changed" }
    let applied = apply_edit(
      editor,
      @md_edits.MarkdownEditOp::CommitEdit(node_id=heading.id(), new_text~),
      0,
    ) catch {
      error => abort("portable commit baseline raised: \{error}")
    }
    editor.refresh() catch {
      error => abort("portable commit baseline refresh raised: \{error}")
    }
    changed = !changed
    match applied {
      Ok([edit]) => b.keep(edit)
      _ => abort("portable commit baseline edit failed")
    }
  })
}

///|
test "perf: portable Markdown commit transaction (250 blocks)" (b : @bench.T) {
  let editor = try! new_editor("portable-commit-benchmark")
  editor.set_text(portable_commit_benchmark_source(250))
  editor.refresh()
  guard editor.get_proj_node() is Some(root) && root.children is [heading, ..] else {
    abort("portable commit benchmark requires a first heading")
  }
  let mut changed = false
  b.bench(() => {
    let new_text = if changed { "Heading 0" } else { "Heading 0 changed" }
    let outcome = commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::CommitEdit(node_id=heading.id(), new_text~),
      0,
    )
    changed = !changed
    match outcome {
      Ok(PortableCommitOutcome::Applied(commit)) => b.keep(commit)
      Ok(PortableCommitOutcome::Unchanged(_)) =>
        abort("portable commit benchmark unexpectedly unchanged")
      Ok(PortableCommitOutcome::Committed(..)) =>
        abort("portable commit benchmark reported a post-commit issue")
      Err(PortableCommitError::NotCommitted(..)) =>
        abort("portable commit benchmark was unavailable")
      Err(PortableCommitError::EditRejected(error~)) =>
        abort("portable commit benchmark rejected: " + error.message())
    }
  })
}
