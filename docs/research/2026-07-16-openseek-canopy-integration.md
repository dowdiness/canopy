# OpenSeek–Canopy integration research (2026-07-16)

**Status:** research note — records what was verified and why, not what to build.
This is a "what was verified" record, kept separate from an implementation plan.
It deliberately cites concrete types, fields, and file paths; that is precisely
why it lives in `docs/research/` and not under architecture docs (which are
principles-only).

**Inspected revisions:**
- Canopy: `43f16244`
- OpenSeek: `b72389a`
- Tau: `6c14f83`

**Companion references:**
- [Coding Agent Direction](../architecture/coding-agent-direction.md) — the
  principles-only target architecture and activation gates this research
  informs.

## OpenSeek identity and capabilities

OpenSeek is a MoonBit-native coding agent. The inspected revision (`b72389a`)
reveals:

- **Native engine:** the agent loop, tools, conversation state, and session
  persistence are implemented in MoonBit.
- **Portable protocol decoder:** `openseek_protocol` parses the wire contract
  without depending on the engine and supports browser and native targets.
- **JSONL command/event protocol:** `serve` reads commands from stdin and emits
  typed events on stdout. Durable replay belongs to the separate session store.
- **Typed tool registry:** tools advertise JSON input schemas and return typed
  response or control actions. Built-ins cover file access, shell execution,
  plans, goals, and turn completion.
- **MCP support:** MCP servers can contribute namespaced tools over stdio or
  Streamable HTTP.
- **Append-only sessions:** a header and typed events form the durable log.
  Compaction appends a summary that changes model-context projection while
  preserving covered history.
- **Provider coupling:** the current loop targets DeepSeek and Kimi models.
  OpenSeek owns its concrete model selection and API credentials. A
  provider-neutral abstraction remains future work.
- **License:** Apache-2.0.

## Tau lessons as reference

Tau is a small Python coding agent and teaching project. The inspected revision
(`6c14f83`) demonstrates:

- **Provider and agent event layers:** provider adapters feed one event stream
  into a separate agent event contract.
- **Portable harness:** the reusable harness excludes terminal, rendering, and
  coding-session resource concerns. Frontends consume its event stream.
- **Append-only sessions:** replay, branching, and compaction derive active
  context without rewriting history.
- **Reference only:** Tau is implemented in Python. Canopy should reuse these
  boundaries rather than depend on Tau's implementation.

## Current Canopy seams

### Cognition context and provider boundary

The cognition runtime models an incremental context graph for AI coding
context. The provider boundary separates deterministic graph recomputation from
external provider interaction.

- `lib/cognition/store.mbt` — `CognitionStore` owns revision, dirty state,
  dependencies, and artifact lifetime. It may plan provider requests and keep
  request/status/result records, but it must not own HTTP clients, credentials,
  retry loops, timers, or background tasks.
- `lib/cognition/provider_boundary.mbt` defines provider-neutral request,
  result, status, provenance, and error descriptors.
- `lib/cognition/provider_boundary_store.mbt` exposes planning
  (`plan_provider_request`), cancellation (`cancel_provider_request`),
  completion (`complete_provider_request`), and request/status/result queries
  on `CognitionStore`.
- `lib/cognition/provider_boundary_reactive.mbt` contains the private reactive
  planning graph and `ProviderDriverAction`. Next-action polling is internal,
  not a public driver contract. A real external driver shell remains future
  work.
- `lib/cognition/types.mbt` — context item types with provenance (source key,
  source revision, payload, inclusion reason).

### Generative UI lifecycle and candidate validation

The Generative UI lifecycle manages revision-bound candidate generation,
validation, and commit. The LLM is an untrusted candidate generator; its output
must never mutate the committed UI directly.

- `lib/cognition/generative_ui.mbt` — lifecycle state machine: generation ID,
  revision, cancellation, chunk sequencing, finalization, stale-completion
  rejection. Every candidate is evaluated against an explicit base revision.
  The lifecycle progresses through validation, dry-run, and commit phases
  deterministically; it does not include a user-visible approval step.
- `lib/cognition/generative_ui_candidate.mbt` — syntax, schema, size, and
  host-capability validation for untrusted candidate data. Revision checks,
  dry-run, and commit remain separate lifecycle and session responsibilities.

The current Generative UI path supports internal validation, internal dry-run,
and session commit. A user-visible approval preview is deferred. Effectful
actions and document mutations require the future host-approval boundary.

