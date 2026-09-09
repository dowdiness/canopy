///|
#warnings("-alert_unstable")
test "remote semantic tree renders like local tree" {
  let document = try! @markdown.parse(
    "# title\n\n- [x] task\n  1. **nested**\n\n[link](javascript:alert(1)) <https://example.test>\n",
    source_id=@loom.SourceId("remote-render-test"),
    extensions=@markdown.MarkdownExtensions::task_list(),
  )
  let root = document.root()
  let local_html = @rabbita_testing.server_side_render(() => render(root))
  let remote = @rabbita_testing.server_side_render(() => {
    render_remote_node(try! decode_node(encode_node(root)))
  })
  assert_eq(local_html, remote)
  assert_true(local_html.contains("data-loomark-task-checkbox"))
  assert_true(!local_html.contains("javascript:alert"))
}

///|
test "remote codec rejects malformed semantic payloads" {
  let unknown = try
    decode_node(
      Json::object({
        "kind": Json::string("future-node"),
        "children": Json::array([]),
      }),
    )
  catch {
    _ => true
  } noraise {
    _ => false
  }
  let wrong_children = try
    decode_node(
      Json::object({
        "kind": Json::string("paragraph"),
        "children": Json::string("not-an-array"),
      }),
    )
  catch {
    _ => true
  } noraise {
    _ => false
  }
  let bad_marker = try
    decode_node(
      Json::object({
        "kind": Json::string("ordered-list"),
        "spread": Json::boolean(false),
        "marker": Json::object({
          "start": Json::number(0.5),
          "delimiter": Json::string("."),
        }),
        "children": Json::array([]),
      }),
    )
  catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(unknown)
  assert_true(wrong_children)
  assert_true(bad_marker)
}
