# S3 Lang Runtime Extraction Plan

## Scope and non-goals

S3 extracts shared Tier-2 companion mechanics into `lang/runtime` while preserving all Tier-1 editor sync surfaces and S2 shipped interfaces (`sync_session/`, `transport_ws/`, `editor` sync surfaces, and deprecated `sync_protocol.mbt`).

This plan is execution-only; it does not redesign architecture.

Non-goals:
- No `ffi/host` extraction (reserved for S4).
- No edits to `ffi` consumer behavior contract beyond adding migration-safe delegation.
- No transport/sync session rewiring.

Cross-cutting constraints:
- Respect MoonBit cross-package rules: enum constructors are package-owned, methods are package-defined, and `using` scopes are file-local.
- Preserve `SyncEditor` text API bounds (`fn[T : Eq]`) by keeping capability-record construction in language packages where concrete `T` is known.
- Keep closure-record runtime API unbounded on `T`, with dispatch performed through concrete builders.
- Keep all manifests in `moon.pkg` brace syntax; avoid editing JSON manifest format.
- Every changed step must include a compile-breakpoint point and the fix that resolves it.
- Per step run `NEW_MOON_MOD=0 moon info` and inspect `git diff '*.mbti'` for visibility/trait-bound drift.
- Do not widen visibility unless required by the final API contract.
- Add deprecated compatibility symbols for moved public symbols with at least one release window.

Benchmark rule from this stage: direct-call/hot-path split is not required; keep unified closure-record dispatch and retain existing dispatch benchmark file under `lang/json/companion/` for continuity.

The language migration order is fixed as: first `json`, then `markdown`, then `lambda` (because `lambda` has optional/extra capabilities and the protocol is intentionally broader).

---

## Step 1 — Introduce `lang/runtime` shared companion layer

### What this step does
- Create a new `lang/runtime` package with shared companion types and helper functions for:
  - companion editor constructor protocol
  - tree-edit application protocol
  - memo attachment + projection protocol
  - message-normalized structural edit plumbing
- Define a runtime record type that represents only shared responsibilities and is reusable by all languages.
- Keep `lambda`’s richer behavior as optional protocol slots:
  - optional `eval` hooks
  - optional `scope` hooks
  - optional `semantic` hooks
  - unsupported paths must return an explicit, user-visible unsupported message rather than diverging behavior.
- Define the shared message/error contract once in `lang/runtime` and preserve existing message strings where externally observed.

### Invariants maintained
- No changes to text pipeline hot-path inside `editor/sync_editor_text.mbt`.
- `handle_text_intent` still funnels through existing `SyncEditor.apply_span_edits` semantics and `FocusHint` ordering.
- `lang/*/companion` package API behavior remains externally equivalent behind deprecations during transition.

### Compile breakpoint + fix
- Expected break: existing language companions import helpers now moved into `lang/runtime`, creating unresolved symbol errors in `lang/json/companion`, `lang/markdown/companion`, and `lang/lambda/companion`.
- Fix in same step: create temporary public facades in `lang/runtime` with the old-facing names imported by language companions, then migrate each language in later steps.

### Verification gates for this step
- `NEW_MOON_MOD=0 moon check` for touched package graph.
- `NEW_MOON_MOD=0 moon info` + `git diff '*.mbti'` with explicit signoff that no breaking signature widening/regressions were introduced.
- A focused build of `lang/runtime` only (plus its direct deps), then targeted probe import smoke in a tiny caller to ensure package compiles under cross-package module boundaries.

---

## Step 2 — Migrate JSON companion flow into `lang/runtime`

### Why first: grounding choice
JSON is the clearest non-lambda reference shape: the companion surface is compact, editor construction and memo attachment are already separable, and round-trip intent tests are already message-oriented. It grounds shared abstractions with the least protocol ambiguity.

### What this step does
- Move shared logic from `lang/json/companion` into `lang/runtime` while leaving JSON-specific parser and AST transforms in `lang/json`.
- In `lang/runtime`, implement JSON’s migration by a language-specific constructor callback that supplies:
  - parser + editor initialization
  - memo-build policy
  - `apply_json_edit` bridge implementation
- Preserve exact `new_json_editor` semantics and `apply_json_edit` external messages during transition:
  - keep compatibility aliases in `lang/json` entrypoints that delegate to runtime APIs.
- Maintain the `json` companion’s benchmark and intent test harness by keeping their module-facing function names stable.

### Invariants maintained
- Parse/op-to-span semantics remain structurally identical (including operation matching order, span emission sequence, and cursor/focus hint handling).
- Memo attachment output remains isomorphic by value and ordering so existing consumers are not order-sensitive.
- Existing JSON error and diagnostic message text remains unchanged for externally asserted paths.

