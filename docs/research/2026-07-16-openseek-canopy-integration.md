# OpenSeek–Canopy integration research (2026-07-16)

**Status:** verified research, not an implementation plan. Concrete APIs and
paths live here rather than in architecture documentation.

**Inspected revisions:**

- Canopy: `43f16244`
- OpenSeek: `b72389a`
- Tau: `6c14f83`

See [Coding Agent Direction](../architecture/coding-agent-direction.md) for the
deferred architecture and activation gates.

## What the investigation needed to establish

OpenSeek already supplies the expensive outer machinery of a coding agent: a
model loop, tools, conversations, and sessions. The unresolved part was whether
Canopy could reuse that machinery without creating a second writer for the same
document.

The answer split in two. OpenSeek has a suitable process and protocol boundary,
and Canopy already has several validation seams. But OpenSeek's default tools
can write around those seams, while Canopy has no proposal and approval gateway
to receive the result safely.

## OpenSeek has the right outer shape

The inspected revision provides:

- a MoonBit agent loop, tool registry, conversation state, and session store;
- a native `serve` command that reads JSONL commands from stdin and emits typed
  events on stdout;
- a portable `openseek_protocol` decoder for native, JavaScript, and WebAssembly
  clients;
- built-in file, shell, plan, goal, and completion tools;
- MCP tools over stdio or Streamable HTTP;
- append-only sessions whose compaction changes model-context projection without
  deleting covered history;
- concrete DeepSeek and Kimi model support, with credentials owned by OpenSeek;
- Apache-2.0 licensing.

The portable decoder initially suggests a direct browser integration. That
portability stops at the wire: the engine and its filesystem tools remain a
native process. A browser still needs a native host or server bridge.

Tau reaches a similar boundary from Python. Its reusable harness separates
provider events from agent events and excludes terminal and rendering concerns.
Its append-only sessions derive replay, branching, and compaction views without
rewriting history. Tau is useful here as a design comparison, not a dependency.

## Canopy already has validation seams

Canopy is not starting from an untyped model response. It already validates
revisioned context, generated UI candidates, editor intents, and one narrow
external diff. None of those seams, however, combines proposal identity, user
approval, and collaborative commit.

### Cognition tracks requests without running an agent

The cognition store (`lib/cognition/store.mbt`) keeps revisioned context,
dependencies, dirty state, and request records deterministic. Provider-neutral
values are defined in `lib/cognition/provider_boundary.mbt`; their store
operations live in `lib/cognition/provider_boundary_store.mbt`.

The reactive next-action machinery and `ProviderDriverAction` remain private in
`lib/cognition/provider_boundary_reactive.mbt`. This is a planning seam, not a
public driver contract for a coding-agent process.

### Generative UI distrusts generated data

`lib/cognition/generative_ui.mbt` already tracks generation identity, revision,
cancellation, chunk order, validation, dry-run, and stale results.
`lib/cognition/generative_ui_candidate.mbt` validates untrusted candidate data.

The JSX path goes further. `ffi/jsx/generative_ui_adapter.mbt` lowers validated
data into typed JSX, and `ffi/jsx/session.mbt` commits only after dry-run and DOM
application succeed. Generated values do not become event handlers, URLs,
expressions, or direct DOM operations.

That is enough for effect-free views. It does not answer who may approve a
document change, because the current lifecycle has no user approval step.

### Intent and view types point in opposite directions

`protocol/user_intent.mbt` carries editor-originated edits and navigation into
Canopy. `protocol/view_node.mbt` and `protocol/view_patch.mbt` carry projected
state back to renderers.

A tempting shortcut would be to accept a `ViewPatch` from the agent. That would
reverse the boundary: patches describe what Canopy decided to render, not what
an external participant may author. `UserIntent` is closer, but it still lacks
a base revision, proposal identity, and host approval.

### One external edit is already lowered safely

`codex/lowering.mbt` converts one constrained unified-diff update into
`UserIntent.TextEdit`.