### JSX candidate projection and session commit

The JSX boundary lowers validated candidates into a typed synthetic projection,
then commits that projection through the existing session dry-run and DOM-apply
path.

- `ffi/jsx/session.mbt` — JSX session state, revision tracking, render planning,
  dry-run, DOM application, recovery, and commit. A candidate is not reported as
  committed unless the session commit succeeds.
- `ffi/jsx/generative_ui_adapter.mbt` — lowering from validated candidate nodes
  to a typed JSX projection. Generated values never become event handlers,
  URLs, expressions, or direct DOM operations.
- `lang/jsx/proj/reconcile.mbt` — reconciliation logic that computes patches
  between projected JSX states.
- `lang/jsx/proj/dry_run.mbt` — pure modeled application of DOM patches before
  the imperative DOM boundary runs.

### UserIntent, ViewNode, and ViewPatch

The protocol layer defines the boundary between Canopy's domain and external
adapters.

- `protocol/user_intent.mbt` — `UserIntent` enum: text edit, structural edit,
  node selection, cursor movement, undo/redo, and node-value commit. These are
  editor-adapter-originated actions: they represent the intent path from a
  frontend or adapter into the editor. Direct FFI paths and language-specific
  edit paths exist alongside this intent enum.
- `protocol/view_node.mbt` — `ViewNode` struct: the UI boundary. New renderers
  should consume protocol output instead of inventing a parallel view tree.
- `protocol/view_patch.mbt` — `ViewPatch` enum: text changes, node replacement
  and child updates, decorations, diagnostics, selection, and full-tree output.
  It is editor output consumed by render adapters, not an authoring input.

### Codex lowering prototype

The Codex lowering prototype demonstrates how an external agent's file changes
can be lowered into `UserIntent` operations and driven into a `SyncEditor`
under the exact (grapheme-boundary-checked) policy.

- `codex/lowering.mbt` — lowers a Codex `FileChange.update` unified diff into
  `UserIntent.TextEdit` operations. The prototype scope is narrow: exactly one
  changed line inside a single hunk, applied only when the document line still
  matches the patch's old text. Multi-hunk diffs, multi-line hunks, and
  concurrent/stale apply are rejected with a clear error.
- `codex/lowering_test.mbt` — tests for grapheme-boundary alignment,
  stale-diff rejection, and exact-boundary policy, including adjacent emoji
  whose UTF-16 encodings share a high surrogate. The earlier Codex research
  note records the separate UTF-8 byte-to-UTF-16 probe.

### Workspace coordinator

The workspace coordinator manages multiple editors on a shared runtime,
enforcing observer discipline and atomic disposal boundaries.

- `workspace/coordinator/types.mbt` — coordinator types: `EditorId`,
  `ProtectedCell`, lifecycle abort kinds and reports, and the coordinator-owned
  registration state.
- `workspace/coordinator/pkg.generated.mbti` — public API: `Coordinator::new`,
  `register_editor`, `destroy_editor`, `read_protected`,
  `register_workspace_cell`, `register_dep`, `unregister_dep`, `runtime`.
- `ffi/json/json_ffi.mbt` — JSON FFI bundle uses the workspace coordinator to
  manage multiple JSON editors on a shared runtime.

The coordinator provides shared incremental-runtime access, protected-cell
lifecycle, and disposal safety. It has no `DocumentId`, document registry,
workspace persistence, multi-document identity, or proposal revision gateway.

### Lambda rename: scope-aware, Lambda-specific

- `lang/lambda/edits/text_edit_rename.mbt` — rename operations are
  scope-graph-aware: they resolve through `@scope.Decl`, use
  `@scope.references(g, decl.id)`, thread the block-local `Decl` straight
  through without round-tripping a root-relative `def_index`, and enforce a
  capture guard against sibling bindings in the same scope. This is
  Lambda-specific; no language-owned action facade generalizes it yet.

### Current explicit gaps

The following infrastructure does not exist today:

- No generic proposal session for agent-authored edits.
- No host-issued approval evidence mechanism.
- No audit ledger recording proposal, approval, and commit provenance.
- No revision-bound commit API for inbound proposals.
- No document workspace with stable `DocumentId` or document registry.

## Observed integration constraints

These constraints follow from the inspected source. They are facts about the
current codebase, not design recommendations.

