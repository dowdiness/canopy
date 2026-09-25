///|
test "PreviewEngine rejects an operation owned by an older activation" {
  let engine = PreviewEngine::PreviewEngine()
  assert_true(engine.activate_generation(1))
  guard engine.prepare_owned(1, "# First\n") is Some(Ok(first)) else {
    fail("current activation should prepare")
  }
  assert_true(engine.accept(first))
  let next_lazy_key_floor = engine.next_lazy_key
  assert_true(engine.activate_generation(2))
  guard engine.prepare_owned(1, "# Stale\n") is None else {
    fail("stale activation should not prepare")
  }
  guard engine.state is NoPair else {
    fail("stale preparation mutated the new activation")
  }
  guard engine.prepare_owned(2, "# Current\n") is Some(Ok(current)) else {
    fail("new activation should prepare")
  }
  assert_true(engine.accept(current))
  guard engine.accepted_render is Some(accepted) else {
    fail("new activation did not accept renderer state")
  }
  for key in accepted.lazy_keys {
    assert_true(key >= next_lazy_key_floor)
  }
  assert_true(engine.next_lazy_key > next_lazy_key_floor)
  assert_false(engine.discard_owned(1))
  guard engine.apply_owned(1, @text_change.ReplaceAll("# Stale\n"), "# Stale\n")
    is None else {
    fail("stale activation should not apply")
  }
  match engine.state {
    Healthy(source~, ..) => assert_eq(source, "# Current\n")
    NoPair | Broken => fail("stale operation changed current parser")
  }
  assert_false(engine.activate_generation(1))
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
  assert_true(engine.accept(initial))
  assert_true(!initial.empty)

  let change = @text_change.ReplaceRange(start=0, delete_len=0, inserted="# ")
  assert_eq(engine.apply(change, "# Heading\n"), Ok(()))
  let refreshed = engine.refresh("# Heading\n")
  guard refreshed is Ok(refreshed) else { abort("refresh failed") }
  assert_true(engine.accept(refreshed))
  assert_true(!refreshed.empty)
  match engine.state {
    Healthy(source~, ..) => assert_eq(source, "# Heading\n")
    NoPair | Broken => abort("expected healthy Preview parser")
  }
}

///|
test "PreviewEngine transports its lazy keys across previous-block matches" {
  let source = "Alpha.\n\nBeta.\n\nGamma.\n"
  let engine = PreviewEngine::PreviewEngine()
  guard engine.prepare(source) is Ok(initial_output) else {
    abort("initial key transport preparation failed")
  }
  assert_true(engine.accept(initial_output))
  guard engine.accepted_render is Some(initial) else {
    abort("initial renderer state missing")
  }
  let initial_keys = initial.lazy_keys.copy()

  let position = source.find("Beta").unwrap()
  let updated = source[:position].to_owned() +
    "Z" +
    source[position + 1:].to_owned()
  let change = @text_change.ReplaceRange(
    start=position,
    delete_len=1,
    inserted="Z",
  )
  assert_eq(engine.apply(change, updated), Ok(()))
  guard engine.refresh(updated) is Ok(current_output) else {
    abort("updated key transport refresh failed")
  }
  assert_true(engine.accept(current_output))
  guard engine.accepted_render is Some(current) else {
    abort("updated renderer state missing")
  }
  assert_eq(current.lazy_keys[0], initial_keys[0])
  assert_true(current.lazy_keys[1] != initial_keys[1])
  assert_eq(current.lazy_keys[2], initial_keys[2])
}

