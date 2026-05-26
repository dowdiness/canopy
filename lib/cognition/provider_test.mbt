///|
test "custom provider controls file and repo summaries" {
  let provider : CognitionProvider = {
    file_summary: fn(path, text) { "custom file \{path}: \{text.length()}" },
    repo_summary: fn(items) { "custom repo: " + items.join(" | ") },
  }
  let store = CognitionStore::new_with_provider(provider)
  let _ = store.set_input(FileText("a.mbt"), Text("one"))

  let _ = store.compute(FileSummary("a.mbt"))
  match store.get_value(FileSummary("a.mbt")) {
    Some(Summary(summary)) => inspect(summary, content="custom file a.mbt: 3")
    _ => fail("expected custom file summary")
  }

  let _ = store.compute(RepoSummary)
  match store.get_value(RepoSummary) {
    Some(Summary(summary)) =>
      inspect(summary, content="custom repo: custom file a.mbt: 3")
    _ => fail("expected custom repo summary")
  }
}

///|
test "provider is called only for recomputed artifacts" {
  let file_calls = Ref(0)
  let repo_calls = Ref(0)
  let provider : CognitionProvider = {
    file_summary: fn(path, text) {
      file_calls.val += 1
      "\{path}: \{text.length()}"
    },
    repo_summary: fn(items) {
      repo_calls.val += 1
      "repo: " + items.join(",")
    },
  }
  let store = CognitionStore::new_with_provider(provider)
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.set_input(FileText("b.mbt"), Text("two"))
  let _ = store.compute(FileSummary("a.mbt"))
  let _ = store.compute(FileSummary("b.mbt"))
  let _ = store.compute(RepoSummary)

  inspect(file_calls.val, content="2")
  inspect(repo_calls.val, content="1")

  let _ = store.set_input(FileText("a.mbt"), Text("one changed"))
  let _ = store.recompute_dirty()

  inspect(file_calls.val, content="3")
  inspect(repo_calls.val, content="2")
  inspect(store.recompute_count(FileSummary("b.mbt")), content="1")
}

///|
test "repo provider receives copied summary arrays" {
  let captured : Array[Array[String]] = []
  let provider : CognitionProvider = {
    file_summary: fn(path, text) { "\{path}: \{text.length()}" },
    repo_summary: fn(items) {
      captured.push(items)
      "repo: " + items.join(",")
    },
  }
  let store = CognitionStore::new_with_provider(provider)
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.compute(RepoSummary)

  captured[0].push("external mutation")

  match store.get_value(RepoSummary) {
    Some(Summary(summary)) =>
      inspect(summary.contains("external mutation"), content="false")
    _ => fail("expected repo summary")
  }
}

///|
test "provider output is copied before storage" {
  let provider_payload : Array[String] = ["first"]
  let provider : CognitionProvider = {
    file_summary: fn(path, _text) { "\{path}: " + provider_payload.join(",") },
    repo_summary: fn(items) { "repo: " + items.join(",") },
  }
  let store = CognitionStore::new_with_provider(provider)
  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  let _ = store.compute(FileSummary("a.mbt"))

  provider_payload.push("external mutation")

  match store.get_value(FileSummary("a.mbt")) {
    Some(Summary(summary)) =>
      inspect(summary.contains("external mutation"), content="false")
    _ => fail("expected file summary")
  }
}