### Compile breakpoint + fix
- Breakpoint A: direct calls from `ffi/json` and tests expecting `new_json_editor` / `apply_json_edit` paths in `lang/json`/`lang/json/companion` fail after extraction.
- Fix: re-export deprecated aliases in `lang/json/top.mbt` and `lang/json/companion` (or whichever module currently owns public symbols) that forward to runtime entrypoints with no behavior change.
- Breakpoint B: any moved helper relying on package-local `using` imports loses scope after move.
- Fix: move helper imports explicitly into each moved file and make runtime modules import modules directly.

### Verification gates (JSON)
- JSON snapshot tests: run package wbtests and assert serialized snapshots still match expected corpus.
- Round-trip edit wbtests: run JSON edit integration tests with explicit message assertions (not only success), verifying both successful and error paths.
- Differential tests: compare old vs runtime-mediated outputs on the same edit stream with non-vacuity assertions (i.e., ensure emitted document/projection/focus actually change where expected and that no silent no-op regression is accepted).
- Workspace/probe integration: run `workspace/probe` tests that exercise JSON sessions, including identity and runtime-safety probes.
- Project commands in addition to checks: `NEW_MOON_MOD=0 moon check`, `NEW_MOON_MOD=0 moon test`, plus `NEW_MOON_MOD=0 moon info` with `git diff '*.mbti'`.

---

## Step 3 — Migrate markdown companion flow into `lang/runtime`

### What this step does
- Migrate `lang/markdown/companion` through runtime primitives exactly as in JSON, preserving markdown parser and fold shapes.
- Preserve existing markdown integration wbtest names and snapshots by keeping public-facing symbols stable through deprecated forwarding aliases.
- Normalize message-producing branches so they route through the runtime-defined message envelope.

### Invariants maintained
- The markdown fold-to-edit path remains stable across span compute and editor application.
- Message ordering and focus reconciliation order are preserved.
- Existing markdown-specific behavior remains in `lang/markdown` modules and only shared orchestration moves.

### Compile breakpoint + fix
- Breakpoint: markdown companion symbols referenced by `ffi/markdown` and markdown examples resolve to symbols still in old package locations.
- Fix: install temporary compatibility shims in `lang/markdown/top.mbt` (and/or companion module if needed) that delegate to runtime, then remove after second-step transition complete.
- Breakpoint: enum-boundary issues if any markdown AST enum was indirectly constructed in moved helper code.
- Fix: keep enum constructors and constructors’ owning module unchanged; move only orchestration paths.

### Verification gates (Markdown)
- Snapshot tests in markdown companion/test files must still match.
- Round-trip edit wbtests with explicit message assertions on both parse-and-apply and reconciliation output.
- Differential non-vacuity tests between pre/post migration markdown edit outputs and message vectors.
- Workspace/probe integration for markdown scenarios.
- `NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test` on touched set.

---

## Step 4 — Migrate lambda companion flow and optional capabilities

