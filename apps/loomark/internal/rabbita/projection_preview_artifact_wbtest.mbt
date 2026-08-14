///|
fn preview_artifact_test_range(start : Int, end : Int) -> (Int, Int) {
  (start, end)
}

///|
fn preview_artifact_test_text(
  start : Int,
  end : Int,
  value : String,
) -> ProjectionPreviewNode {
  {
    origin: preview_artifact_test_range(start, end),
    view: PreviewText(value),
    diagnostics: [],
    children: [],
  }
}

///|
fn preview_artifact_test_fixture() -> ProjectionPreviewArtifact {
  {
    root: {
      origin: (0, 29),
      view: PreviewDocument,
      diagnostics: ["warning: recovered source"],
      children: [
        {
          origin: (0, 12),
          view: PreviewHeading(2),
          diagnostics: [],
          children: [preview_artifact_test_text(2, 7, "Title")],
        },
        {
          origin: (13, 29),
          view: PreviewLink(
            "https://example.test",
            Some("Example"),
            PreviewInlineLink,
          ),
          diagnostics: [],
          children: [preview_artifact_test_text(14, 21, "example")],
        },
      ],
    },
  }
}

///|
test "preview artifact JSON roundtrip preserves typed views ranges diagnostics and child order" {
  let artifact = preview_artifact_test_fixture()
  let encoded = projection_preview_artifact_json(artifact)
  let decoded = projection_preview_artifact_from_json(encoded)
  assert_eq(decoded, Ok(artifact))
  let encoded_text = encoded.stringify()
  assert_true(encoded_text.contains("\"children\":[{"))
  assert_true(
    encoded_text.contains("\"diagnostics\":[\"warning: recovered source\"]"),
  )
}

///|
test "preview artifact JSON rejects unknown fields and unknown views" {
  let unknown_field = @json.parse(
    "{\"root\":{\"origin\":[0,0],\"view\":{\"kind\":\"document\",\"extra\":true},\"diagnostics\":[],\"children\":[]}}",
  ) catch {
    _ => abort("test JSON must parse")
  }
  let unknown_view = @json.parse(
    "{\"root\":{\"origin\":[0,0],\"view\":{\"kind\":\"future-view\"},\"diagnostics\":[],\"children\":[]}}",
  ) catch {
    _ => abort("test JSON must parse")
  }
  assert_true(projection_preview_artifact_from_json(unknown_field) is Err(_))
  assert_true(projection_preview_artifact_from_json(unknown_view) is Err(_))
}

///|
test "preview artifact JSON rejects malformed ranges" {
  let reversed = @json.parse(
    "{\"root\":{\"origin\":[4,2],\"view\":{\"kind\":\"document\"},\"diagnostics\":[],\"children\":[]}}",
  ) catch {
    _ => abort("test JSON must parse")
  }
  let negative = @json.parse(
    "{\"root\":{\"origin\":[-1,2],\"view\":{\"kind\":\"document\"},\"diagnostics\":[],\"children\":[]}}",
  ) catch {
    _ => abort("test JSON must parse")
  }
  assert_true(projection_preview_artifact_from_json(reversed) is Err(_))
  assert_true(projection_preview_artifact_from_json(negative) is Err(_))
}

///|
test "projection Worker publishes artifact and no HTML authority" {
  let dispatch = new_projection_worker_dispatcher()
  let response = dispatch(
    "{\"schema_version\":\"1\",\"request_id\":1,\"command\":{\"kind\":\"seed\",\"agent_id\":\"artifact-test\",\"source\":\"# Title\\n\",\"generation\":1,\"demand\":{\"block\":true,\"preview\":true,\"diagnostics\":true}}}",
  )
  assert_true(response.contains("\"artifact\""))
  assert_false(response.contains("\"html\""))
}

///|
test "artifact renderer preserves safe URL policy and treats raw HTML as text" {
  let artifact : ProjectionPreviewArtifact = {
    root: {
      origin: (0, 49),
      view: PreviewDocument,
      diagnostics: [],
      children: [
        {
          origin: (0, 17),
          view: PreviewLink("javascript:alert(1)", None, PreviewInlineLink),
          diagnostics: [],
          children: [preview_artifact_test_text(0, 4, "link")],
        },
        {
          origin: (18, 49),
          view: PreviewInlineHtml("<img src=x onerror=alert(1)>"),
          diagnostics: [],
          children: [],
        },
      ],
    },
  }
  let rendered = @rabbita_runtime.render_to_string(() => {
    @rabbita_runtime.Val::constant(
      semantic_preview_artifact_view("source", artifact),
    )
  })
  assert_true(rendered.contains("loomark-preview-url-rejected"))
  assert_true(rendered.contains("loomark-preview-html"))
  assert_true(rendered.contains("&lt;img"))
  assert_false(rendered.contains("<img src=x"))
}
