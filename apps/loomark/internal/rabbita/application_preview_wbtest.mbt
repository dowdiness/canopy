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