It accepts one changed line in one hunk only when the old line still matches and
grapheme boundaries are valid. Tests pin stale-diff and UTF-16 boundary
rejection.

The probe shows that an external change can pass through a guarded Canopy
boundary. Its narrowness also exposes what is missing: it is neither a generic
proposal nor a revision-checked commit gateway.

### Workspace and rename cover different halves

`workspace/coordinator` manages editor registration, protected reads,
dependencies, and disposal on a shared incremental runtime. It does not provide
stable document identity, a document registry, or proposal revisions.

`lang/lambda/edits/text_edit_rename.mbt` supplies the semantic half of one useful
operation. It resolves declarations and references through the scope graph and
rejects sibling-name capture. The operation is Lambda-specific, with no
language-neutral action facade.

## The stock `serve` boundary fails in two concrete places

### More tools can be added, but built-ins cannot be removed

`agent/tool_definition.mbt::build_tools` always adds `shell`, `read`, `edit`,
`multi_edit`, `write`, `remove`, `plan`, `goal`, and `finish`, plus
`shell_output` and `shell_stop` where supported. `extra_tools` only appends.

An embedded caller can instead pass a custom `Tools` registry to
`run_turn_in_scope`. A separate `serve` client cannot inject that registry, which
is the boundary evaluated here. Its model would still have `shell`, `edit`, and
`write` paths around Canopy's validation flow.

### MCP reporting is not a final tool inventory

`serve` resolves MCP tools, builds the final registry, and then starts its stdin
reader. `mcp_tools_registered` reports only MCP discovery and is absent without
an MCP configuration. No event reports every tool available to the model.

The distinction matters before the first prompt. Once a turn starts, the model
may call an unexpected write-capable tool immediately. A host that intends to
fail closed must inspect the final registry first.

These two changes can land independently. Registry reporting can describe the
current engine before configurable built-ins exist; later it can verify that a
restricted registry was actually built.

### Correlation is narrower than it first appears

The protocol has no general request identity for reconnect and replay. That
sounds like the next blocker, but the current `serve` scheduler uses one ordered
queue and one active work item. A single-process, read-only bridge can keep its
request state in the adapter because it has no effect to replay.

The requirement changes as soon as results can commit. Reconnect, replay,
concurrent effects, or duplicate delivery then need stable identity so one
approval cannot become two commits.

## A Lambda rename could test the missing half

Lambda rename is a plausible first mutation because Canopy already owns its
scope and capture checks. The agent could request the operation without
reimplementing those semantics.

The remaining gap is not rename logic. Before the operation can reach a live
document, Canopy still needs:

- proposal identity and base revision;
- host-issued approval;
- revision recheck at commit;
- proposal, approval, and commit provenance;
- duplicate and cancellation handling;
- CRDT peer-convergence tests.

A future plan may choose selected-node rename or build a language-owned action
facade first. Stable document identity can wait for multi-document work, but the
items above cannot be skipped for one active editor.

## Risks that remain open

- **Product priority:** agent integration is deferred while the Personal
  Knowledge Environment is the near-term direction.
- **Retrieval:** the default cognition ranker is path-oriented; projection-aware
  semantic retrieval remains future work.
- **Structural parameters:** string-valued edit parameters cover rename but not
  every refactoring.
- **Protocol evolution:** additive event decoding is tolerant, but a safe host
  still needs the actual startup tool inventory. General version negotiation
  should wait for a concrete compatibility need.
- **Generative UI:** an agent connection does not bypass product, provider,
  validation, or effect-authority gates.

## Conclusion

OpenSeek can supply the agent loop and session. Canopy can supply semantic
queries and authoritative commit.

The stock `serve` path is not safe for this integration yet: it cannot omit its
file-changing built-ins or report its final registry, and Canopy cannot turn an
approved proposal into an idempotent collaborative commit.

Those gaps define a bounded future experiment rather than a new product
priority. Any implementation should first pass the activation gates in
[Coding Agent Direction](../architecture/coding-agent-direction.md) and use an
executable plan with explicit acceptance criteria.
