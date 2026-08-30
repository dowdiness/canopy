///|
test "PreviewEngine rejects an operation owned by an older activation" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate(1))
  guard engine.prepare_owned(1, "# First\n") is Some(Ok(_)) else {
    fail("current activation should prepare")
  }
  let next_revision_key_floor = engine.next_revision_key
  assert_true(engine.activate(2))
  guard engine.prepare_owned(1, "# Stale\n") is None else {
    fail("stale activation should not prepare")
  }
  guard engine.state is NoPair else {
    fail("stale preparation mutated the new activation")
  }
  guard engine.prepare_owned(2, "# Current\n") is Some(Ok(_)) else {
    fail("new activation should prepare")
  }
  match engine.state {
    Healthy(semantics~, ..) =>
      for key in semantics.publish().top_level_revision_keys() {
        assert_true(key >= next_revision_key_floor)
      }
    NoPair | Broken => fail("new activation did not own a healthy parser")
  }
  assert_true(engine.next_revision_key > next_revision_key_floor)
  assert_false(engine.discard_owned(1))
  guard engine.apply_owned(1, @text_change.ReplaceAll("# Stale\n"), "# Stale\n")
    is None else {
    fail("stale activation should not apply")
  }
  match engine.state {
    Healthy(source~, ..) => assert_eq(source, "# Current\n")
    NoPair | Broken => fail("stale operation changed current parser")
  }
  assert_false(engine.activate(1))
}

///|
test "PreviewEngine stays uninitialized until preparation" {
  let engine = PreviewEngine::PreviewEngine()
  guard engine.state is NoPair else { abort("parser initialized too early") }
  assert_eq(
    engine.apply(@text_change.ReplaceAll("Text only"), "Text only"),
    Ok(()),
  )
  guard engine.state is NoPair else { abort("Text-only change created parser") }
}

///|
test "PreviewEngine prepares one semantic result and advances exact edits" {
  let engine = PreviewEngine::PreviewEngine()
  let initial = engine.prepare("Heading\n")
  guard initial is Ok(initial) else { abort("initial preparation failed") }
  assert_true(!initial.empty)

  let change = @text_change.ReplaceRange(start=0, delete_len=0, inserted="# ")
  assert_eq(engine.apply(change, "# Heading\n"), Ok(()))
  let refreshed = engine.refresh("# Heading\n")
  guard refreshed is Ok(refreshed) else { abort("refresh failed") }
  assert_true(!refreshed.empty)
  match engine.state {
    Healthy(source~, ..) => assert_eq(source, "# Heading\n")
    NoPair | Broken => abort("expected healthy Preview parser")
  }
}

///|
test "PreviewEngine publishes lazy task-list HTML after an edit" {
  let source = "- [ ] todo\n\nTail text.\n"
  let engine = PreviewEngine::PreviewEngine()
  guard engine.prepare(source) is Ok(initial) else {
    abort("initial task-list preparation failed")
  }
  let initial_html = @rabbita_testing.server_side_render(() => initial.html)
  assert_true(initial_html.contains("type=\"checkbox\""))
  assert_true(!initial_html.contains("checked"))

  let position = source.find("[ ]").unwrap() + 1
  let checked_source = source[:position].to_owned() +
    "x" +
    source[position + 1:].to_owned()
  let change = @text_change.ReplaceRange(
    start=position,
    delete_len=1,
    inserted="x",
  )
  assert_eq(engine.apply(change, checked_source), Ok(()))
  guard engine.refresh(checked_source) is Ok(checked) else {
    abort("checked task-list refresh failed")
  }
  let checked_html = @rabbita_testing.server_side_render(() => checked.html)
  assert_true(checked_html.contains("type=\"checkbox\""))
  assert_true(checked_html.contains("checked"))
  assert_true(!checked_html.contains("[x]"))
}

///|
test "PreviewEngine keeps a healthy parser for ReplaceAll" {
  let engine = PreviewEngine::PreviewEngine()
  ignore(engine.prepare("Before\n"))
  assert_eq(
    engine.apply(@text_change.ReplaceAll("# After\n"), "# After\n"),
    Ok(()),
  )
  guard engine.refresh("# After\n") is Ok(result) else {
    abort("ReplaceAll refresh failed")
  }
  assert_true(!result.empty)
  match engine.state {
    Healthy(source~, ..) => assert_eq(source, "# After\n")
    NoPair | Broken => abort("expected healthy Preview parser")
  }
}

///|
test "PreviewEngine discards a stale preparation parser before retry" {
  let engine = PreviewEngine::PreviewEngine()
  ignore(engine.prepare("stale\n"))
  engine.discard()
  guard engine.state is Broken else { abort("stale parser stayed active") }
  guard engine.refresh("latest\n") is Ok(_) else {
    abort("discarded parser was not replaced")
  }
  match engine.state {
    Healthy(source~, ..) => assert_eq(source, "latest\n")
    NoPair | Broken => abort("expected replacement Preview parser")
  }
}

///|
test "PreviewEngine replaces only an unusable parser on allowed refresh" {
  let engine = PreviewEngine::PreviewEngine()
  ignore(engine.prepare("Before\n"))
  let replacement_key_floor = engine.next_revision_key
  let inconsistent = @text_change.ReplaceRange(
    start=0,
    delete_len=1,
    inserted="X",
  )
  guard engine.apply(inconsistent, "not-the-change") is Err(_) else {
    abort("inconsistent transition should fail")
  }
  guard engine.state is Broken else { abort("failed parser stayed active") }

  guard engine.refresh("latest\n") is Ok(result) else {
    abort("broken parser replacement failed")
  }
  assert_true(!result.empty)
  match engine.state {
    Healthy(source~, semantics~, ..) => {
      assert_eq(source, "latest\n")
      let publication = semantics.publish()
      for key in publication.top_level_revision_keys() {
        assert_true(key >= replacement_key_floor)
      }
      assert_true(engine.next_revision_key > replacement_key_floor)
    }
    NoPair | Broken => abort("expected replacement Preview parser")
  }
}
