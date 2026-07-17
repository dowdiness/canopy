# OpenSeek–Canopy integration research (2026-07-16)

**Status:** verified research, not an implementation plan. Concrete APIs and
paths live here rather than in architecture documentation.

**Inspected revisions:**

- Canopy: `43f16244`
- OpenSeek: `b72389a`
- Tau: `6c14f83`

See [Coding Agent Direction](../architecture/coding-agent-direction.md) for the
deferred architecture and activation gates.

## External engine findings

### OpenSeek

The inspected OpenSeek revision provides:

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

OpenSeek is therefore a plausible external engine, but its native process and
filesystem tools still need a host boundary for browser and editor use.

### Tau

Tau is a small Python reference, not a dependency candidate. Its useful lessons
are architectural:

- provider events feed a separate agent event contract;
- its reusable harness excludes terminal and rendering concerns;
- append-only sessions derive replay, branching, and compaction views without
  rewriting history.

## Current Canopy seams

### Cognition

The cognition store (`lib/cognition/store.mbt`) keeps revisioned context,
dependencies, dirty state, and request records deterministic. Provider-neutral
values are defined in `lib/cognition/provider_boundary.mbt`. Their store
operations live in `lib/cognition/provider_boundary_store.mbt`.

The reactive next-action machinery and `ProviderDriverAction` remain private in
`lib/cognition/provider_boundary_reactive.mbt`. Canopy has no public external
driver contract for a coding-agent process.

### Generative UI

`lib/cognition/generative_ui.mbt` already models generation identity, revision,
cancellation, chunk order, validation, dry-run, and stale-result rejection.
`lib/cognition/generative_ui_candidate.mbt` validates untrusted candidate data.
This lifecycle has no user approval step.

`ffi/jsx/generative_ui_adapter.mbt` lowers validated data into typed JSX, while
`ffi/jsx/session.mbt` commits only after dry-run and DOM application succeed.
Generated values do not become event handlers, URLs, expressions, or direct DOM
operations.

This path is suitable for effect-free views. Document changes and other host
effects still need a separate approval boundary.

### Intent and view protocol

- `protocol/user_intent.mbt` carries editor-originated text, structural,
  selection, cursor, undo/redo, and value-commit intents.
- `protocol/view_node.mbt` is the renderer-facing tree.
- `protocol/view_patch.mbt` carries editor output such as node, text,
  decoration, diagnostic, and selection updates.

`ViewPatch` is output, not an authoring format. `UserIntent` also does not yet
model a revision-bound agent proposal with host approval.

### Existing external lowering probe

`codex/lowering.mbt` converts one narrowly constrained unified-diff update into
`UserIntent.TextEdit`.

It accepts one changed line in one hunk only when the old line still matches and
grapheme boundaries are valid. Tests pin stale-diff and UTF-16 boundary
rejection.

This proves that an external change can be lowered through a guarded Canopy
boundary. It is not a generic proposal or commit gateway.

### Workspace coordinator

`workspace/coordinator` manages editor registration, protected reads,
dependencies, and disposal on a shared incremental runtime. It has no stable
`DocumentId`, document registry, proposal revision gateway, or workspace
persistence.

### Lambda rename

`lang/lambda/edits/text_edit_rename.mbt` performs scope-aware rename. It resolves
declarations and references through the scope graph and rejects sibling-name
capture. The operation is Lambda-specific; no language-neutral action facade
currently exposes it.

## OpenSeek integration constraints

### Native engine, portable decoder

The browser can decode OpenSeek events, but it cannot run the native engine and
filesystem tools directly. A browser integration needs a native host or server
bridge.

### Built-ins cannot be restricted

`agent/tool_definition.mbt::build_tools` always adds `shell`, `read`, `edit`,
`multi_edit`, `write`, `remove`, `plan`, `goal`, and `finish`, plus
`shell_output` and `shell_stop` where supported. `extra_tools` only appends.
`serve` has no setting that removes the file-changing built-ins.

### The final registry is not reported

`serve` resolves MCP tools, builds the final registry, and then starts its stdin
reader. It emits no complete list of tools available to the model.
`mcp_tools_registered` reports only MCP discovery and is absent without an MCP
configuration.

Registry reporting can describe today's standard engine before configurable
built-ins exist. Once restrictions exist, the same startup report can verify
them before a prompt is sent.

### Initial correlation can stay narrow

The current `serve` scheduler uses one ordered queue and one active work item.
A single-process, read-only bridge can keep request state in its adapter without
a general replay protocol.

Reconnect, replay, concurrent effects, or commit-capable results would require
stable correlation so duplicate delivery cannot duplicate an effect.

## Candidate first mutation slice

The existing Lambda rename is a plausible first operation because its semantic
checks already live in Canopy. A future plan could use a selected-node rename or
first build a language-owned action facade; this research does not choose.

Either mutation slice still needs infrastructure that Canopy lacks:

- proposal identity and base revision;
- host-issued approval;
- revision recheck at commit;
- proposal, approval, and commit provenance;
- duplicate and cancellation handling;
- CRDT peer-convergence tests.

Stable document identity is not required for one active editor, but it is
required before multi-document proposals.

## Risks and open questions

- **Product priority:** agent integration is deferred while the Personal
  Knowledge Environment is the near-term direction.
- **Retrieval:** the current default cognition ranker is path-oriented;
  projection-aware semantic retrieval remains future work.
- **Structural parameters:** string-valued edit parameters cover rename but not
  every refactoring.
- **Protocol evolution:** additive event decoding is tolerant, but a safe host
  still needs the actual startup tool inventory. General version negotiation
  should wait for a concrete compatibility need.
- **Generative UI:** an agent connection does not bypass the existing product,
  provider, validation, or effect-authority gates.

## Conclusion

OpenSeek can supply the agent loop and session, while Canopy can supply semantic
queries and authoritative commit. The immediate upstream gaps are the inability
to remove file-changing built-ins and the absence of a final tool inventory.
Canopy's larger proposal, approval, and audit boundary remains unimplemented.

Any implementation should first pass the activation gates in
[Coding Agent Direction](../architecture/coding-agent-direction.md) and use an
executable plan with explicit acceptance criteria.
