///|
test "FileSummary depends on FileText" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("hello\nworld"))
  let _ = store.compute(FileSummary("a.mbt"))
  let deps = store.dependencies_of(FileSummary("a.mbt"))
  assert_true(deps.contains(FileText("a.mbt")))
}

///|
test "revision clock is incr backed" {
  let store = CognitionStore::new()
  inspect(store.current_revision().to_int(), content="0")
  let _ = store.set_input(FileText("a.mbt"), Text("hello"))
  inspect(store.current_revision().to_int(), content="1")
}

///|
test "dependency edge snapshot is incr backed" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("hello"))
  let _ = store.compute(FileSummary("a.mbt"))
  let edges = store.dependency_edges()
  assert_true(
    edges.contains({ from: FileSummary("a.mbt"), input: FileText("a.mbt") }),
  )
}

///|
test "set_input only accepts FileText Text pairs" {
  let store = CognitionStore::new()
  inspect(store.set_input(RepoSummary, Summary("bad")), content="false")
  inspect(store.set_input(FileText("a.mbt"), Summary("bad")), content="false")
  inspect(store.get_value(RepoSummary) is None, content="true")
  inspect(store.get_value(FileText("a.mbt")) is None, content="true")
}

///|
test "known_files tracks FileText inputs in sorted order" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("b.mbt"), Text("two"))
  let _ = store.set_input(FileText("a.mbt"), Text("one"))

  inspect(store.known_files().join(","), content="a.mbt,b.mbt")
}

///|
test "remove_file unregisters file and recomputes repo without deleted summary" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.set_input(FileText("b.mbt"), Text("two"))
  let _ = store.compute(QueryContext("what changed?"))

  inspect(store.remove_file("missing.mbt"), content="false")
  inspect(store.remove_file("a.mbt"), content="true")
  inspect(store.known_files().join(","), content="b.mbt")
  inspect(store.get_value(FileText("a.mbt")) is None, content="true")
  inspect(store.get_value(FileSummary("a.mbt")) is None, content="true")
  inspect(store.is_dirty(RepoSummary), content="true")
  inspect(store.is_dirty(QueryContext("what changed?")), content="true")

  let recomputed = store.recompute_dirty()
  inspect(recomputed.contains(RepoSummary), content="true")
  inspect(recomputed.contains(QueryContext("what changed?")), content="true")
  let deps = store.dependencies_of(RepoSummary)
  inspect(deps.contains(FileSummary("a.mbt")), content="false")
  inspect(deps.contains(FileSummary("b.mbt")), content="true")
  match store.get_value(RepoSummary) {
    Some(Summary(summary)) => {
      inspect(summary.contains("a.mbt"), content="false")
      inspect(summary.contains("b.mbt"), content="true")
    }
    _ => fail("expected repo summary")
  }
}

///|
test "remove_file cleans deleted file dependency graph after recompute" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.set_input(FileText("b.mbt"), Text("two"))
  let _ = store.compute(QueryContext("what changed?"))

  inspect(store.remove_file("a.mbt"), content="true")
  inspect(store.known_files().join(","), content="b.mbt")
  inspect(store.get_value(FileText("a.mbt")) is None, content="true")
  inspect(store.get_value(FileSummary("a.mbt")) is None, content="true")
  inspect(store.is_dirty(RepoSummary), content="true")
  inspect(store.is_dirty(QueryContext("what changed?")), content="true")
  inspect(
    dependency_edges_mention_path(store.dependency_edges(), "a.mbt"),
    content="false",
  )
  inspect(store.dependents_of(FileText("a.mbt")).length(), content="0")
  inspect(store.dependents_of(FileSummary("a.mbt")).length(), content="0")

  let _ = store.recompute_dirty()
  inspect(
    dependency_edges_mention_path(store.dependency_edges(), "a.mbt"),
    content="false",
  )
  inspect(store.dependents_of(FileText("a.mbt")).length(), content="0")
  inspect(store.dependents_of(FileSummary("a.mbt")).length(), content="0")
  let repo_deps = store.dependencies_of(RepoSummary)
  inspect(repo_deps.contains(FileSummary("a.mbt")), content="false")
  inspect(repo_deps.contains(FileSummary("b.mbt")), content="true")
}

///|
test "caller path strings are distinct workspace identities" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("foo.mbt"), Text("one"))
  let _ = store.set_input(FileText("./foo.mbt"), Text("two"))

  inspect(store.known_files().join(","), content="foo.mbt,./foo.mbt")

  let _ = store.compute(RepoSummary)
  let deps = store.dependencies_of(RepoSummary)
  inspect(deps.contains(FileSummary("./foo.mbt")), content="true")
  inspect(deps.contains(FileSummary("foo.mbt")), content="true")

  inspect(store.remove_file("./foo.mbt"), content="true")
  inspect(store.known_files().join(","), content="foo.mbt")
  inspect(store.get_value(FileText("foo.mbt")) is Some(_), content="true")
}

///|
fn dependency_edges_mention_path(
  edges : Array[Dependency],
  path : String,
) -> Bool {
  for edge in edges {
    if cognition_key_mentions_path(edge.from, path) ||
      cognition_key_mentions_path(edge.input, path) {
      return true
    }
  }
  false
}

///|
fn cognition_key_mentions_path(key : CognitionKey, path : String) -> Bool {
  match key {
    FileText(candidate) => candidate == path
    FileSummary(candidate) => candidate == path
    RepoSummary => false
    QueryContext(_) => false
  }
}

