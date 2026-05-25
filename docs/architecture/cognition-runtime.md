# Cognition Runtime

This is the first minimal runtime layer for AI-native cognition in Canopy. It is
not an IDE feature yet and does not change the existing editor, CRDT, parser,
projection, or rendering pipeline.

The runtime models an incremental cognition graph:

```text
Workspace inputs → derived cognition artifacts → AI context artifacts
```

The first goal is dependency tracking and selective recomputation for AI coding
context. Quality of generated summaries is deliberately out of scope; current
recomputation uses deterministic mock functions.

## Minimal model

The runtime is intentionally small and separate from the editor pipeline. It
stores named workspace inputs and derived cognition artifacts, records the
revision assigned to each stored artifact, and maintains both dependency and
reverse-dependency edges. Reverse edges make invalidation cheap: when an input
changes, all transitive dependents can be marked dirty without scanning every
artifact.

The current implementation lives in `lib/cognition`; its generated package
interface is the source of truth for concrete API names.

## Mock recomputation rules

The first mock graph has three layers: file text, file-level summaries, and
repo/query context. File-level summaries read one file input. Repo context reads
all known file summaries. Query context reads repo context. When a new file
input appears after repo context already exists, or after query context has
observed repo context, the runtime dirties the corresponding file-level summary
and repo context so repo context can adopt the new dependency on the next
recomputation.

When an input changes, the store marks transitive dependents dirty. Recomputing
dirty artifacts proceeds only when their dependencies are clean, so unrelated
summaries are not recomputed when another file changes.

## Non-goals for this milestone

- No real LLM calls.
- No vector database.
- No network sync.
- No CRDT changes.
- No frontend UI.
- No VSCode/Cursor integration.
- No full IDE or agent framework.

## Future artifact shapes

Future cognition keys may include `SymbolSummary`, `DecisionLog`,
`AgentMemory`, `BranchMemory`, and `StaleMemory`. Those should build on the
same graph discipline: explicit inputs, explicit dependencies, revisions, and
selective invalidation before any expensive AI work is introduced.
