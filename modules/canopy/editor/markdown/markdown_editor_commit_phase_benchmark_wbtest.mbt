///|
/// Keep the browser-sized Markdown workload identical to the Loomark latency
/// probe so cumulative phase costs can be compared without a UI clock.
/// The text-change benchmark isolates the diff helper. The following three
/// benchmarks are cumulative: their differences estimate apply, refresh, and
/// snapshot costs before the public commit comparisons.
fn commit_phase_source(block_count : Int) -> String {
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
fn commit_phase_sentinel_dense_source(block_count : Int) -> String {
  Array::makei(block_count, index => {
    if index % 2 == 0 {
      "\u{200B}\n"
    } else {
      "Paragraph 😀 " + index.to_string() + " keeps A\u{200B}B visible.\n"
    }
  }).join("\n")
}

///|
fn commit_phase_variant(source : String, tick : Int) -> String {
  let suffix = if tick % 2 == 0 { "x" } else { "" }
  source + suffix
}

///|
fn commit_phase_editor(source : String) -> MarkdownEditor {
  try! MarkdownEditor(agent_id="markdown-commit-phase", source~)
}

///|
fn commit_phase_set_text(
  editor : MarkdownEditor,
  source : String,
) -> (@text_change.TextChange, Bool) {
  editor.editor.set_text_with_change(source) catch {
    error => abort("set_text benchmark failed: \{error}")
  }
}

///|
fn commit_phase_changes(source : String) -> Array[@text_change.TextChange] {
  [
    @text_change.compute_text_change(source, commit_phase_variant(source, 0)),
    @text_change.compute_text_change(source + "x", source),
  ]
}

///|
test "perf: TextChange compute (250 blocks)" (b : @bench.T) {
  let source = commit_phase_source(250)
  let appended_source = source + "x"
  let mut tick = 0
  b.bench(() => {
    let change = if tick % 2 == 0 {
      @text_change.compute_text_change(source, appended_source)
    } else {
      @text_change.compute_text_change(appended_source, source)
    }
    b.keep(change)
    tick += 1
  })
}

///|
/// This uses the public undo-recording path with precomputed changes. It is a
/// comparison for apply/parser work, not a replacement for the bulk path's
/// private no-undo policy.
test "perf: MarkdownEditor apply precomputed change (250 blocks)" (b : @bench.T) {
  let source = commit_phase_source(250)
  let changes = commit_phase_changes(source)
  let editor = commit_phase_editor(source)
  let mut tick = 0
  b.bench(() => {
    let change = changes[tick % changes.length()]
    tick += 1
    editor.editor.apply_text_edit(
      change.start,
      change.delete_len,
      change.inserted,
      0,
    ) catch {
      error => abort("commit benchmark edit failed: \{error}")
    }
    b.keep(editor.editor.get_text())
  })
}

///|
test "perf: MarkdownEditor set_text_with_change (250 blocks)" (b : @bench.T) {
  let source = commit_phase_source(250)
  let editor = commit_phase_editor(source)
  let mut tick = 0
  b.bench(() => {
    let result = commit_phase_set_text(
      editor,
      commit_phase_variant(source, tick),
    )
    tick += 1
    b.keep(result)
  })
}

///|
test "perf: MarkdownEditor set_text_with_change + refresh (250 blocks)" (
  b : @bench.T,
) {
  let source = commit_phase_source(250)
  let editor = commit_phase_editor(source)
  let mut tick = 0
  b.bench(() => {
    let result = commit_phase_set_text(
      editor,
      commit_phase_variant(source, tick),
    )
    tick += 1
    editor.editor.refresh() catch {
      error => abort("refresh benchmark failed: \{error}")
    }
    b.keep(result)
  })
}

///|
test "perf: MarkdownEditor set_text + refresh + snapshot (250 blocks)" (
  b : @bench.T,
) {
  let source = commit_phase_source(250)
  let editor = commit_phase_editor(source)
  let mut tick = 0
  b.bench(() => {
    ignore(commit_phase_set_text(editor, commit_phase_variant(source, tick)))
    tick += 1
    editor.editor.refresh() catch {
      error => abort("refresh benchmark failed: \{error}")
    }
    b.keep(
      editor.snapshot() catch {
        error => abort("snapshot benchmark failed: \{error}")
      },
    )
  })
}

///|
test "perf: MarkdownEditor commit without receipt (250 blocks)" (b : @bench.T) {
  let source = commit_phase_source(250)
  let editor = commit_phase_editor(source)
  let mut tick = 0
  b.bench(() => {
    let result = editor.commit(
      MarkdownEditRequest::ReplaceSource(commit_phase_variant(source, tick)),
    ) catch {
      error => abort("commit benchmark failed: \{error}")
    }
    tick += 1
    b.keep(result)
  })
}

///|
test "perf: MarkdownEditor commit with receipt (250 blocks)" (b : @bench.T) {
  let source = commit_phase_source(250)
  let editor = commit_phase_editor(source)
  let mut tick = 0
  b.bench(() => {
    let result = editor.commit_with_receipt(
      MarkdownEditRequest::ReplaceSource(commit_phase_variant(source, tick)),
    ) catch {
      error => abort("receipt benchmark failed: \{error}")
    }
    tick += 1
    b.keep(result)
  })
}

///|
test "perf: MarkdownEditor structural receipt (250 blocks)" (b : @bench.T) {
  let editor = commit_phase_editor(commit_phase_source(250))
  let heading = editor.snapshot().blocks().to_array()[0].node_id()
  let mut changed = false
  b.bench(() => {
    let new_text = if changed { "Heading 0 changed" } else { "Heading 0" }
    let receipt = editor.commit_with_receipt(
      MarkdownEditRequest::CommitEdit(node_id=heading, new_text~),
    ) catch {
      error => abort("structural receipt benchmark raised: \{error}")
    }
    changed = !changed
    match receipt {
      Ok(receipt) => b.keep(receipt)
      Err(_) => abort("structural receipt benchmark failed")
    }
  })
}

///|
test "perf: sentinel-dense structural receipt (250 blocks)" (b : @bench.T) {
  let editor = commit_phase_editor(commit_phase_sentinel_dense_source(250))
  let blocks = editor.snapshot().blocks().to_array()
  let paragraph = blocks[blocks.length() - 1].node_id()
  let original = "Paragraph 😀 249 keeps A\u{200B}B visible."
  let changed_text = "Paragraph 😀 249 changed A\u{200B}B visibly."
  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(node_id=paragraph, new_text=changed_text),
    ) {
    Ok(result) => b.keep(result)
    Err(_) => abort("sentinel-dense structural receipt prime failed")
  }
  let mut changed = true
  b.bench(() => {
    let new_text = if changed { original } else { changed_text }
    let receipt = editor.commit_with_receipt(
      MarkdownEditRequest::CommitEdit(node_id=paragraph, new_text~),
    ) catch {
      error => abort("sentinel-dense structural receipt raised: \{error}")
    }
    changed = !changed
    match receipt {
      Ok(receipt) => b.keep(receipt)
      Err(_) => abort("sentinel-dense structural receipt failed")
    }
  })
}

///|
test "perf: MarkdownEditor structural block edit (250 blocks)" (b : @bench.T) {
  let editor = commit_phase_editor(commit_phase_source(250))
  let heading = editor.snapshot().blocks().to_array()[0].node_id()
  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(
        node_id=heading,
        new_text="Heading 0 changed",
      ),
    ) {
    Ok(result) => b.keep(result)
    Err(_) => abort("structural block benchmark prime failed")
  }
  let mut changed = false
  b.bench(() => {
    let new_text = if changed { "Heading 0 changed" } else { "Heading 0" }
    let result = editor.commit(
      MarkdownEditRequest::CommitEdit(node_id=heading, new_text~),
    ) catch {
      error => abort("structural block benchmark raised: \{error}")
    }
    changed = !changed
    match result {
      Ok(result) => b.keep(result)
      Err(_) => abort("structural block benchmark failed")
    }
  })
}
