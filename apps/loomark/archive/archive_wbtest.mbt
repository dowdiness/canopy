///|
fn archive_decode_open_limits(
  max_encoded_bytes? : Int = 1024 * 1024,
  max_decoded_operations? : Int = 10000,
  max_pending_operations? : Int = 1000,
  max_parents_per_operation? : Int = 256,
) -> @markdown.MarkdownArchiveOpenLimits {
  try! @markdown.MarkdownArchiveOpenLimits(
    max_encoded_bytes~,
    max_decoded_operations~,
    max_pending_operations~,
    max_parents_per_operation~,
  )
}

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
    open_limits=archive_decode_open_limits(),
  )
  assert_true(decoded.document_id() == archive.document_id())
  assert_eq(decoded.portable_markdown(), editor.portable_markdown())
  assert_true(decoded.history() == archive.history())
}

///|
test "archive structural decode leaves history admission to the repository" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="archive-decode-only-source",
    source="hello",
  )
  let document_id = try! LoomarkDocumentId::from_string("doc-decode-only")
  let archive = try! LoomarkDocumentArchive::capture(document_id~, editor~)
  let decoded = try! LoomarkDocumentArchive::decode_json_string(
    archive
    .to_json_string()
    .replace(
      old="\"portable_markdown\":\"hello\"",
      new="\"portable_markdown\":\"other\"",
    ),
  )
  assert_eq(decoded.portable_markdown(), "other")
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

  let capacity : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded,
      validation_agent_id="archive-errors-capacity",
      open_limits=archive_decode_open_limits(max_encoded_bytes=0),
    ),
  ) catch {
    error => Err(error)
  }
  match capacity {
    Err(
      LoomarkArchiveDecodeError::LimitExceeded(
        dimension=@markdown.MarkdownArchiveLimitDimension::EncodedBytes,
        maximum=0,
        actual~
      )
    ) => assert_true(actual > 0)
    _ => fail("expected archive limit failure")
  }

  let newer : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "{\"schema_version\":\"2\",\"document_id\":\"x\",\"portable_markdown\":42,\"history\":false,\"extensions\":{}}",
      validation_agent_id="archive-errors-newer",
      open_limits=archive_decode_open_limits(),
    ),
  ) catch {
    error => Err(error)
  }
  match newer {
    Err(LoomarkArchiveDecodeError::UnsupportedNewerVersion(version~)) =>
      assert_eq(version, "2")
    _ => fail("expected version 2 to be unsupported")
  }

  let too_large : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "{\"schema_version\":\"2147483648\"}",
      validation_agent_id="archive-errors-int-overflow",
      open_limits=archive_decode_open_limits(),
    ),
  ) catch {
    error => Err(error)
  }
  match too_large {
    Err(LoomarkArchiveDecodeError::UnsupportedNewerVersion(version~)) =>
      assert_eq(version, "2147483648")
    _ => fail("expected 2147483648 to be unsupported")
  }

  let much_too_large : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "{\"schema_version\":\"999999999999999999999999999999999999999999999999999\"}",
      validation_agent_id="archive-errors-huge-version",
      open_limits=archive_decode_open_limits(),
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
    let malformed : Result[LoomarkDocumentArchive, Error] = Ok(
      LoomarkDocumentArchive::from_json_string(
        schema_version_json,
        validation_agent_id="archive-errors-malformed-schema-version",
        open_limits=archive_decode_open_limits(),
      ),
    ) catch {
      error => Err(error)
    }
    assert_true(
      malformed is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)),
    )
  }

  let malformed : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "not-json",
      validation_agent_id="archive-errors-malformed",
      open_limits=archive_decode_open_limits(),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(malformed is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)))

  let missing : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      "{\"schema_version\":\"1\"}",
      validation_agent_id="archive-errors-missing",
      open_limits=archive_decode_open_limits(),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(missing is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)))

  let unknown : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(
        old="\"extensions\":{}",
        new="\"extensions\":{},\"unknown\":true",
      ),
      validation_agent_id="archive-errors-unknown",
      open_limits=archive_decode_open_limits(),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(unknown is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)))

  let corrupt : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(old="\"history\":\"", new="\"history\":\"not-history"),
      validation_agent_id="archive-errors-corrupt",
      open_limits=archive_decode_open_limits(),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(corrupt is Err(LoomarkArchiveDecodeError::CorruptHistory(_)))

  let mismatch : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(old="# Title\\n", new="# Other\\n"),
      validation_agent_id="archive-errors-mismatch",
      open_limits=archive_decode_open_limits(),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(
    mismatch is Err(LoomarkArchiveDecodeError::PortableTextHistoryMismatch),
  )

  let empty_id : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(old="doc-errors", new=""),
      validation_agent_id="archive-errors-empty-id",
      open_limits=archive_decode_open_limits(),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(empty_id is Err(LoomarkArchiveDecodeError::EmptyDocumentId))

  let nonempty_extensions : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded.replace(
        old="\"extensions\":{}",
        new="\"extensions\":{\"future\":true}",
      ),
      validation_agent_id="archive-errors-extensions",
      open_limits=archive_decode_open_limits(),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(
    nonempty_extensions is Err(LoomarkArchiveDecodeError::MalformedEnvelope(_)),
  )
}

///|
test "archive decode distinguishes incomplete history from limit-exceeded" {
  let source = try! @markdown.MarkdownEditor(
    agent_id="archive-gap-source",
    source="x",
  )
  let cut = source.version()
  assert_true(
    source.commit(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=1,
        delete_len=0,
        inserted="y",
      ),
    )
    is Ok(_),
  )
  let gapped = try! source.history_since(version=cut)
  let encoded = Json::object({
    "schema_version": Json::string(LOOMARK_ARCHIVE_SCHEMA_VERSION.to_string()),
    "document_id": Json::string("doc-gap"),
    "portable_markdown": Json::string("xy"),
    "history": Json::string(gapped.to_json_string()),
    "extensions": Json::empty_object(),
  }).stringify()

  let incomplete : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded,
      validation_agent_id="archive-gap-incomplete",
      open_limits=archive_decode_open_limits(max_pending_operations=1),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(incomplete is Err(LoomarkArchiveDecodeError::IncompleteHistory))

  let capacity : Result[LoomarkDocumentArchive, Error] = Ok(
    LoomarkDocumentArchive::from_json_string(
      encoded,
      validation_agent_id="archive-gap-capacity",
      open_limits=archive_decode_open_limits(max_pending_operations=0),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(
    capacity
    is Err(
      LoomarkArchiveDecodeError::LimitExceeded(
        dimension=@markdown.MarkdownArchiveLimitDimension::PendingOperations,
        maximum=0,
        actual=1
      )
    ),
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
    open_limits=archive_decode_open_limits(),
  )
  let history = decoded.history()
  let reopened = try! @markdown.MarkdownEditor::open(
    agent_id="archive-continued-editor",
    history~,
    open_limits=archive_decode_open_limits(),
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
