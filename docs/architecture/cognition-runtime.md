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
reverse-dependency edges. Store-wide revision and dependency-edge snapshots are
backed by the existing `dowdiness/incr` runtime instead of a second incremental
engine. Reverse edges make invalidation cheap: when an input changes, all
transitive dependents can be marked dirty without scanning every artifact.

The current implementation lives in `lib/cognition`; its generated package
interface is the source of truth for concrete API names. Package-level examples
live in `lib/cognition/README.mbt.md` and are checked by `moon test`.

## Mock recomputation rules

The first mock graph has three layers: file text, file-level summaries, and
repo/query context. File-level summaries read one file input. A workspace file
registry tracks active file inputs. Repo context reads summaries for active
files and seeds missing summaries from registered file inputs on its first
build. Query context reads repo context and materializes repo context when
needed. When a new file input appears after repo context already exists, or
after query context has observed repo context, the runtime dirties the
corresponding file-level summary and repo context so repo context can adopt the
new dependency on the next recomputation. Removing a file unregisters it,
removes its file text and summary artifacts, and dirties repo/query context so
the next recomputation excludes the deleted file. Dependency edges that mention
that deleted path are dropped at removal time even though dirty derived values
are not refreshed until recomputation. Paths are keyed by the caller's
exact string for this milestone; for example, `foo.mbt` and `./foo.mbt` are
distinct workspace identities until a separate workspace-root canonicalization
policy exists. Model rename and move operations as removing the old path and
adding the new path with the same contents rather than as identity-preserving
moves.

When an input changes, the store marks transitive dependents dirty. Recomputing
dirty artifacts proceeds only when their dependencies are clean, so unrelated
summaries are not recomputed when another file changes.

Packed context is modeled as another derived artifact. It depends on repo
context plus the selected file-summary candidates, stores provenance-bearing
`ContextItem` values, and keeps each item's source key, source revision,
payload, and inclusion reason. Candidate summaries are selected by deterministic
query/path matching before falling back to path order, then can be constrained by
item count or cumulative payload character budget. Tests can explain why a
context item was included without invoking a model, keeping AI-facing context
inspectable before any real model provider is introduced.

Summary generation and context ranking are routed through deterministic policy
seams. The default provider preserves the mock summary strings, and the default
ranker preserves query/path matching. Tests and future integrations can inject
alternate synchronous providers or rankers without changing graph ownership or
dependency tracking. Policies produce values and scores only; `CognitionStore`
remains the source of truth for revisions, dirty state, dependencies, and
artifact lifetime.

## Provider Boundary

Provider execution is modeled as a boundary around the deterministic graph, not
as graph recomputation. `CognitionStore` may plan provider requests, keep
request/status/result records, and reject stale completions, but it must not own
HTTP clients, credentials, retry loops, timers, or background tasks.

A provider driver should follow this loop:

1. Plan work with `plan_provider_request`.
2. Poll the next action with a driver-supplied wall-clock timestamp.
3. Acknowledge starts and cancellations before launching or stopping external
   work.
4. Complete the request explicitly with the stored descriptor and result.

The driver owns wall-clock time and effect scheduling. Retry waits are derived
from typed provider errors, but the driver supplies the current time when
polling so retryable work can become ready outside tests. Completion remains a
store operation that validates request id, option provenance, source revisions,
and dependency fingerprints before mutating graph artifacts.

The current provider/ranker callbacks remain deterministic policy seams for
mock values and ranking. They are not transport hooks for real providers.

## Non-goals for this milestone

- No real LLM calls.
- No vector database.
- No network sync.
- No CRDT changes.
- No frontend UI.
- No VSCode/Cursor integration.
- No full IDE or agent framework.

## Future artifact shapes

Future cognition artifacts should build on the same graph discipline: explicit
inputs, explicit dependencies, revisions, and selective invalidation before any
expensive AI work is introduced.
