///|
test "custom ranker controls packed context order and reasons" {
  let ranker : ContextRanker = {
    score_summary: fn(_query, key) {
      match key {
        FileSummary("src/gamma.mbt") => 1000
        FileSummary(_) => 0
        _ => 0
      }
    },
    reason_summary: fn(_query, key) {
      match key {
        FileSummary("src/gamma.mbt") => "custom preferred gamma"
        FileSummary(path) => "custom fallback \{path}"
        _ => "custom artifact"
      }
    },
  }
  let store = CognitionStore::new_with_provider_and_ranker(
    CognitionProvider::mock(),
    ranker,
  )
  let _ = store.set_input(FileText("src/beta.mbt"), Text("beta"))
  let _ = store.set_input(FileText("src/gamma.mbt"), Text("gamma"))

  let items = store.pack_context("explain beta", 3)

  inspect(items[1].source == FileSummary("src/gamma.mbt"), content="true")
  inspect(items[1].reason, content="custom preferred gamma")
  inspect(items[2].source == FileSummary("src/beta.mbt"), content="true")
  inspect(items[2].reason, content="custom fallback src/beta.mbt")
}
