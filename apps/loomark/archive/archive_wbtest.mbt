///|
test "archive capture and round-trip tracer" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="archive-capture-red",
    source="# Title\n\nbody\n",
  )
  ignore(
    editor.commit(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=2,
        delete_len=0,
        inserted="New ",
      ),
    ),
  )
  let document_id = try! LoomarkDocumentId::from_string("doc-1")
  let archive = try! LoomarkDocumentArchive::capture(document_id~, editor~)
  let encoded = archive.to_json_string()
  assert_true(encoded.contains("\"schema_version\":\"1\""))
  let decoded = try! LoomarkDocumentArchive::from_json_string(
    encoded,
    validation_agent_id="archive-roundtrip-red",
  )
  assert_true(decoded.document_id() == archive.document_id())
  assert_eq(decoded.portable_markdown(), editor.portable_markdown())
  assert_true(decoded.history() == archive.history())
}

///|
test "archive decode error matrix" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="archive-errors-source",
    source="# Title\n",
  )
  let document_id = try! LoomarkDocumentId::from_string("doc-errors")
  let archive = try! LoomarkDocumentArchive::capture(document_id~, editor~)
  let encoded = archive.to_json_string()
  assert_true(encoded.contains("\"schema_version\":\"1\""))

  let newer : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "{\"schema_version\":\"2\",\"document_id\":\"x\",\"portable_markdown\":42,\"history\":false,\"extensions\":{}}",
      validation_agent_id="archive-errors-newer",
    ),
  ) catch {
    error => Err(error)
  }
  match newer {
    Err(LoomarkArchiveDecodeError::UnsupportedNewerVersion(version~)) =>
      assert_eq(version, "2")
    _ => fail("expected version 2 to be unsupported")
  }

  let too_large : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "{\"schema_version\":\"2147483648\"}",
      validation_agent_id="archive-errors-int-overflow",
    ),
  ) catch {
    error => Err(error)
  }
  match too_large {
    Err(LoomarkArchiveDecodeError::UnsupportedNewerVersion(version~)) =>
      assert_eq(version, "2147483648")
    _ => fail("expected 2147483648 to be unsupported")
  }

  let much_too_large : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "{\"schema_version\":\"999999999999999999999999999999999999999999999999999\"}",
      validation_agent_id="archive-errors-huge-version",
    ),
  ) catch {
    error => Err(error)
  }
  match much_too_large {
    Err(LoomarkArchiveDecodeError::UnsupportedNewerVersion(version~)) =>
      assert_eq(version, "999999999999999999999999999999999999999999999999999")
    _ => fail("expected huge version to be unsupported")
  }

  let malformed_schema_versions = [
    "{\"schema_version\":1}", "{\"schema_version\":1.0}", "{\"schema_version\":1e0}",
    "{\"schema_version\":0}", "{\"schema_version\":-1}", "{\"schema_version\":\"\"}",
    "{\"schema_version\":\"0\"}", "{\"schema_version\":\"00\"}", "{\"schema_version\":\"01\"}",
    "{\"schema_version\":\"0001\"}", "{\"schema_version\":\"-1\"}", "{\"schema_version\":\"1.0\"}",
    "{\"schema_version\":\"1e0\"}", "{\"schema_version\":true}", "{\"schema_version\":false}",
    "{\"schema_version\":null}", "{\"schema_version\":{}}", "{\"schema_version\":[]}",
  ]
  for schema_version_json in malformed_schema_versions {
    let malformed : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
      LoomarkDocumentArchive::from_json_string(
        schema_version_json,
        validation_agent_id="archive-errors-malformed-schema-version",
      ),
    ) catch {
      error => Err(error)
    }
    assert_true(
      malformed is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)),
    )
  }

  let malformed : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "not-json",
      validation_agent_id="archive-errors-malformed",
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(malformed is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)))

  let missing : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "{\"schema_version\":\"1\"}",
      validation_agent_id="archive-errors-missing",
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(missing is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)))

  let unknown : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(
        old="\"extensions\":{}",
        new="\"extensions\":{},\"unknown\":true",
      ),
      validation_agent_id="archive-errors-unknown",
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(unknown is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)))

  let corrupt : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(old="\"history\":\"", new="\"history\":\"not-history"),
      validation_agent_id="archive-errors-corrupt",
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(corrupt is Err(LoomarkArchiveDecodeError::CorruptHistory(_)))

  let mismatch : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(old="# Title\\n", new="# Other\\n"),
      validation_agent_id="archive-errors-mismatch",
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(
    mismatch is Err(LoomarkArchiveDecodeError::PortableTextHistoryMismatch),
  )

  let empty_id : Result[LoomarkDocumentArchive, LoomarkArchiveDecodeError] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(old="doc-errors", new=""),
      validation_agent_id="archive-errors-empty-id",
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(empty_id is Err(LoomarkArchiveDecodeError::EmptyDocumentId))

  let nonempty_extensions : Result[
    LoomarkDocumentArchive,
    LoomarkArchiveDecodeError,
  ] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(
        old="\"extensions\":{}",
        new="\"extensions\":{\"future\":true}",
      ),
      validation_agent_id="archive-errors-extensions",
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(
    nonempty_extensions is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)),
  )
}

///|
test "decoded archive continues through public edit and merge APIs" {
  let source = "First\n\nSecond\n"
  let editor = try! @markdown.MarkdownEditor(
    agent_id="archive-continued-source",
    source~,
  )
  let document_id = try! LoomarkDocumentId::from_string("doc-continued")
  let archive = try! LoomarkDocumentArchive::capture(document_id~, editor~)
  let decoded = try! LoomarkDocumentArchive::from_json_string(
    archive.to_json_string(),
    validation_agent_id="archive-continued-decode",
  )
  let history = decoded.history()
  let reopened = try! @markdown.MarkdownEditor::open(
    agent_id="archive-continued-editor",
    history~,
  )
  let first = reopened.snapshot().blocks().to_array()[0]
  assert_true(
    reopened.commit(
      @markdown.MarkdownEditRequest::CommitEdit(
        node_id=first.node_id(),
        new_text="Changed",
      ),
    )
    is Ok(_),
  )
  let second = reopened.snapshot().blocks().to_array()[1]
  assert_true(
    reopened.commit(
      @markdown.MarkdownEditRequest::MergeWithPrevious(node_id=second.node_id()),
    )
    is Ok(_),
  )
  assert_eq(reopened.portable_markdown(), "ChangedSecond\n")
}
