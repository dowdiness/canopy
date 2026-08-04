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
    PackedContext(_, _) => false
    BudgetedContext(_, _, _) => false
    TruncatedContext(_, _, _) => false
  }
}

///|
test "pack_context returns provenance-bearing budgeted items" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("b.mbt"), Text("two"))
  let _ = store.set_input(FileText("a.mbt"), Text("one"))

  let items = store.pack_context("what changed?", 2)

  inspect(items.length(), content="2")
  inspect(items[0].source == RepoSummary, content="true")
  inspect(items[0].source_revision.to_int() > 0, content="true")
  inspect(items[0].payload.contains("repo summary"), content="true")
  inspect(
    items[0].reason,
    content="workspace overview for query: what changed?",
  )
  inspect(items[1].source == FileSummary("a.mbt"), content="true")
  inspect(items[1].payload.contains("a.mbt"), content="true")
  inspect(items[1].reason, content="workspace file summary")
}

///|
test "pack_context prefers file summaries that match the query" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/beta.mbt"), Text("beta"))
  let _ = store.set_input(FileText("src/alpha.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/gamma.mbt"), Text("gamma"))

  let items = store.pack_context("explain beta", 3)

  inspect(items.length(), content="3")
  inspect(items[0].source == RepoSummary, content="true")
  inspect(items[1].source == FileSummary("src/beta.mbt"), content="true")
  inspect(items[1].reason, content="name matched query: beta")
  inspect(items[2].source == FileSummary("src/alpha.mbt"), content="true")
  inspect(items[2].reason, content="workspace file summary")
}

///|
test "pack_context ranks full path matches before filename matches" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("src a"))
  let _ = store.set_input(FileText("test/a.mbt"), Text("test a"))

  let items = store.pack_context("debug test/a.mbt and a.mbt", 3)

  inspect(items[1].source == FileSummary("test/a.mbt"), content="true")
  inspect(items[1].reason, content="path matched query: test/a.mbt")
  inspect(items[2].source == FileSummary("src/a.mbt"), content="true")
  inspect(items[2].reason, content="filename matched query: a.mbt")
}

///|
test "pack_context records graph dependencies and invalidates on edits" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.set_input(FileText("b.mbt"), Text("two"))
  let _ = store.pack_context("what changed?", 2)
  let key = CognitionKey::PackedContext("what changed?", 2)
  let deps = store.dependencies_of(key)

  inspect(deps.contains(RepoSummary), content="true")
  inspect(deps.contains(FileSummary("a.mbt")), content="true")
  inspect(deps.contains(FileSummary("b.mbt")), content="true")

  let _ = store.set_input(FileText("a.mbt"), Text("one changed"))
  inspect(store.is_dirty(key), content="true")
  let recomputed = store.recompute_dirty()
  inspect(recomputed.contains(key), content="true")
}

///|
test "pack_context returns immutable item arrays" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))

  let items = store.pack_context("what changed?", 1)
  items.push({
    source: FileText("external.mbt"),
    source_revision: items[0].source_revision,
    payload: "external mutation",
    reason: "external",
  })

  let fresh = store.pack_context("what changed?", 1)
  inspect(fresh.length(), content="1")
  inspect(fresh[0].payload.contains("external mutation"), content="false")
}

///|
test "pack_context with non-positive budget returns no items but stays live" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))

  inspect(store.pack_context("what changed?", 0).length(), content="0")
  inspect(
    store
    .dependencies_of(CognitionKey::PackedContext("what changed?", 0))
    .contains(RepoSummary),
    content="true",
  )
}

///|
test "pack_context_with_budget skips oversized items and preserves query ranking" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/alpha.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/beta.mbt"), Text("beta"))
  let _ = store.set_input(FileText("src/gamma.mbt"), Text("gamma"))

  let items = store.pack_context_with_budget("explain beta", 3, 40)

  inspect(items.length(), content="1")
  inspect(items[0].source == FileSummary("src/beta.mbt"), content="true")
  inspect(items[0].reason, content="name matched query: beta")
}

///|
test "pack_context_with_budget includes more items when budget allows" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/alpha.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/beta.mbt"), Text("beta"))

  let items = store.pack_context_with_budget("explain beta", 3, 1000)

  inspect(items.length(), content="3")
  inspect(items[0].source == RepoSummary, content="true")
  inspect(items[1].source == FileSummary("src/beta.mbt"), content="true")
  inspect(items[2].source == FileSummary("src/alpha.mbt"), content="true")
}

///|
test "pack_context_with_options preserves wrapper behavior" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/alpha.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/beta.mbt"), Text("beta"))

  let by_items = store.pack_context_with_options(
    "explain beta",
    ContextPackOptions::new(max_items=2),
  )
  let by_chars = store.pack_context_with_options(
    "explain beta",
    ContextPackOptions::new(max_items=3, max_chars=40),
  )

  inspect(by_items.length(), content="2")
  inspect(by_items[1].source == FileSummary("src/beta.mbt"), content="true")
  inspect(by_chars.length(), content="1")
  inspect(by_chars[0].source == FileSummary("src/beta.mbt"), content="true")
}

///|
test "pack_context_with_options reuses clean cached context" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let options = ContextPackOptions::new(max_items=2)
  let key = CognitionKey::PackedContext("what changed?", 2)

  let first = store.pack_context_with_options("what changed?", options)
  inspect(first.length(), content="2")
  inspect(store.recompute_count(key), content="1")

  let second = store.pack_context_with_options("what changed?", options)
  inspect(second.length(), content="2")
  inspect(store.recompute_count(key), content="1")

  let _ = store.set_input(FileText("a.mbt"), Text("one changed"))
  let refreshed = store.pack_context_with_options("what changed?", options)
  inspect(refreshed.length(), content="2")
  inspect(store.recompute_count(key), content="2")
}

