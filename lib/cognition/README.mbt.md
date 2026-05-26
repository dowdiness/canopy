# Cognition Runtime API

`dowdiness/cognition` is a deterministic, incremental graph for AI-facing
workspace context. It tracks file inputs, derived summaries, packed context,
provenance, dependency edges, dirty state, and recompute counts. It does not call
LLMs or the network.

The usual flow is:

1. create a `CognitionStore`,
2. register workspace files with `set_input(FileText(path), Text(contents))`,
3. call a context packing method,
4. inspect returned `ContextItem` provenance and optional `ContextPackStats`.

## Basic context packing

```mbt check
///|
test "README basic context packing" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/alpha.mbt"), Text("let alpha = 1\n"))
  let _ = store.set_input(FileText("src/beta.mbt"), Text("let beta = 2\n"))

  let items = store.pack_context_with_options(
    "explain beta",
    ContextPackOptions::new(max_items=2),
  )

  inspect(items.length(), content="2")
  inspect(items[0].source == RepoSummary, content="true")
  inspect(items[1].source == FileSummary("src/beta.mbt"), content="true")
  inspect(items[1].reason, content="name matched query: beta")
}
```

Each `ContextItem` carries:

- `source` — the cognition artifact selected for context,
- `source_revision` — the revision observed when the item was built,
- `payload` — the text sent to the caller,
- `reason` — deterministic explanation of why it was selected.

## Budgets, truncation, and telemetry

Use `ContextPackOptions` when callers need a stable surface for context limits.
`max_chars` counts cumulative payload characters. By default, oversized items are
skipped; set `truncate_items=true` to include one truncated item when it would
otherwise exceed the remaining budget.

```mbt check
///|
test "README budgeted context packing" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/beta.mbt"), Text("let beta = 2\n"))

  let (items, stats) = store.pack_context_with_stats(
    "explain beta",
    ContextPackOptions::new(max_items=3, max_chars=10, truncate_items=true),
  )

  inspect(items.length(), content="1")
  inspect(items[0].payload.length(), content="10")
  inspect(items[0].reason.contains("; truncated"), content="true")
  inspect(stats.selected_items, content="1")
  inspect(stats.truncated_items, content="1")
  inspect(stats.payload_chars, content="10")
}
```

Telemetry is deterministic and derived from the same candidate list as the
returned items:

- `selected_items` — number of returned items,
- `skipped_items` — candidates not returned,
- `truncated_items` — returned items whose reason includes `; truncated`,
- `payload_chars` — total returned payload length.

## Custom deterministic policies

`CognitionProvider` controls summary text. `ContextRanker` controls candidate
ordering and reasons. Both are synchronous deterministic policy seams; the store
still owns graph state, revisions, dirty propagation, dependency edges, and
artifact lifetime.

```mbt check
///|
test "README custom provider and ranker" {
  let provider : CognitionProvider = {
    file_summary: fn(path, text) { "summary \{path}: \{text.length()}" },
    repo_summary: fn(items) { "repo => " + items.join(" | ") },
  }
  let ranker : ContextRanker = {
    score_summary: fn(_query, key) {
      match key {
        FileSummary("src/gamma.mbt") => 10
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
  let store = CognitionStore::new_with_provider_and_ranker(provider, ranker)
  let _ = store.set_input(FileText("src/beta.mbt"), Text("beta"))
  let _ = store.set_input(FileText("src/gamma.mbt"), Text("gamma"))

  let items = store.pack_context("explain beta", 3)

  inspect(items[1].source == FileSummary("src/gamma.mbt"), content="true")
  inspect(items[1].reason, content="custom preferred gamma")
}
```

## Compatibility helpers

For simple callers, these wrappers remain available:

- `pack_context(query, max_items)` — item-count budget only,
- `pack_context_with_budget(query, max_items, max_chars)` — item-count plus
  character budget,
- `pack_context_with_options(query, options)` — explicit options,
- `pack_context_with_stats(query, options)` — explicit options plus telemetry.