///|
test "PreviewEngine rejects a stale rendered candidate before acceptance" {
  let source = "Alpha.\n\nBeta.\n\nGamma.\n"
  let engine = PreviewEngine::PreviewEngine()
  guard engine.prepare(source) is Ok(initial_output) else {
    abort("initial candidate preparation failed")
  }
  assert_true(engine.accept(initial_output))
  guard engine.accepted_render is Some(initial) else {
    abort("initial candidate was not accepted")
  }
  let initial_keys = initial.lazy_keys.copy()

  let beta = source.find("Beta").unwrap()
  let first_source = source[:beta].to_owned() +
    "Z" +
    source[beta + 1:].to_owned()
  assert_eq(
    engine.apply(
      @text_change.ReplaceRange(start=beta, delete_len=1, inserted="Z"),
      first_source,
    ),
    Ok(()),
  )
  guard engine.refresh(first_source) is Ok(stale_output) else {
    abort("stale candidate refresh failed")
  }

  let gamma = first_source.find("Gamma").unwrap()
  let current_source = first_source[:gamma].to_owned() +
    "D" +
    first_source[gamma + 1:].to_owned()
  assert_eq(
    engine.apply(
      @text_change.ReplaceRange(start=gamma, delete_len=1, inserted="D"),
      current_source,
    ),
    Ok(()),
  )
  guard engine.refresh(current_source) is Ok(current_output) else {
    abort("current candidate refresh failed")
  }

  assert_false(engine.accept(stale_output))
  assert_true(engine.accept(current_output))
  guard engine.accepted_render is Some(current) else {
    abort("current candidate was not accepted")
  }
  for key in current.lazy_keys {
    assert_true(!initial_keys.contains(key))
  }
}

///|
test "PreviewEngine rejects duplicate and out-of-bounds previous indexes" {
  assert_false(previous_block_indexes_are_valid([Some(0), Some(0)][:], 2))
  assert_false(previous_block_indexes_are_valid([Some(0), Some(2)][:], 2))
  assert_true(previous_block_indexes_are_valid([Some(1), Some(0)][:], 2))
}

///|
test "PreviewEngine refreshes every lazy key after structural fallback" {
  let source = "Alpha.\n\nBeta.\n"
  let engine = PreviewEngine::PreviewEngine()
  guard engine.prepare(source) is Ok(initial_output) else {
    abort("structural fallback preparation failed")
  }
  assert_true(engine.accept(initial_output))
  guard engine.accepted_render is Some(initial) else {
    abort("initial renderer state missing")
  }
  let initial_keys = initial.lazy_keys.copy()
  let position = source.find("Beta").unwrap()
  let inserted = "Inserted.\n\n"
  let changed = source[:position].to_owned() +
    inserted +
    source[position:].to_owned()
  let change = @text_change.ReplaceRange(
    start=position,
    delete_len=0,
    inserted~,
  )
  assert_eq(engine.apply(change, changed), Ok(()))
  guard engine.refresh(changed) is Ok(current_output) else {
    abort("structural fallback refresh failed")
  }
  assert_true(engine.accept(current_output))
  guard engine.accepted_render is Some(current) else {
    abort("fallback renderer state missing")
  }
  assert_eq(current.lazy_keys.length(), 3)
  for key in current.lazy_keys {
    assert_true(!initial_keys.contains(key))
  }
}

///|
test "PreviewEngine publishes lazy task-list HTML after an edit" {
  let source = "- [ ] todo\n\nTail text.\n"
  let engine = PreviewEngine::PreviewEngine()
  guard engine.prepare(source) is Ok(initial) else {
    abort("initial task-list preparation failed")
  }
  assert_true(engine.accept(initial))
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
  assert_true(engine.accept(checked))
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
  guard engine.prepare("Before\n") is Ok(initial_output) else {
    abort("replacement test preparation failed")
  }
  assert_true(engine.accept(initial_output))
  let replacement_key_floor = engine.next_lazy_key
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
  assert_true(engine.accept(result))
  assert_true(!result.empty)
  match engine.state {
    Healthy(source~, ..) => assert_eq(source, "latest\n")
    NoPair | Broken => abort("expected replacement Preview parser")
  }
  guard engine.accepted_render is Some(accepted) else {
    abort("replacement Preview did not accept renderer state")
  }
  for key in accepted.lazy_keys {
    assert_true(key >= replacement_key_floor)
  }
  assert_true(engine.next_lazy_key > replacement_key_floor)
}