- **`serve` is native JSONL over stdio.** The serve loop reads JSONL commands
  from stdin and writes JSONL events to stdout (`serve.mbt`). This is a
  native-process contract.
- **Protocol decoder is portable.** `openseek_protocol` parses the wire
  contract without engine dependencies and supports browser targets.
- **Browser needs native or server bridge.** The engine and its process and
  filesystem tools remain native. Browser deployments need a local native host
  or server bridge even though the decoder itself is portable.
- **Standard serve always registers mutation-capable built-ins.** The default
  registry includes workspace-mutating `shell`, `edit`, `multi_edit`, `write`,
  and `remove` tools alongside `read` and the session/control tools `plan`,
  `goal`, and `finish` (`tool_definition.mbt`). No built-in profile or
  host-policy switch disables the workspace-mutating subset for an
  external-editor integration.
- **Protocol and domain separation.** OpenSeek's protocol layer
  (`openseek_protocol`) is independent of its engine, but the engine's tool
  semantics (file writes, shell execution) are not mediated by any Canopy
  domain concept today. An adapter must translate between OpenSeek's tool
  actions and Canopy's proposal and intent contracts.

## Candidate integration blockers

The inspected `serve` path exposes two concrete blockers for a safe subprocess
integration:

- **Built-in write paths cannot be omitted.** A controller cannot currently
  remove `shell`, `edit`, `multi_edit`, `write`, and `remove` while retaining
  the model loop and selected read/control tools.
- **The final registry is not reported.** `serve` resolves MCP tools, builds the
  final registry, and then starts its stdin reader without emitting the names
  available to the model. `mcp_tools_registered` reports only MCP discovery and
  is absent when no MCP configuration is supplied.

Registry reporting can describe the current standard engine before
configurable built-ins exist. Once a restricted registry exists, the same
startup report can verify it before a prompt is sent.

The current `serve` scheduler funnels commands through one ordered queue and
runs one active work item at a time. An initial single-process, read-only bridge
can keep request state in its adapter without a general replay protocol.

Stable cross-process correlation becomes necessary when an implementation adds
reconnect, replay, concurrent effects, or any path whose duplicate result could
commit state.

A later mutation slice also depends on Canopy infrastructure that does not yet
exist: proposal identity, revision checks, host-issued approval, and a commit
gateway. Abstracting OpenSeek's concrete model providers is a separate engine
concern and is not required to test this host boundary.

## Feasibility finding: first vertical slice

The current Lambda rename implementation is scope-graph-aware and
capture-safe, but it is Lambda-specific. No language-owned action facade
generalizes rename across languages.

A first vertical slice could therefore use a **Lambda selected-node rename
proposal**, or it must build a language-owned action facade first. Choosing
between those scopes belongs in a future implementation decision and plan.

Either mutation slice would require infrastructure that does not exist today:

- A generic proposal model that carries proposal identity, base revision, and
  structured edit intent.
- A host-issued approval step that the agent cannot mint itself.
- A revision-checked commit gateway that re-checks the base revision at commit
  time.
- An audit trail recording proposal, approval, and commit provenance.

None of this infrastructure exists today.

The responsibility split and activation gates for this slice are defined in the
[Coding Agent Direction](../architecture/coding-agent-direction.md). This
research note does not authorize implementation.

## Risks and open questions

- **Retrieval gap:** OpenSeek supplies an agent and tools, while Canopy currently
  supplies deterministic context packing with a path-oriented default ranker.
  Projection-derived and semantic retrieval remain future work.
- **Narrow structural parameters:** string-valued structural parameters cover
  rename but not every refactoring shape.
- **Document-qualified identity:** multi-document proposals need stable document
  identity in addition to projection identity. No `DocumentId` exists today.
- **Protocol skew:** the portable decoder tolerates additive events, but a safe
  adapter still needs a startup inventory of the tools actually available to
  the model. General version negotiation should be added only when a concrete
  compatibility boundary requires it.
- **Generative UI value gate:** agent integration does not authorize a live
  provider. A later OpenSeek-driven experiment must retain effect-free host
  capabilities and pass the separate product-value and provider gates;
  effectful actions also need future host approval evidence.

## Disclaimer

This is not an implementation plan. It does not authorize live-provider
production work. It records what was verified and why, and it informs the
principles-only target architecture direction in
[Coding Agent Direction](../architecture/coding-agent-direction.md).

Implementation work should pass the activation gates in the direction document
and should be scoped through an executable plan with clear acceptance criteria.
