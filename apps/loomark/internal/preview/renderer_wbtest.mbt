///|
fn preview_test_document(source : String) -> @markdown.MarkdownIR raise {
  let parser = @loom.new_syntax_parser(
    @loom.SourceId("loomark-preview-test"),
    source,
    @markdown.markdown_grammar.to_syntax_grammar(),
  )
  let snapshot = parser.snapshot().read_or_abort()
  @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    parser.source_id(),
    snapshot.syntax,
    snapshot.diagnostics,
  )
}

///|
#warnings("-alert_unstable")
fn render_preview(source : String) -> String raise {
  let preview = render(preview_test_document(source))
  @rabbita_testing.server_side_render(() => preview)
}

///|
fn assert_preview_contains(rendered : String, expected : String) -> Unit {
  if !rendered.contains(expected) {
    abort("missing `\{expected}` in `\{rendered}`")
  }
}

///|
test "Preview renderer covers headings containers and code" {
  let rendered = render_preview(
    "# ATX\n\nSetext\r\n======\r\n\n> quote\n\n- outer\n  3. inner\n\n```moonbit\nlet value = 1\n```\n\n---\n",
  )
  assert_preview_contains(rendered, ">ATX</h1>")
  assert_preview_contains(rendered, ">Setext</h1>")
  assert_preview_contains(rendered, "<blockquote")
  assert_preview_contains(rendered, "<ul")
  assert_preview_contains(rendered, "<ol")
  assert_preview_contains(rendered, "start=\"3\"")
  assert_preview_contains(rendered, "data-loomark-code-info=\"moonbit\"")
  assert_preview_contains(rendered, "<hr")
}

///|
test "Preview renderer covers inline forms and safe new-tab links" {
  let rendered = render_preview(
    "**bold** *italic* `code` [inline](/to \"tip\") [full][ref] ![image *alt*](/img \"caption\")\n\n[ref]: /ref \"reference title\"\n",
  )
  assert_preview_contains(rendered, "<strong>bold</strong>")
  assert_preview_contains(rendered, "<em>italic</em>")
  assert_preview_contains(rendered, "<code>code</code>")
  assert_preview_contains(rendered, "href=\"/to\"")
  assert_preview_contains(rendered, "target=\"_blank\"")
  assert_preview_contains(rendered, "rel=\"noopener noreferrer\"")
  assert_preview_contains(rendered, "title=\"tip\"")
  assert_preview_contains(
    rendered, "data-loomark-link-reference-form=\"inline\"",
  )
  assert_preview_contains(
    rendered, "data-loomark-link-reference-form=\"full-reference\"",
  )
  assert_preview_contains(rendered, "src=\"/img\"")
  assert_preview_contains(rendered, "alt=\"image alt\"")
}

///|
test "Preview renderer keeps raw HTML inert and preserves break forms" {
  let rendered = render_preview(
    "<https://example.test> <mail@example.test>\rsoft\nspace  \nslash\\\nnext\n\n<div>block</div>\n\ninline <i>tag</i>\n",
  )
  assert_preview_contains(rendered, "data-loomark-autolink-kind=\"uri\"")
  assert_preview_contains(rendered, "data-loomark-autolink-kind=\"email\"")
  assert_preview_contains(
    rendered, "data-loomark-hard-break-form=\"trailing-spaces\"",
  )
  assert_preview_contains(
    rendered, "data-loomark-hard-break-form=\"backslash\"",
  )
  assert_preview_contains(rendered, "data-loomark-preview-html=\"block\"")
  assert_preview_contains(rendered, "data-loomark-preview-html=\"inline\"")
  assert_preview_contains(rendered, "&lt;div&gt;block&lt;/div&gt;")
  assert_preview_contains(rendered, "&lt;i&gt;")
}

///|
test "Preview renderer rejects unsafe destinations" {
  let rendered = render_preview(
    "[link](javascript:alert(1)) <javascript:alert(1)> ![image](javascript:alert(1))",
  )
  assert_true(!rendered.contains("href=\"javascript:"))
  assert_true(!rendered.contains("src=\"javascript:"))
  assert_preview_contains(rendered, "data-loomark-preview-url-rejected")
  assert_eq(safe_destination("java script:alert(1)", image=false), None)
  assert_eq(safe_destination("java\u0000script:alert(1)", image=false), None)
  assert_eq(safe_destination("java\tscript:alert(1)", image=false), None)
}

///|
test "Preview renderer preserves syntax diagnostics during direct lowering" {
  let rendered = render_preview("[unclosed\n")
  assert_preview_contains(rendered, "Recovered Markdown: [")
  assert_preview_contains(rendered, "data-loomark-preview-diagnostic")
}

///|
test "Preview renderer distinguishes tight and loose lists" {
  let tight = render_preview("- one\n- two\n")
  let loose = render_preview("- one\n\n- two\n")
  assert_true(!tight.contains("<p"))
  assert_preview_contains(tight, "data-loomark-list-item-spread=\"false\"")
  assert_preview_contains(loose, "data-loomark-list-item-spread=\"true\"")
  assert_preview_contains(loose, "<p")
}

///|
test "Preview empty state follows semantic children" {
  assert_true(is_empty(preview_test_document("")))
  assert_true(!is_empty(preview_test_document("# Heading\n")))
}
