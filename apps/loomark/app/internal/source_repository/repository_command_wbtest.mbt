///|
fn command_doc(id : String) -> Document {
  Document::create(id, "# text\n") catch {
    _ => abort("invalid")
  }
}

///|
test "open begins with complete Store entries scan" {
  assert_true(
    @debug.to_string(open(_ => @cmd.none)).contains("IndexedDBEntries"),
  )
}

///|
test "saved membership parses an exact editing hint" {
  let saved = SavedDocuments::from_documents([command_doc("a")]).unwrap()
  assert_eq(saved.editing_document_hint("a"), Some(EditingDocumentHint("a")))
  assert_eq(saved.editing_document_hint("missing"), None)
}

///|
test "remembering a parsed hint writes the advisory record" {
  let saved = SavedDocuments::from_documents([command_doc("a")]).unwrap()
  let hint = saved.editing_document_hint("a").unwrap()
  assert_true(@debug.to_string(hint.remember()).contains("IndexedDBApply"))
}

///|
test "save replaces a known document" {
  let saved = SavedDocuments::from_documents([command_doc("a")]).unwrap()
  assert_true(
    @debug.to_string(save(saved, command_doc("a"), _ => @cmd.none)).contains(
      "IndexedDBApply",
    ),
  )
}

///|
test "save inserts only at unobserved key" {
  let saved = SavedDocuments::from_documents([]).unwrap()
  assert_true(
    @debug.to_string(save(saved, command_doc("new"), _ => @cmd.none)).contains(
      "IndexedDBApply",
    ),
  )
  let (saved, _) = reconcile_scan([
    @indexed_db.Entry::StringRecord("source/v1/new", "bad"),
  ])
  assert_false(
    @debug.to_string(save(saved, command_doc("new"), _ => @cmd.none)).contains(
      "IndexedDBApply",
    ),
  )
}

///|
test "delete rejects unknown document" {
  let saved = SavedDocuments::from_documents([]).unwrap()
  let emitted : Array[DeleteResult] = []
  let command = delete(saved, "missing", result => {
    emitted.push(result)
    @cmd.none
  })
  assert_eq(emitted, [DeleteResult::DeleteFailed(DeleteFailure::InvalidSource)])
  assert_false(@debug.to_string(command).contains("IndexedDB"))
}

///|
test "delete and create commands use positional callbacks" {
  let saved = SavedDocuments::from_documents([command_doc("a")]).unwrap()
  assert_true(
    @debug.to_string(delete(saved, "a", _ => @cmd.none)).contains(
      "IndexedDBApply",
    ),
  )
  assert_false(
    @debug.to_string(create(saved, _ => @cmd.none)).contains("IndexedDB"),
  )
}
