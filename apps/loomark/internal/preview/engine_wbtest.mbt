///|
test "PreviewEngine stays uninitialized until preparation" {
  let engine = PreviewEngine::PreviewEngine()
  guard engine.state is NoPair else { abort("pair initialized too early") }
  assert_eq(
    engine.apply(@text_change.ReplaceAll("Text only"), "Text only"),
    Ok(()),
  )
  guard engine.state is NoPair else { abort("Text-only change created pair") }
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
    NoPair | Broken => abort("expected healthy Preview pair")
  }
}

///|
test "PreviewEngine keeps a healthy pair for ReplaceAll" {
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
    NoPair | Broken => abort("expected healthy Preview pair")
  }
}

///|
test "PreviewEngine discards a stale preparation pair before retry" {
  let engine = PreviewEngine::PreviewEngine()
  ignore(engine.prepare("stale\n"))
  engine.discard()
  guard engine.state is Broken else { abort("stale pair stayed active") }
  guard engine.refresh("latest\n") is Ok(_) else {
    abort("discarded pair was not replaced")
  }
  match engine.state {
    Healthy(source~, ..) => assert_eq(source, "latest\n")
    NoPair | Broken => abort("expected replacement Preview pair")
  }
}

///|
test "PreviewEngine replaces only an unusable pair on allowed refresh" {
  let engine = PreviewEngine::PreviewEngine()
  ignore(engine.prepare("Before\n"))
  let inconsistent = @text_change.ReplaceRange(
    start=0,
    delete_len=1,
    inserted="X",
  )
  guard engine.apply(inconsistent, "not-the-change") is Err(_) else {
    abort("inconsistent transition should fail")
  }
  guard engine.state is Broken else { abort("failed pair stayed active") }

  guard engine.refresh("latest\n") is Ok(result) else {
    abort("broken pair replacement failed")
  }
  assert_true(!result.empty)
  match engine.state {
    Healthy(source~, ..) => assert_eq(source, "latest\n")
    NoPair | Broken => abort("expected replacement Preview pair")
  }
}
