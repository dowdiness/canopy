# Architecture Redesign — Staged Restructuring Proposal

**Date:** 2026-06-11
**Status:** Proposed (Codex design-validated 2026-06-11; amendments folded in)
**Related:**
[Library API boundary ADR (S0, accepted)](../decisions/2026-06-11-library-api-boundary.md) ·
[Shared-substrate incr version lock](../decisions/2026-06-10-shared-substrate-incr-version-lock.md) ·
[Framework genericity contract](../decisions/2026-03-29-framework-genericity-contract.md) ·
[Identity and reuse mechanisms](../decisions/2026-06-01-identity-and-reuse-mechanisms.md) ·
TODO §14 (library identity) · TODO §15 (editor decoupling) · TODO §18 (shared-runtime workspace)

This is the umbrella proposal plus staged migration index — a `docs/plans/`
execution spec, **not** a `docs/architecture/` record. Concrete files, types,
and counts below are point-in-time evidence (2026-06-11 snapshot; code is the
source of truth). The durable principle-level architecture statements live in
`docs/architecture/` and are updated as stages land. Each stage (S1–S5b) gets
its own narrow plan doc when execution starts; this document is the canonical
statement of *why*, *what target*, and *in what order*.

## Why

The pipeline architecture (CRDT → parser → projection → editor → protocol →
adapters) is sound and is **not** being replaced. Four structural problems now
generate disproportionate change cost:

