# Observer discipline contract: editor memo rooting on a shared `@incr.Runtime`

**Date:** 2026-05-23
**Status:** Design draft (prose-only, pre-Codex-review)
**Post-#633 note (2026-06-14):** references to Lambda flat-projection companion cells (`proj_memo`, `get_flat_proj`) are superseded; Lambda's editor-facing projection cells are now the generic cached projection, registry, and source-map memos.
**Builds on:** `docs/research/2026-05-23-runtime-safety-decision.md` §"Named follow-ups" #2
**Belongs to slice:** §P0b of `docs/research/2026-05-22-spec-aware-workspace.md`

---

## 1. Purpose

Gate #1 confirmed that a single shared `@incr.Runtime` across editors is mechanically viable (`docs/research/2026-05-23-runtime-safety-decision.md` §C) and identified three contracts the editor stack must satisfy before such sharing is safe in production. This document specifies the second contract — editor-side Observer discipline.

It decides:

- **What** subset of each editor's reactive cells must be explicitly rooted.
- **Who** owns the roots.
- **When** they are created and disposed.
- **What** failure modes the contract prevents, and **how** tests verify it.

It does **not** decide:

- The shape of the workspace-side `on_change` multiplexer (follow-up #1).
- The signature of `new_*_editor(runtime=shared)` ctor variants (follow-up #3).
- Whether the workspace gc cadence is timer-driven, edit-driven, or coordinator-driven.
- The cross-runtime bridge design (path (ii) — not selected).

These adjacent contracts can land in any order, but they all assume this one.

---

## 2. Why discipline is required (background)

Every `new_*_editor` constructor today builds a fresh `@incr.Runtime::new()` per editor (`lang/lambda/companion/lambda_editor.mbt:107-113`; `lang/markdown/companion/markdown_companion.mbt:7-16`). The editor handle holds the only reference. When the FFI consumer drops the handle and `destroy_editor` runs (`ffi/lambda/lifecycle.mbt:88-101`), the runtime and all its cells become GC-collectable as a unit. The runtime itself is the unit of lifetime, so fine-grained rooting is unnecessary.

A shared workspace runtime collapses that unit. Many editors share one runtime, and `Runtime::gc()` (`loom/incr/cells/internal/kernel/gc.mbt:113-128`) collects every `Interior` cell unreachable from a `Root` cell. Memos default to `gc_role = Interior` (`loom/incr/cells/internal/pull/memo_data.mbt:46-48`). Gate #1 §B confirmed that without roots, every Memo in the runtime is collected on the next `gc()`.

The editor handle no longer keeps its reactive surface alive under shared-runtime semantics. Something must explicitly root it. This contract is that something.

---

## 3. The core invariant

> **For every Memo that an editor's public API reads via `parser.runtime().read(...)`, the editor must own a live `Observer` on that Memo (or on a downstream Memo whose `gc_dependencies` BFS transitively pins it) for the entire interval between editor construction and `destroy_editor`.**

"Owns" means: the Observer's lifetime is bound to the editor instance such that disposing the editor disposes the Observer, and nothing else can dispose it earlier.

The invariant is one-sided: it does *not* require every Memo inside the editor to be rooted — only the ones the public API exposes. Internal-only Memos that are read solely as transitive dependencies of an externally-exposed Memo are pinned automatically by the BFS in `loom/incr/cells/internal/kernel/gc.mbt:63-87` (gate #1 §C verified this).

---

## 4. Enumerating the externally-exposed surface

The set of Memos that must be rooted per editor is exactly the set read by methods on `SyncEditor[T]` and its companion. As of 2026-05-23:

**Generic (every editor):**
- `SyncEditor::get_proj_node` reads `cached_proj_node` (`editor/sync_editor.mbt:293-295`).
- `SyncEditor::get_source_map` reads `source_map_memo` (`editor/sync_editor.mbt:299-301`).
- `SyncEditor::get_registry` reads `registry_memo` (`editor/sync_editor.mbt:306-310`).
- `SyncEditor::get_tree` reads `parser.ast()` (`editor/sync_editor.mbt:318-320`).
- `SyncEditor::get_errors` reads `parser.diagnostics()` for non-empty documents, and `SyncEditor::is_parse_valid` delegates to `get_errors` (`editor/sync_editor_parser.mbt:107-115`).
- `SyncEditor::get_node` and `SyncEditor::node_at_position` read `registry_memo` and `source_map_memo` (`editor/sync_editor.mbt:327`, `:340`, `:348`).

**Lambda-specific (companion):**
- #633 removed the companion-owned flat projection cell from the editor-facing
  surface; generic projection reads now go through `SyncEditor`'s cached
  projection, registry, and source-map memos.
- `LambdaCompanion::get_eval_results` reads `escalation_memo`.

**Other languages (Markdown, JSON):** the same generic projection cells (`cached_proj_node`, `registry_memo`, `source_map_memo`), the parser diagnostics cell, plus any language-specific companion memos to be enumerated when that language ships on shared runtime.

**Bridge-layer (workspace-facing):** `parser.source()` (`Memo[String]`) is not read by `SyncEditor` directly today but is the natural workspace-side input for cross-editor text dependencies (gate #1 §C probed exactly this). It must be rooted whenever the editor is constructed on a shared runtime — even though no current public API reads it — because workspace Memos will.

The contract's enforcement target is the constructor: `new_lambda_editor`, `new_markdown_editor`, `new_json_editor` (and any future `new_*_editor`) must, when given a shared runtime, install and own one Observer per Memo in this set.

---

## 5. Ownership: the editor scope

The natural primitive is `@incr.Scope`. `Scope::add_observer` (`loom/incr/cells/scope.mbt:268-281`) already exists and ties Observer disposal to scope disposal in dispose-hook order (step 2 of disposal — after children, before owned cells), which matches the lifetime requirement here.

The contract specifies:

- Each `SyncEditor[T]` owns a `Scope` field (call it `lifetime_scope`).
- The constructor, after building all Memos, calls `scope.add_observer(memo.observe())` for each Memo in the externally-exposed set.
- `destroy_editor` (`ffi/lambda/lifecycle.mbt:88-101` and equivalents) disposes `lifetime_scope`. One new line per FFI lifecycle module.
- Each editor gets its own `Scope`; multiple editors on one shared runtime have independent scopes.

The contract does **not** specify that the editor must store the `Observer` handles directly. `Scope::add_observer` returns the Observer for immediate use (`scope.mbt:280`), so if a future call site needs the Observer's `.get()` it can keep it; otherwise the scope-owned reference is enough.

---

## 6. Workspace-level corollaries

Two corollaries on the workspace side of the boundary:

**Corollary A — workspace Memos transitively root editor Memos, but the editor still needs its own Observer.** Gate #1 §C confirmed that a workspace Memo with its own Observer transitively pins its input cone. That only holds *while the workspace Memo exists and is observed*. Before the first workspace-Memo construction, and after a workspace Memo is torn down but before its editor is destroyed, only the editor's own Observers prevent collection. Without them, a `gc()` during either interval (or a later stop-the-world coordinator gc that targets cells outside the current dep-graph) would wipe the editor's surface.

**Corollary B — the coordinator must tear down its dep-graph entries for an editor before, or atomically with, `destroy_editor`.** When `destroy_editor` disposes `lifetime_scope`, the editor's own Observers vanish. Any coordinator Memo still reading the destroyed editor's Memos keeps them alive (BFS through that Memo's Observer), but the next read returns stale data — a logical bug. The coordinator must drop its dep-graph entries (and the Observers rooting them) for editor E before `destroy_editor(E)` returns. The ordering protocol itself is out of scope here but must be specified before any coordinator code lands.

---

## 7. Failure modes the contract prevents

Each failure mode is the answer to "what happens if the invariant is violated in this specific way?":

1. **Forgotten Observer on construction.** Editor is built, no Observer installed. Workspace `gc()` runs at any time → Memo collected → next `SyncEditor::get_proj_node` (or equivalent) hits a disposed cell. The disposed-cell behavior in `Runtime::read` aborts (`cell_info` returns `None`, `runtime.mbt:300-314`). Symptom: editor appears to work, then aborts on the first read after the first workspace gc. Heisenbug if gc cadence is non-deterministic.

2. **Observer disposed early.** Editor still alive, `lifetime_scope` disposed early (e.g. via a buggy partial-teardown path). Same symptom as (1), but timing tracks the buggy code path rather than gc cadence — easier to attribute, provided you already suspect the disposal path.

3. **Observer leaked past destroy_editor.** `lifetime_scope` not disposed on destroy_editor. Memos pinned indefinitely; runtime grows monotonically as editors are created and destroyed. No correctness symptom; pure resource leak. Surfaces under stress (many editor cycles) or in long-lived workspaces.

4. **Workspace dep-graph reads a destroyed editor's Memo.** Corollary B violated. Workspace Memo still observed → editor Memos still pinned via BFS → reads succeed but return the editor's last-known state forever. Silently-stale data; the worst kind of failure because there's no abort and no obvious symptom until a user notices their cross-editor query is showing data from a closed file.

5. **Externally-exposed Memo added without contract update.** A future `SyncEditor::get_thing()` method exposes a new Memo that the constructor doesn't observe. Failure mode (1) for that one Memo. Mitigation: lint / convention enforcement (out of scope here, see §10).

---

## 8. Tests that pin the invariant

The tests live in `editor/`, `workspace/probe/`, or a new `workspace/contracts/` package. Each test asserts a specific predicate from §7's failure-mode list rather than restating the invariant abstractly.

1. **Survives workspace gc (positive — covers failure mode 1).** Construct two editors on one shared runtime. Run `runtime.gc()` twice (gate #1 §C established the two-call discipline; `loom/incr/cells/runtime.mbt:564-568` drains broadcast queue after sweep). Call every externally-exposed accessor on each editor, including diagnostics paths (`get_errors`, `is_parse_valid`) on a non-empty document. Assertion: no abort; values match what they would on a private runtime.

2. **Collects after destroy_editor (positive — covers failure mode 3).** Same setup. Capture the externally-exposed Memo IDs before destroy. Call destroy_editor(A). Run `runtime.gc()` twice. Assertion: `runtime.cell_info(id)` returns `None` for each of A's externally-exposed Memo IDs *unless* a workspace Memo is observing them (probe should set up the negative side of this explicitly, see test 4).

3. **Negative control — without contract, gc collects everything (covers failure mode 1's mechanism).** Construct an editor without installing the Observer scope. Run `runtime.gc()` twice. Assertion: `cell_info` returns `None` for the externally-exposed Memo IDs. This is the failing baseline that test 1 must improve on; if test 3 also passes "no abort", test 1 is not exercising the contract.

4. **Workspace Memo keeps editor Memos alive across destroy (covers Corollary A & failure mode 4).** Construct editor A on a shared runtime. Construct a workspace Memo W that reads A's `cached_proj_node`. Observe W. Call `destroy_editor(A)` — this disposes A's `lifetime_scope`. Run `runtime.gc()` twice. Assertion: A's `cached_proj_node` ID is *still* live (BFS-pinned through W); reading W returns A's last value. The test documents failure mode 4 rather than blessing it — it makes the silent-stale-data behavior explicit so reviewers treat Corollary B's enforcement as a separate question.

5. **Two editors don't accidentally cross-pin (sanity).** Construct A and B on a shared runtime. Call `destroy_editor(A)`. Run `runtime.gc()` twice. Read every B accessor. Assertion: no abort; B's surface unaffected. Failure here means a per-editor scope is shared across editors by mistake.

The tests must be written as black-box against the public API. Internal helpers like `cell_info` are acceptable as test-only assertions (gate #1 used them) but the contract violation must be observable through the public API in at least one test (test 1 covers this — abort-on-read is the public-API symptom).

---

## 9. What this contract does NOT decide

- **Whether the editor's constructor on a shared runtime is a separate function or a parameter on the existing function.** That's follow-up #3.
- **Whether `lifetime_scope` is a new public field, a private field accessed only by destroy, or hidden inside an opaque handle.** Pure API ergonomics, defer to implementation.
- **The Observer count budget.** Gate #1 verified that several Observers per editor compose. Whether many editors times the full rooted surface stresses the runtime is empirically untested but well outside the workspace's near-term scope.
- **What happens if an editor is constructed on its own private runtime (the legacy mode).** This contract is conditional on shared-runtime construction. Private-runtime editors don't need it — the runtime itself is the unit of lifetime, as today.
- **Whether `parser.source()` and the already-public parser views are enough for workspace consumers.** If a future workspace use case needs another parser-internal Memo directly, the externally-exposed set in §4 grows by one and the constructor must observe one more.

---

## 10. Implementation gating

This document is the spec; implementation waits for:

1. **Codex design review** of the document (per `docs/research/2026-05-23-runtime-safety-decision.md` §"Named follow-ups" #4 — the contract is the load-bearing piece, the implementation is downstream).
2. **Decision on follow-up #3** (constructor variant shape). The contract's enforcement target is the constructor, so the signature determines where `scope.add_observer` calls live.
3. **Decision on follow-up #1** (workspace `on_change` multiplexer). Orthogonal in code but conceptually paired — the multiplexer is the workspace-side counterpart to editor-side observation discipline. Reviewing both together lets Codex check the contracts compose without overlap or gap.

Once those are settled, implementation is ~5–10 lines per FFI lifecycle module plus the constructor-side additions. Per-editor scope addition to `SyncEditor` is ~3 lines. Total surface ~30–50 lines across `editor/`, `lang/{lambda,markdown,json}/companion/`, and `ffi/{lambda,markdown}/lifecycle.mbt`. The contract's test set (§8) is ~5 black-box tests in `workspace/contracts/` (or `editor/`).

---

## 11. Open questions for Codex

When this draft goes to Codex for design review, the questions to ask explicitly:

1. **Is the externally-exposed Memo set in §4 complete?** Specifically: are there `parser.runtime().read(...)` calls in the editor stack I missed via grep? Are there indirect Memo reads (e.g., capabilities closures invoked from JS) that need rooting?
2. **Is `parser.source()` the right candidate for "root preemptively because workspace will read it"?** Or is the right set "everything the parser exposes" — beyond the already-required diagnostics and AST reads — to avoid future contract churn each time workspace use cases grow?
3. **Is Corollary B's "tear down dep-graph entries before destroy_editor" enforceable without a workspace coordinator API today?** If not, should the contract specify that destroy_editor on a shared runtime must abort if any workspace Memo still depends on it — preferring fail-fast to silent staleness (failure mode 4)?
4. **Does `Scope::add_observer`'s dispose-hook ordering interact safely with `gc()` running concurrently with destroy_editor?** Both run on the runtime's main thread today, but worth confirming there's no re-entrancy hazard if destroy_editor triggers a callback that calls `runtime.gc()`.
5. **Is test 4 (silent-stale-data documentation) the right failure-mode framing?** Or should it assert that reading a destroyed editor's surface aborts, which would push Corollary B's enforcement down to the runtime level rather than leaving it to the coordinator?