///|
test "changing one FileText marks its FileSummary dirty" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("hello"))
  let _ = store.compute(FileSummary("a.mbt"))
  let _ = store.set_input(FileText("a.mbt"), Text("hello again"))
  inspect(store.is_dirty(FileSummary("a.mbt")), content="true")
}

///|
test "RepoSummary becomes dirty when a FileSummary changes" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("hello"))
  let _ = store.compute(FileSummary("a.mbt"))
  let _ = store.compute(RepoSummary)
  store.mark_dirty(FileSummary("a.mbt"))
  inspect(store.is_dirty(RepoSummary), content="true")
}

///|
test "unrelated FileSummary is not recomputed when another file changes" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.set_input(FileText("b.mbt"), Text("two"))
  let _ = store.compute(FileSummary("a.mbt"))
  let _ = store.compute(FileSummary("b.mbt"))
  let _ = store.compute(RepoSummary)
  let a_before = store.recompute_count(FileSummary("a.mbt"))
  let b_before = store.recompute_count(FileSummary("b.mbt"))

  let _ = store.set_input(FileText("a.mbt"), Text("one changed"))
  let recomputed = store.recompute_dirty()

  inspect(recomputed.contains(FileSummary("a.mbt")), content="true")
  inspect(recomputed.contains(FileSummary("b.mbt")), content="false")
  inspect(
    store.recompute_count(FileSummary("a.mbt")) == a_before + 1,
    content="true",
  )
  inspect(
    store.recompute_count(FileSummary("b.mbt")) == b_before,
    content="true",
  )
}

///|
test "QueryContext depends on RepoSummary" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("hello"))
  let _ = store.compute(FileSummary("a.mbt"))
  let _ = store.compute(RepoSummary)
  let _ = store.compute(QueryContext("what changed?"))
  let deps = store.dependencies_of(QueryContext("what changed?"))
  assert_true(deps.contains(RepoSummary))
}

///|
test "RepoSummary first build seeds summaries from FileText inputs" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.set_input(FileText("b.mbt"), Text("two\nlines"))

  let _ = store.compute(RepoSummary)

  let deps = store.dependencies_of(RepoSummary)
  assert_true(deps.contains(FileSummary("a.mbt")))
  assert_true(deps.contains(FileSummary("b.mbt")))
  inspect(store.recompute_count(FileSummary("a.mbt")), content="1")
  inspect(store.recompute_count(FileSummary("b.mbt")), content="1")
}

///|
test "QueryContext first build seeds RepoSummary from FileText inputs" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))

  let _ = store.compute(QueryContext("what changed?"))

  let deps = store.dependencies_of(RepoSummary)
  assert_true(deps.contains(FileSummary("a.mbt")))
  match store.get_value(QueryContext("what changed?")) {
    Some(ContextBundle(items)) =>
      inspect(items.join("\n").contains("a.mbt"), content="true")
    _ => fail("expected context bundle")
  }
}

///|
test "new FileSummary invalidates existing repo context" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.compute(FileSummary("a.mbt"))
  let _ = store.compute(RepoSummary)
  let _ = store.compute(QueryContext("what changed?"))

  let _ = store.set_input(FileText("b.mbt"), Text("two"))
  let recomputed = store.recompute_dirty()

  inspect(recomputed.contains(FileSummary("b.mbt")), content="true")
  inspect(recomputed.contains(RepoSummary), content="true")
  inspect(recomputed.contains(QueryContext("what changed?")), content="true")
  let deps = store.dependencies_of(RepoSummary)
  assert_true(deps.contains(FileSummary("b.mbt")))
}

///|
test "new FileText invalidates query context before RepoSummary exists" {
  let store = CognitionStore::new()
  let _ = store.compute(QueryContext("what changed?"))

  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let recomputed = store.recompute_dirty()

  inspect(recomputed.contains(FileSummary("a.mbt")), content="true")
  inspect(recomputed.contains(RepoSummary), content="true")
  inspect(recomputed.contains(QueryContext("what changed?")), content="true")
  let deps = store.dependencies_of(RepoSummary)
  assert_true(deps.contains(FileSummary("a.mbt")))
}

///|
test "dirty traversal skips already dirty subtrees" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.compute(FileSummary("a.mbt"))
  let _ = store.compute(RepoSummary)
  let _ = store.compute(QueryContext("what changed?"))

  store.mark_dirty(RepoSummary)
  let changed = store.dirty_dependents(FileSummary("a.mbt"))

  inspect(changed.contains(RepoSummary), content="false")
  inspect(changed.contains(QueryContext("what changed?")), content="false")
  inspect(store.is_dirty(QueryContext("what changed?")), content="true")
}

///|
test "returned ContextBundle cannot mutate stored value" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("hello"))
  let _ = store.compute(FileSummary("a.mbt"))
  let _ = store.compute(RepoSummary)
  let _ = store.compute(QueryContext("what changed?"))
  match store.get_value(QueryContext("what changed?")) {
    Some(ContextBundle(items)) => items.push("external mutation")
    _ => fail("expected context bundle")
  }
  match store.get_value(QueryContext("what changed?")) {
    Some(ContextBundle(items)) =>
      inspect(items.contains("external mutation"), content="false")
    _ => fail("expected context bundle")
  }
}

///|
test "demo trace shows selective recomputation" {
  inspect(
    demo_trace().join("\n"),
    content=(
      #|dirty after src/a.mbt edit: FileSummary(src/a.mbt), RepoSummary, QueryContext(what changed?)
      #|recomputed: FileSummary(src/a.mbt), RepoSummary, QueryContext(what changed?)
      #|FileSummary(src/a.mbt) count: 2
      #|FileSummary(src/b.mbt) count: 1
    ),
  )
}