///|
test "pack_context_with_options truncates oversized selected items when enabled" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/beta.mbt"), Text("beta"))

  let skipped = store.pack_context_with_options(
    "explain beta",
    ContextPackOptions::new(max_items=3, max_chars=10),
  )
  let truncated = store.pack_context_with_options(
    "explain beta",
    ContextPackOptions::new(max_items=3, max_chars=10, truncate_items=true),
  )

  inspect(skipped.length(), content="0")
  inspect(truncated.length(), content="1")
  inspect(truncated[0].source == RepoSummary, content="true")
  inspect(truncated[0].payload.length(), content="10")
  inspect(
    truncated[0].reason,
    content="workspace overview for query: explain beta; truncated",
  )
}

///|
test "pack_context_with_stats reports selected skipped and payload counts" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/alpha.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/beta.mbt"), Text("beta"))

  let (items, stats) = store.pack_context_with_stats(
    "explain beta",
    ContextPackOptions::new(max_items=2),
  )

  inspect(items.length(), content="2")
  inspect(stats.selected_items, content="2")
  inspect(stats.skipped_items, content="1")
  inspect(stats.truncated_items, content="0")
  inspect(
    stats.payload_chars == items[0].payload.length() + items[1].payload.length(),
    content="true",
  )
}

///|
test "pack_context_with_stats reuses computed context items" {
  let reason_calls = Ref::Ref(0)
  let ranker : ContextRanker = {
    score_summary: fn(_query, _key) { 0 },
    reason_summary: fn(_query, _key) {
      reason_calls.val += 1
      "reason call \{reason_calls.val}"
    },
  }
  let store = CognitionStore::new_with_provider_and_ranker(
    CognitionProvider::mock(),
    ranker,
  )
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let key = CognitionKey::PackedContext("what changed?", 2)

  let (items, stats) = store.pack_context_with_stats(
    "what changed?",
    ContextPackOptions::new(max_items=2),
  )

  inspect(reason_calls.val, content="1")
  inspect(items[1].reason, content="reason call 1")
  match store.get_value(key) {
    Some(ContextItems(stored)) =>
      inspect(stored[1].reason == items[1].reason, content="true")
    _ => fail("expected packed context")
  }
  inspect(stats.selected_items, content="2")
  inspect(stats.skipped_items, content="0")
}

///|
test "pack_context_with_stats reports truncation" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/beta.mbt"), Text("beta"))

  let (items, stats) = store.pack_context_with_stats(
    "explain beta",
    ContextPackOptions::new(max_items=3, max_chars=10, truncate_items=true),
  )

  inspect(items.length(), content="1")
  inspect(stats.selected_items, content="1")
  inspect(stats.skipped_items, content="1")
  inspect(stats.truncated_items, content="1")
  inspect(stats.payload_chars, content="10")
}

///|
test "pack_context truncates without splitting unicode characters" {
  let provider : CognitionProvider = {
    file_summary: fn(path, _text) { "\{path}: 😀" },
    repo_summary: fn(items) { items.join("\n") },
  }
  let store = CognitionStore::new_with_provider(provider)
  let _ = store.set_input(FileText("emoji.mbt"), Text("ignored"))

  let (items, stats) = store.pack_context_with_stats(
    "emoji",
    ContextPackOptions::new(max_items=2, max_chars=12, truncate_items=true),
  )

  inspect(items.length(), content="1")
  inspect(items[0].payload, content="emoji.mbt: ")
  inspect(stats.truncated_items, content="1")
  inspect(stats.payload_chars, content="11")
}

///|
test "pack_context does not emit empty truncated items" {
  let provider : CognitionProvider = {
    file_summary: fn(path, _text) { "\{path}: data" },
    repo_summary: fn(_items) { "12345" },
  }
  let store = CognitionStore::new_with_provider(provider)
  let _ = store.set_input(FileText("a.mbt"), Text("ignored"))

  let (items, stats) = store.pack_context_with_stats(
    "what changed?",
    ContextPackOptions::new(max_items=2, max_chars=5, truncate_items=true),
  )

  inspect(items.length(), content="1")
  inspect(items[0].payload, content="12345")
  inspect(stats.selected_items, content="1")
  inspect(stats.truncated_items, content="0")
  inspect(stats.payload_chars, content="5")
}

///|
test "pack_context stats do not infer truncation from ranker reason text" {
  let ranker : ContextRanker = {
    score_summary: fn(_query, _key) { 0 },
    reason_summary: fn(_query, _key) { "contains ; truncated marker" },
  }
  let store = CognitionStore::new_with_provider_and_ranker(
    CognitionProvider::mock(),
    ranker,
  )
  let _ = store.set_input(FileText("a.mbt"), Text("one"))

  let (_items, stats) = store.pack_context_with_stats(
    "what changed?",
    ContextPackOptions::new(max_items=2),
  )

  inspect(stats.truncated_items, content="0")
}

///|
test "pack_context_with_budget with non-positive char budget returns no items but stays live" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("a.mbt"), Text("one"))

  inspect(
    store.pack_context_with_budget("what changed?", 3, 0).length(),
    content="0",
  )
  inspect(
    store
    .dependencies_of(CognitionKey::BudgetedContext("what changed?", 3, 0))
    .contains(RepoSummary),
    content="true",
  )
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
