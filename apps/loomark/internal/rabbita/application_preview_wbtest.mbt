///|
/// Preview-demand boundary matrix:
///
/// | old consumer | next consumer | accepted | changed | decision |
/// | --- | --- | --- | --- | --- |
/// | no | yes | yes | either | read |
/// | yes | yes | yes | yes | read |
/// | yes | yes | yes | no | keep |
/// | either | either | no | either | keep |
/// | either | no | yes | either | clear |
test "accepted source change invalidates the canonical Preview stamp" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="preview-stamp-invalidation",
    source="# A\n",
  )
  let model = {
    ..test_model(try! editor.snapshot(), editor.version()),
    preview_artifact: Some({
      stamp: projection_worker_client_test_stamp(1),
      preview: { source: "# A\n", artifact: preview_artifact_test_fixture() },
    }),
  }
  let invalidated_b = invalidate_preview_after_authority(
    model,
    accepted=true,
    changed=true,
  )
  assert_true(invalidated_b.preview_artifact is None)
  let adopted_b = { ..invalidated_b, preview_artifact: model.preview_artifact }
  let invalidated_a = invalidate_preview_after_authority(
    adopted_b,
    accepted=true,
    changed=true,
  )
  assert_true(invalidated_a.preview_artifact is None)
  let retained = invalidate_preview_after_authority(
    model,
    accepted=true,
    changed=false,
  )
  assert_true(retained.preview_artifact is Some(_))
}

///|
test "preview document decision matrix preserves accepted preview reads" {
  assert_eq(
    preview_document_decision(false, true, accepted=true, changed=false),
    PreviewDocumentRead,
  )
  assert_eq(
    preview_document_decision(true, true, accepted=true, changed=true),
    PreviewDocumentRead,
  )
  assert_eq(
    preview_document_decision(true, true, accepted=true, changed=false),
    PreviewDocumentKeep,
  )
  assert_eq(
    preview_document_decision(true, true, accepted=false, changed=true),
    PreviewDocumentKeep,
  )
}

///|
test "preview document decision matrix clears without consumers" {
  assert_eq(
    preview_document_decision(true, false, accepted=true, changed=false),
    PreviewDocumentClear,
  )
  assert_eq(
    preview_document_decision(true, false, accepted=true, changed=true),
    PreviewDocumentClear,
  )
  assert_eq(
    preview_document_decision(false, false, accepted=true, changed=false),
    PreviewDocumentClear,
  )
}

///|
test "preview document decision matrix restores and rejects deterministically" {
  assert_eq(
    preview_document_decision(false, true, accepted=true, changed=true),
    PreviewDocumentRead,
  )
  assert_eq(
    preview_document_decision(false, true, accepted=true, changed=false),
    PreviewDocumentRead,
  )
  assert_eq(
    preview_document_decision(true, true, accepted=true, changed=false),
    PreviewDocumentKeep,
  )
  assert_eq(
    preview_document_decision(false, true, accepted=false, changed=true),
    PreviewDocumentKeep,
  )
  assert_eq(
    preview_document_decision(true, false, accepted=false, changed=true),
    PreviewDocumentKeep,
  )
}
