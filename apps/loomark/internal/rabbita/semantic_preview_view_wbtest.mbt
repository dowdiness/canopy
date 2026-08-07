///|
#warnings("-alert_unstable")
fn render_preview(source : String) -> String raise {
  let preview = semantic_preview_view(
    source,
    wbtest_markdown_ir(@loom.SourceId("loomark-preview-ssr"), source),
  )
  @rabbita_runtime.render_to_string(() => {
    @rabbita_runtime.Val::constant(preview)
  })
}

///|
test "semantic preview SSR renders an ATX heading" {
  let rendered = render_preview("# Hello\n")
  assert_true(rendered.contains("id=\"loomark-preview\""))
  assert_true(rendered.contains("<h1"))
  assert_true(rendered.contains(">Hello</h1>"))
}

///|
fn assert_preview_contains(rendered : String, expected : String) -> Unit {
  if !rendered.contains(expected) {
    abort("missing `\{expected}` in `\{rendered}`")
  }
}

///|
test "semantic preview SSR renders headings containers and code" {
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
test "semantic preview SSR renders inline links images and reference metadata" {
  let rendered = render_preview(
    "**bold** *italic* `code` [inline](/to \"tip\") [full][ref] ![image *alt*](/img \"caption\")\n\n[ref]: /ref \"reference title\"\n",
  )
  assert_preview_contains(rendered, "<strong>bold</strong>")
  assert_preview_contains(rendered, "<em>italic</em>")
  assert_preview_contains(rendered, "<code>code</code>")
  assert_preview_contains(rendered, "href=\"/to\"")
  assert_preview_contains(rendered, "title=\"tip\"")
  assert_preview_contains(
    rendered, "data-loomark-link-reference-form=\"inline\"",
  )
  assert_preview_contains(
    rendered, "data-loomark-link-reference-form=\"full-reference\"",
  )
  assert_preview_contains(rendered, "src=\"/img\"")
  assert_preview_contains(rendered, "alt=\"image alt\"")
  assert_preview_contains(rendered, "title=\"caption\"")
  assert_preview_contains(
    rendered, "data-loomark-image-reference-form=\"inline\"",
  )
}

///|
test "semantic preview SSR preserves autolink break and HTML forms" {
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
test "semantic preview SSR labels raw recovered and literal fallback forms" {
  let raw = render_preview("[text](url\n")
  let recovered = render_preview("[unclosed\n")
  let literal = render_preview("~~strike~~")
  assert_preview_contains(raw, "data-loomark-preview-fallback=\"raw\"")
  assert_preview_contains(
    recovered, "data-loomark-preview-fallback=\"recovered\"",
  )
  assert_preview_contains(recovered, "Diagnostic:")
  assert_preview_contains(literal, "~~strike~~")
}

///|
test "semantic preview SSR rejects unsafe link destinations" {
  let rejected = render_preview(
    "[link](javascript:alert(1)) <javascript:alert(1)> ![image](javascript:alert(1))",
  )
  let safe = render_preview(
    "[relative](docs/page) [space](<docs/my page>) [colon](docs/page:part) [web](HTTP://example.test) [mail](mailto:me@example.test) ![image](/image.png)",
  )
  assert_true(!rejected.contains("href=\"javascript:"))
  assert_true(!rejected.contains("src=\"javascript:"))
  assert_preview_contains(rejected, "data-loomark-preview-url-rejected")
  assert_preview_contains(safe, "href=\"docs/page\"")
  assert_preview_contains(safe, "href=\"docs/my page\"")
  assert_preview_contains(safe, "href=\"docs/page:part\"")
  assert_preview_contains(safe, "href=\"HTTP://example.test\"")
  assert_preview_contains(safe, "href=\"mailto:me@example.test\"")
  assert_preview_contains(safe, "src=\"/image.png\"")
  assert_eq(
    semantic_preview_safe_destination("java script:alert(1)", image=false),
    None,
  )
  assert_eq(
    semantic_preview_safe_destination("java\u0000script:alert(1)", image=false),
    None,
  )
  assert_eq(
    semantic_preview_safe_destination("java\tscript:alert(1)", image=false),
    None,
  )
  assert_eq(
    semantic_preview_safe_destination("java\nscript:alert(1)", image=false),
    None,
  )
  assert_eq(
    semantic_preview_safe_destination("java\rscript:alert(1)", image=false),
    None,
  )
}

///|
test "semantic preview SSR keeps ordinary paragraphs semantic" {
  let rendered = render_preview("ordinary paragraph\n")
  assert_preview_contains(rendered, "<p")
  assert_preview_contains(rendered, ">ordinary paragraph</p>")
}

///|
test "semantic preview SSR distinguishes tight and loose list paragraphs" {
  let tight = render_preview("- one\n- two\n")
  let loose = render_preview("- one\n\n- two\n")
  let nested = render_preview("- outer\n  - inner\n")
  assert_true(!tight.contains("<p"))
  assert_preview_contains(tight, "data-loomark-list-item-spread=\"false\"")
  assert_preview_contains(tight, ">one</li>")
  assert_preview_contains(loose, "data-loomark-list-item-spread=\"true\"")
  assert_preview_contains(loose, "<p")
  assert_preview_contains(nested, "<ul")
  assert_preview_contains(nested, "outer")
  assert_preview_contains(nested, "inner")
}