1. **Substrate version coherence is policed, not constructed.**
   `dowdiness/incr` is consumed via registry pin (root `moon.mod.json`) *and*
   as a nested submodule inside loom; `event-graph-walker` is a direct canopy
   submodule *and* a second nested submodule inside loom; canopy path-deps
   reach through the loom submodule into loom's nested submodules
   (`./loom/egglog`, `./loom/egraph`) and internals. Coherence costs an ADR,
   `scripts/check-shared-substrate.sh`, CI gates (#574), and manual pointer
   dances (#575). The five commits on main preceding this proposal are all
   drift management.
2. **`editor/` is a gravity well.** Highest churn in the repo (642
   file-changes 2026-03→06; next is `projection/` at 399). One package mixes
   nine concerns: CRDT sync dispatch, binary wire encoding
   (`sync_protocol.mbt`), WebSocket transport (`websocket_js.mbt` /
   `websocket_native.mbt`), recovery state machine, undo/history,
   grapheme-aware text editing, tree editing, view diffing, parse
   orchestration. `SyncEditor[T]` owns ~12 fields spanning all of them. The
   sync wire format is defined twice (`editor/sync_protocol.mbt`,
   `relay/wire.mbt`), held in parity only by `relay/cross_compat_wbtest.mbt`
   and frozen fixtures.
3. **The per-language pattern is ~75% repeated wiring with no enforced
   contract.** A new language touches 4 packages / 13–16 files across three
   module boundaries. `ffi/{lambda,json,markdown}` are ~70–75% structurally
   identical; the companion `apply_*_edit` bridge is ~80% language-agnostic
   but re-implemented per language. The lambda family (7 packages) diverged so
   far that `ADDING_A_LANGUAGE.md` warns against copying it.
4. **Two write paths and two export layers at the app seam.**
   `examples/ideal/main` calls typed APIs directly while TS calls JSON FFI
   through the hand-maintained `crdt_reexport.mbt` (31 wrappers, exists for
   per-entry bundle splitting). Documented bug history at this seam: #554,
   #555/#558, #571, runtime TypeError on missed second export layer.

Secondary pressures: the library-vs-application identity is undeclared
(TODO §14 — ~55 "unused" `pub` fns re-litigated per audit; ~100 FFI fns with
no stability contract), and reactive-cell ownership is diffuse (TODO §18 —
cells constructed in editor, companions, ffi, and apps; `workspace/coordinator`
adopted only by `ffi/*`).

**Explicit non-pressures** (no redesign warranted): no import cycles in the
substrate graph; dependency direction lang → editor → core holds at the import
level; runtime performance is healthy — remaining perf items (TODO §3–5) are
local optimizations.

## Scope

In:

- canopy root module packages: `core`, `editor`, `projection`, `protocol`,
  `relay`, `ephemeral`, `llm` (placement only), `workspace/*`, `lang/*`,
  `ffi/*`
- substrate governance policy per dependency, not library internals
- the app-seam export surface (`crdt_reexport.mbt` replacement path)
- the public-API boundary declaration (S0 ADR)

Out (intentionally unchanged):

- internals of loom, seam, incr, event-graph-walker, egglog/egraph (own repos;
  only their *consumption mechanism* is in scope)
- the rabbita fork and `lib/*` UI widget modules
- canvas / block-editor examples beyond compile compatibility
- formal-verification packages
- CRDT algorithms and parser reuse mechanics (identity-mechanisms ADR stands)
- performance work tracked in TODO §3–5

## Current State

- Documented architecture: `docs/architecture.md`,
  `docs/architecture/responsibility-map.md` — text-first pipeline with
  documented anti-patterns; largely respected at import level (verified
  against live `moon.pkg` import graph 2026-06-11).
- Language specifics enter `editor/` and `projection/` via **test** imports
  only (lambda as test fixture) — a leak relative to the TestExpr genericity
  proof approach the genericity ADR established for `core`.
- The ephemeral extraction requested by TODO §15 has **already shipped**
  (top-level `ephemeral/` package; `editor/ephemeral_facade.mbt` remains as
  facade). The TODO entry is stale.
- A transport seam already exists (`editor/in_memory_transport.mbt`).
- `ffi/lambda` additionally bundles `llm` and `relay` wiring — infrastructure
  inside a language facade.
- The package named `protocol/` is the **view** protocol
  (ViewNode/ViewPatch/UserIntent); the **sync** wire protocol lives inside
  `editor/` — one concept-name, two unrelated meanings.

## Desired State (target architecture)

Same pipeline, sharper boundaries. Arrows mean "may depend on":

```text
L6 apps/examples (ideal, canvas, block-editor, web/TS)
      ↓
L5 host bindings   ffi/host (generic registry+lifecycle) + ffi/<L> (thin registration)
      ↓
L4 language SPI    lang/runtime (generic companion/dispatch) + lang/<L> (grammar-specific)
      ↓
L3 infrastructure  transport-ws (js/native), relay, persistence  — adapters only
      ↓                                  ↘ (relay depends on L1 wire, never editor)
L2 domain engine   editor (orchestration, NO I/O) · sync-session (sync policy +
                   recovery, transport-agnostic) · projection · ephemeral
      ↓
L1 kernel          core · protocol/view · protocol/wire (single sync wire definition)
      ↓
L0 substrate       incr · loom/seam · event-graph-walker · moji/text-change/pretty
```

Key structures (each traces to a Why item):

1. **`protocol/wire`** — owns *all* envelope/version/namespace constants, the
   only encode/decode constructors, an explicit frame-namespace API for
   ephemeral payloads, and the documented version-bump protocol. `editor`,
   `relay`, and `ephemeral` consume it exclusively. *(Codex amendment: scope
   includes constants + ephemeral framing, not just message codecs — partial
   moves reintroduce drift.)*
2. **`sync-session` + `transport-ws`** — sync state machine (status, recovery,
   retries, deferred buffering, watchdog) and message dispatch extracted from
   `editor/` behind the existing Transport seam; WebSocket externs become an
   L3 adapter. `editor/` keeps document + parser + projection orchestration,
   undo, text/tree editing.
3. **`lang/runtime`** — generic companion machinery (editor construction,
   `apply_edit` dispatch: match op → compute spans → apply → reconcile cursor,
   memo attachment) extracted once. Languages provide a **capability record**
   (extends the existing `LanguageCapabilities[T]` closure-record pattern;
   records over traits because MoonBit traits are Self-based without type
   parameters, plus the orphan rule). Lambda extras (eval tiers, scope,
   semantic) are **optional capability fields with explicit unsupported
   paths** — never mandatory protocol. *(Codex: SOUND as specified.)*
4. **`ffi/host`** — generic handle registry, lifecycle, coordinator wiring,
   protected-cells plumbing once; `ffi/<L>` shrinks to registration plus
   genuinely language-specific exports. `llm`/relay wiring moves out of
   `ffi/lambda`. One declared export manifest per app replaces the
   `crdt_reexport.mbt` + `moon.pkg` export-list pair.
5. **Substrate governance** — every `dowdiness/*` dependency has one declared
   ownership policy: either a single consumption mechanism, or an explicit
   dual-source exception with resolver-identity CI and a removal /
   re-evaluation date (see S5a; direction decided there, not here).
6. **Declared API boundary** — the S0 ADR
   (`docs/decisions/2026-06-11-library-api-boundary.md`).

Cell-ownership (TODO §18) resolves *by* moves 2–4: editor-core owns projection
memos, sync-session owns sync cells, lang/runtime owns language memos,
ffi/host owns handle-scoped lifetimes via the coordinator — giving §P0b its
atomic-boundary candidates from structure rather than convention.

### Dependency and boundary rules

- L(n) depends only on L(n−1) and below; never upward; L2 engines interact
  only via L1 types.
- `core`, `protocol/view`, `protocol/wire` import substrate only — no
  language, transport, or app imports (extends the genericity ADR).
- `editor` must not import any `lang/*` **including test imports** — the
  lambda test fixture is replaced by a TestExpr-style neutral grammar.
- `relay` depends on `protocol/wire` + `byte_codec` only; never on `editor`.
- `lang/<L>` depends on `lang/runtime` + its loom grammar; never on `ffi/*`
  or another language.
- `ffi/<L>` is the only place JSON serialization of editor state lives; an
  app uses typed APIs *or* the ffi surface for a given mutation flow, never
  both.
- Substrate: one governed policy per dependency; dual-source exceptions must
  be documented in the substrate ADR with resolver-identity CI and removal /
  re-evaluation dates.
- Enforcement: `.mbti` diff review (existing), import-graph lint over
  `moon.pkg` files in CI, `workspace/probe` as the cross-package contract-test
  home.

## Steps (migration stages)

Each stage is independently shippable and reversible; later stages assume
earlier ones landed. Compatibility shims live **at least one full release
cycle** before removal *(Codex amendment)*.

1. **S0 — Declare the API boundary (docs only).** Accept/amend the
   [library API boundary ADR](../decisions/2026-06-11-library-api-boundary.md);
   link this plan from TODO; mark the stale TODO §15 ephemeral entry done.
   Risk: nil.
2. **S1 — Unify the sync wire protocol.** Create `protocol/wire`; move
   `editor/sync_protocol.mbt` encode/decode **plus all version/namespace/frame
   constants** byte-equivalently; add the explicit ephemeral frame-namespace
   API; port `relay/wire.mbt` onto it; deprecated re-export aliases in editor
   (`#deprecated(skip_current_package=true)` + alias, the in-repo proven
   idiom). Frozen fixtures (`relay/wire_frozen_wbtest.mbt`,
   `ephemeral/wire_format_fixture_wbtest.mbt`) must pass **unmodified**;
   `cross_compat_wbtest.mbt` flips from drift-detector to contract test.
   Document the version-bump protocol in the package README.
3. **S2 — Extract `sync-session` + `transport-ws`.** Move recovery, status,
   ws lifecycle, dispatch behind the Transport seam. **`SyncEditor`'s type,
   fields, and constructors stay stable** — the split happens behind the
   struct; surface changes ship no earlier than one release later via
   deprecations *(Codex amendment: re-export-only preservation is not enough
   if the struct surface changes)*. Verify: relocated `error_path` /
   `recovery` / `sync_editor_ws` wbtests, collaboration E2E suites.
4. **S3 — Extract `lang/runtime`; converge families.** Start from markdown or
   json (clean CstFold shapes); lambda migrates **last**, its extras as
   optional capabilities. Benchmark-gated: microbenchmark capability dispatch
   on the `handle_text_intent` hot path *before* landing (enum-boxing
   precedent: a storage-shape change once cost 2×). Verify per language:
   snapshot tests, round-trip edit wbtests asserted on messages (not just
   success), differential tests with non-vacuity asserts, `workspace/probe`.
5. **S4 — `ffi/host` + export manifest, parallel-run.** Extract the shared
   ffi wiring; ship the declared manifest **alongside** `crdt_reexport.mbt`
   for one release. Deletion gated on: TS typecheck CI, per-entry bundle-size
   measurement against baselines (json 277 kB / markdown 246 kB /
   lambda 546 kB — per-entry splitting must not regress), and runtime smoke
   across all three FFI surfaces *(Codex amendment)*.
6. **S5a — Substrate governance ADR + resolver-identity CI guard.** Decide
   the governance policy per dependency. Preferred direction: **loom migrates to
   registry `event-graph-walker`; canopy keeps its direct submodule** — the
   originally drafted inverse (drop canopy's submodule, path-dep loom's nested
   copy) would add a loom PR + pointer bump to every egw change *(Codex
   amendment: gate count goes up; rejected)*. Alternative: explicit
   dual-source policy. Either way, add a CI guard asserting both resolution
   paths yield the same egw version. The version-lock ADR is amended, not
   replaced.
7. **S5b — Execute the de-dup** in the direction S5a decided. Highest
   coordination cost (multi-repo, one merge gate per nesting level); only
   after S1–S4 landed and the cross-repo CI green path rehearsed once.
8. **S6 — Continuous app-layer modularization.** Feature-module splits of
   ideal's 44-variant Msg / 360-line update, continuing the existing ui/
   extraction. Human-in-the-loop per the UI rule; never batch.

## Acceptance Criteria

- [ ] S0 ADR accepted; TODO §14 exit conditions met; stale §15 entry closed.
- [ ] One sync-wire definition: grep finds no encode/decode of the sync frame
      outside `protocol/wire`; frozen fixtures unchanged.
- [ ] `editor/` imports no transport, no wire encoding beyond `protocol/wire`
      types, no `lang/*` (incl. tests).
- [ ] `relay` builds without `editor` in its import set.
- [ ] A new-language checklist measurably shrinks (target: ≤2 new packages,
      no copied ffi lifecycle code).
- [ ] `crdt_reexport.mbt` deleted only after manifest parallel-run + the three
      S4 gates pass.
- [ ] Substrate ADR names one governed policy per dependency (single
      mechanism or documented dual-source exception); resolver-identity CI
      guard green.
- [ ] Import-graph lint enforcing the boundary rules runs in CI.

## Validation

```bash
moon check && moon test                  # workspace
moon info && git diff '*.mbti'           # API surface diffs per stage
moon bench --release                     # S3 dispatch gate
cd <submodule> && moon test              # per CI matrix
# S4: per-entry bundle measurement + Playwright suites per ci.yml
```

Plus: frozen wire fixtures (S1), `workspace/probe` integration probes per new
seam, E2E suites (ideal, web, canvas, demo-react), browser phase benchmarks
for `handle_text_intent` (S3), per-entry bundle budgets (S4).

## Risks

- **S3 behavioral drift** in edit dispatch (error messages, cursor
  reconciliation order) — mitigated by message-asserting round-trip tests.
- **S3 dispatch cost** — benchmark-gated; fallback: direct call path for hot
  ops, generic routing for cold ops (recorded as explicit trade-off).
- **S4 bundle regression** — parallel-run + measurement before deletion; the
  re-export layer exists for a real reason (≈7.6 MB module-split saving).
- **S5b coordination cost** — bounded by S5a governance-first and rehearsal.
- **API compatibility** — deprecated aliases + facades, one-cycle minimum;
  S0 ADR defines which breaks need shims at all.

## Notes

- **Codex design validation (2026-06-11):** verdicts — protocol/wire seam
  SOUND-WITH-CHANGES; capability-record SPI SOUND; substrate single-checkout
  SOUND-WITH-CHANGES (direction reversed, see S5a); migration order
  SOUND-WITH-CHANGES (shim-lifetime + struct-surface conditions). All
  amendments are folded into the stages above and marked *(Codex amendment)*.
- Unknowns to resolve before the dependent stage: (1) whether moon resolves
  canopy's egw and loom's nested egw as one or two package graphs — before
  S5a; (2) bundle behavior of consolidated ffi/host under per-entry splitting
  — spike before S4 deletion; (3) capability-dispatch cost — microbenchmark
  before S3; (4) Structure-mode completion state (`docs/decisions-needed.md`)
  — before S6 touches it.
- Trade-offs considered and rejected: loomgen-now (would codify the current
  asymmetric pattern; generate *after* S3 stabilizes the template); full
  monorepo flattening (submodules are published libraries); full rewrite
  (boundaries are mostly honored — this is consolidation).
- Evidence base: live `moon.pkg` import-graph extraction, git churn
  2026-03→06, `.gitmodules` at both nesting levels, four bounded package-map
  research passes, `docs/TODO.md` §14/§15/§18, graphify graph over loom
  (no import cycles; `Runtime`/`Signal`/`Memo` as expected god nodes).