> **AMENDED 2026-06-12 (grounding outcome — supersedes the step as written
> below).** Lambda does NOT migrate onto `LanguageSpec`. PR3 grounding built
> the responsibility map and restated lambda in the spec's vocabulary; the
> apply path failed every condition for raising it into the SPI:
>
> 1. At the time, `compute_text_edit` required
>    `EditContext{source_text, source_map, registry, module_projection}` — not
>    the spec's `(Op, String, ProjNode[T], SourceMap)`; widening would have
>    forced dead context on json/markdown. The post-`ModuleProjection` #634
>    audit narrowed this point: Lambda's registry and `DefinitionIndex` are now
>    derivable from the generic `ProjNode` root, so context alone is no longer
>    the deciding blocker.
> 2. `apply_lambda_tree_edit` returns `Result[Array[SpanEdit],
>    TreeEditError]` — a typed public error surface plus a patch trace
>    consumed by `ffi/lambda` (intent.mbt, semantic.mbt) via the
>    `@lang_lambda` facade; flattening to `Result[Unit, String]` breaks
>    consumers.
> 3. `Drop` delegates to `editor.move_node`, an editor-owned operation
>    (placeholder/separator handling) — editor coupling the SPI deliberately
>    excludes (framework generality = what it excludes).
> 4. The proposal's "lambda extras as optional capability fields" is ALREADY
>    satisfied by per-instance `LanguageCapabilities` (all fields optional,
>    `None` = explicit unsupported).
>
> Codex adversarial review (2026-06-12): "Cannot refute — the exception
> looks like a real boundary, not laziness", with the additional
> verification that S4 ffi/host extraction is not blocked (ffi already
> consumes the bridge through the facade).
>
> **Revisit trigger (updated by #634):** raise `apply_edit` into the spec only
> if a future non-Lambda language needs the same richer application contract —
> typed edit errors, successful `SpanEdit` traces, or editor-owned move/drop
> semantics — and the resulting API would serve at least two languages without
> dead config in any of them.
>
> PR3 therefore ships: this decision record, the ADDING_A_LANGUAGE.md
> template update (LanguageSpec is the path for new languages; lambda
> documented as the exception), and the lang/runtime README boundary note.
> Steps 4's original migration prose and Step 5's "one runtime-mediated
> implementation path per language" goal are void for lambda.

### What this step does
- Migrate `lang/lambda/companion` orchestration into `lang/runtime` by adapting the complex lambda companion shape onto the generic runtime dispatch.
- Keep lambda-specific extra fields in the runtime capability record as optional (eval/scope/semantic). Unsupported paths return explicit errors and preserve external message text.
- Preserve `lang/lambda/top.mbt` public contracts and companion exports during migration via deprecations.
- Keep lambda benchmark behavior unchanged and retain current benchmark files.

### Invariants maintained
- Existing lambda parse-tree edit application shape and focus behavior remain unchanged where supported.
- Unsupported optional capability requests do not panic or crash; they fail with deterministic, tested messages.
- Existing direct-language semantic overlays remain package-owned; runtime only calls into them through callbacks.
- No hot-path behavior split is introduced; still unified closure-record dispatch.

### Compile breakpoint + fix
- Breakpoint A: `lang/lambda/companion` currently returns tuple-shaped data used by several callsites; moving orchestration may change construction type if callbacks are flattened.
- Fix: keep lambda-specific public facade signatures unchanged by preserving lambda-specific return adapters in `lang/lambda/top.mbt` and forwarding to runtime internals.
- Breakpoint B: `fn[T]` unbounded closure record fields conflict with `SyncEditor` text method expectations.
- Fix: keep `T : Eq` constraints in constructor/builder closures inside `lang/lambda` and `lang/json`/`markdown` language packages; runtime record remains unbounded and stores already-instantiated closures.

### Verification gates (Lambda)
- Snapshot tests for lambda companion and overlay-related suites.
- Round-trip edit wbtests with assertions on message text and message shape (including unsupported optional capability branches).
- Differential tests for successful edits and expected-failure branches with non-vacuity assertions.
- Probe/identity integration tests over lambda sample sessions.
- `NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test` on touched set, and `git diff '*.mbti'` review for accidental API leakage.

---

## Step 5 — Consolidate runtime API, deprecations, and proof of migration completeness

### What this step does
- Finalize `lang/runtime` API into public contract intended for S3 only, ensuring each `lang/*` package has one compatibility surface and one runtime-mediated implementation path.
- Remove temporary internal duplicate helper code that became dead after migration.
- Add/update migration notes and add/adjust the `docs/development/ADDING_A_LANGUAGE.md` references that were made stale by this extraction.
- Ensure ffi consumers remain source-compatible without requiring `lang/runtime` awareness.

### Invariants maintained
- Every moved public symbol still callable via deprecated alias until at least one release cycle.
- No API obligations from the Tier-2 boundary are relaxed.
- Package-level ownership invariants: constructors remain where owning enum/type originally lives.

### Compile breakpoint + fix
- Breakpoint: stale temporary aliases or duplicate exports creating ambiguous import paths across runtime/language modules.
- Fix: run package-by-package compile to find collisions, then keep exactly one canonical symbol path and one explicit deprecated forwarder path.

### Verification gates
- Per-step invariants sweep:
  - `NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test`.
  - `NEW_MOON_MOD=0 moon info` with `git diff '*.mbti'` review.
  - Snapshot + message-asserted wbtests for all three languages in one pass.
  - differential + non-vacuity tests for all three in aggregate.
  - workspace/probe package integration across language sessions.
- JS-facing example readiness check:
  - build JS artifacts before any web/example test gates as required by repo convention.
  - ensure web/demo examples run with existing external JS entrypoints.

---

## PR slicing and merge gating

Proposed slice:
- PR1: `lang/runtime` package + `json` migration.
- PR2: `markdown` migration using `lang/runtime`.
- PR3: `lambda` migration with optional capability fields.

For each PR:
- keep workspace green before handoff with `NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test`.
- keep example apps operational (`moon build --target js` precondition where app suites depend on JS artifacts).
- keep temporary compatibility aliases for moved public symbols.
- do not touch S2 surfaces; explicitly validate no changes in `sync_session/`, `transport_ws/`, editor sync shims.
