# S4 FFI Host Extraction and Export Manifest Plan

## Context

S4 implements the host-binding part of the architecture redesign after S3's
language-runtime boundary work. The target is narrow: extract repeated
Tier-3 FFI host wiring from `ffi/lambda`, `ffi/json`, and `ffi/markdown` into a
shared internal `ffi/host` package while preserving each `ffi/<L>` package as
its own MoonBit JS link root. The extraction must not change the editor sync
surfaces frozen in S2, the `lang/runtime` design from S3, the lambda language
exception, or the per-entry bundle split that motivated the hand-maintained
FFI/re-export arrangement.

The measurement spike at `33db8db` is evidence only. It showed that a generic
`HostRegistry[H]` shape containing per-handle bookkeeping, view-state
bookkeeping, and a coordinator destroy gateway preserved per-entry Vite chunks
with sub-kB deltas. Production work must re-derive that shape with intentional
visibility, constructor, test, and `.mbti` treatment rather than merging the
spike verbatim.

The two S4 deliverables are deliberately separated by PR gate:

- PR1 extracts `ffi/host` and migrates the three language FFI packages onto it.
- PR2 introduces declared export manifests and a discrepancy-reporting check
  while keeping the current hand-maintained export files authoritative.

Deletion of `examples/ideal/main/crdt_reexport.mbt` is out of scope for S4. It
is a later PR after one release of parallel-run, gated on TS typecheck CI,
bundle measurement, and runtime smoke across lambda, JSON, and Markdown FFI
surfaces.

## Decided design summary

`ffi/host` is a Tier-3 internal library dependency. It owns only generic host
bookkeeping:

- a handle map keyed by the exported integer handle
- a per-handle `@editor.ViewUpdateState` map for the ordinary view-patch path
- access to the shared `@workspace.Coordinator` through caller-supplied
  coordinator instances
- a destroy gateway that calls `Coordinator::destroy_editor` and removes FFI
  bookkeeping only after the coordinator accepts destruction

Each `ffi/<L>` remains a separate link root and keeps one process-global
coordinator instance. Each language package owns its language-specific handle
record, protected-cell bundle, editor/companion construction, exported function
names, JSON parsing/serialization choices, and any extra state.

The production registry should be public as a type from `ffi/host`, but not a
blanket data bag. The planned API is:

- `pub struct HostRegistry[H]` with fields not exported for arbitrary
  cross-package assignment.
- A named constructor following the repo convention:
  `HostRegistry::HostRegistry`.
- Methods for inserting, looking up, removing, clearing test state, creating or
  retrieving a view state, and destroying through the coordinator.
- Any method that mutates internal maps lives in `ffi/host`, because methods
  must be defined in the owning package and cross-package `pub struct` fields
  are read-only.

If MoonBit's visibility rules require callers to mutate registry internals
directly, prefer a small method over `pub(all)` fields. Use `pub(all)` only as a
last resort for the `HostRegistry` fields, and document the exact compiler
constraint in the PR body and `.mbti` review. Language handle records and
protected-cell bundles stay private to their `ffi/<L>` package unless an
existing white-box test can no longer test the intended behavior without
promoting visibility; in that case, move or rewrite the test rather than
exporting internals.

Scope decision: PR1 extracts only registry, ordinary view-state bookkeeping,
and the coordinator destroy gateway. It does not generalize the
assemble-handle pattern or protected-cell bundles. The rationale is that
assembly is where language-specific editor constructors, companion outputs,
protected-cell constructors, lambda's `last_created_handle`, and lambda's
analysis attachment disposal semantics meet. Protected-cell bundles are also
language typed: JSON/Markdown have the seven-cell editor subset, while lambda
has ten cells plus companion-derived projection/eval/typecheck cells. Forcing
those into a host protocol would make lambda extras mandatory or create dead
configuration for JSON and Markdown. Minimal extraction captures the proven
duplication without weakening the language boundary.

## Step 1 — Add `ffi/host` with registry contract and tests

Create the `ffi/host` package with imports limited to `editor` and
`workspace/coordinator`. Define the generic registry contract around
handle-map lifecycle, ordinary view-state lifecycle, and coordinator-mediated
destroy. The host package must not import any language package, `llm`, `relay`,
`transport_ws`, JSON/Markdown/Lambda AST packages, or example app package.

Add host-local tests for behavior that is independent of language handles:
view-state get-or-create returns the same state for the same handle, removing a
handle removes its view state, destroy refusal leaves bookkeeping intact, and
destroy success removes bookkeeping. If a realistic destroy test needs a
registered coordinator editor, use the smallest host-local test handle shape
and protected-read surface available without depending on a language package.

Expected compile breakpoint: none outside `ffi/host` until language packages
import it. The first `moon check` may expose MoonBit visibility constraints
around mutating map fields through methods; fix by adding owning-package
methods, not by exposing fields.

Expected `.mbti` diff: a new `ffi/host/pkg.generated.mbti` containing only the
intended `HostRegistry` type and its constructor/methods. Existing
`ffi/{lambda,json,markdown}/pkg.generated.mbti` files should not change in this
step.

Verification:

- `NEW_MOON_MOD=0 moon check`
- `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/host`
- `NEW_MOON_MOD=0 moon info` and inspect `git diff '*.mbti'`
- No bundle build required before callers import `ffi/host`

## Step 2 — Migrate JSON FFI onto `ffi/host`

Import `ffi/host` in `ffi/json/moon.pkg` and replace the local `json_handles`
and `json_view_states` globals with one JSON registry instance. Keep the
JSON-local coordinator, `JsonHandle`, `JsonProtectedCells`,
`assemble_json_handle`, and all exported function names unchanged. The JSON
handle record remains private and still carries `editor`, `editor_id`, and
`cells`.

The migration order is: add the host dependency, introduce the JSON registry,
change `assemble_json_handle` to register handles through the host method, then
port read callsites from direct map access to registry lookup. Port
`json_compute_view_patches_json` to get its `ViewUpdateState` through the host.
Finally port `destroy_json_editor` and test cleanup helpers to host methods.
This order keeps lookup failures easy to diagnose before destroy semantics are
changed.

White-box tests in `ffi/json/lifecycle_phase1_wbtest.mbt` currently write
private `json_handles` and `json_view_states` state. Rewrite them to exercise
the JSON registry through host methods while still validating the JSON
protected-cell fields from the JSON package. Do not move JSON protected-cell
tests into `ffi/host`; host cannot know the seven typed cells.

Expected compile breakpoints: references to `json_handles` and
`json_view_states` fail after the globals are removed; fix package by package
inside `ffi/json` before touching other languages. If field access into the
registry fails due to cross-package read-only rules, add a host method for the
specific operation.

Expected `.mbti` diff: `ffi/json/pkg.generated.mbti` should be unchanged,
because the JS export surface is unchanged. Any diff must be explained as an
accidental API leak or corrected before the PR proceeds.

Verification:

- `NEW_MOON_MOD=0 moon check`
- `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/json`
- `NEW_MOON_MOD=0 moon info` and inspect `git diff 'ffi/json/pkg.generated.mbti' 'ffi/host/pkg.generated.mbti'`
- `cd examples/web && npm run build`; record JSON, Markdown, and Lambda chunk
  sizes even though only JSON was migrated

## Step 3 — Migrate Markdown FFI onto `ffi/host`

Repeat the JSON migration for `ffi/markdown`, keeping the Markdown-local
coordinator, `MarkdownHandle`, `MarkdownProtectedCells`,
`assemble_markdown_handle`, structural-edit parsing, sentinel export, and
manual Markdown view-patch construction unchanged.

The Markdown view path is not identical to JSON: it computes patches manually
from protected reads, source text, diagnostics, and `diff_view_nodes`. Only the
state storage moves to `ffi/host`; the patch algorithm stays in
`ffi/markdown`. This protects the Markdown-specific empty paragraph sentinel
and diagnostic behavior from being pulled into a generic host API.

Rewrite `ffi/markdown/lifecycle_phase1_wbtest.mbt` cleanup and direct
bookkeeping checks against the registry methods. Keep tests that validate
seven-cell protected reads and Markdown patch behavior in the Markdown package.

Expected compile breakpoints: references to `markdown_handles` and
`markdown_view_states` fail after replacement. Fix all Markdown files and
white-box tests before moving to lambda so error output stays localized.

Expected `.mbti` diff: `ffi/markdown/pkg.generated.mbti` should be unchanged.
Only `ffi/host/pkg.generated.mbti` should have the intended new host API.

Verification:

- `NEW_MOON_MOD=0 moon check`
- `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/markdown`
- `NEW_MOON_MOD=0 moon info` and inspect `git diff 'ffi/markdown/pkg.generated.mbti' 'ffi/host/pkg.generated.mbti'`
- `cd examples/web && npm run build`; record JSON, Markdown, and Lambda chunk
  sizes

## Step 4 — Migrate Lambda FFI onto `ffi/host`

Migrate lambda last because its FFI package is the largest and contains
language-local extras. Replace only `lambda_handles` and ordinary `view_states`
with the host registry. Keep all of the following in `ffi/lambda`: the
coordinator singleton, `LambdaHandle`, `LambdaProtectedCells`, companion
storage, `last_created_handle`, `pretty_view_states`, LLM functions,
relay-room state, WebSocket wiring, semantic/pretty projection accessors,
undo functions, and analysis attachment disposal.

The destroy flow must preserve lambda's current ordering: a refused
coordinator destroy leaves FFI bookkeeping and analysis attachment intact; an
accepted destroy removes the ordinary host handle/view state, removes the
pretty view state, clears `last_created_handle` when appropriate, then disposes
the companion analysis attachment. Do not make `pretty_view_states` part of
`ffi/host`; it is lambda-specific state for a separate projection surface.

Rename mechanics must be deliberate. The spike showed that broad textual
renames can corrupt embedding identifiers such as `clear_lambda_handles`. Use
semantic rename where possible, or scoped `rg` plus manual edits restricted to
the FFI bookkeeping identifiers. Do not rewrite exported JS names or embedded
protocol strings.

Rewrite lambda white-box tests that directly clear or inspect `lambda_handles`
and `view_states` to go through host registry methods. Tests that validate
workspace memos, semantic projection, WebSocket integration, relay leaks,
pretty patches, or protected lambda-specific cells stay in `ffi/lambda`.

Expected compile breakpoints: most lambda files reference `lambda_handles`, so
expect failures in lifecycle, diagnostics, undo, intent, semantic, ephemeral,
view, pretty, ws, and wbtests after the registry replacement. Fix in this
order: lifecycle construction and simple get/set, ordinary view patches,
diagnostics/projection accessors, undo/intent/ephemeral/semantic/pretty/ws
callers, then tests. This keeps the package compiling around a single
canonical lookup path.

Expected `.mbti` diff: `ffi/lambda/pkg.generated.mbti` should be unchanged.
Any missing, added, or renamed export is a regression. `ffi/host` remains the
only new public package surface.

Verification:

- `NEW_MOON_MOD=0 moon check`
- `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/ffi/lambda`
- `NEW_MOON_MOD=0 moon info` and inspect `git diff 'ffi/lambda/pkg.generated.mbti' 'ffi/host/pkg.generated.mbti'`
- `cd examples/web && npm run build`; record JSON, Markdown, and Lambda chunk
  sizes

## Step 5 — Host extraction integration sweep

After all three packages compile, remove dead local helper comments that still
describe per-language handle maps, update FFI README text where it describes
the lifecycle owner, and verify import boundaries. The sweep should establish
that `ffi/host` is a dependency of `ffi/{lambda,json,markdown}` only, and that
none of the three FFI packages stopped being a JS link root.

Review `moon.pkg` brace manifests manually. The FFI export arrays in
`ffi/lambda/moon.pkg`, `ffi/json/moon.pkg`, and `ffi/markdown/moon.pkg` must
remain byte-for-byte equivalent except for formatting produced by accepted
tooling. The host package must have no JS export list.

Expected compile breakpoints: duplicate or stale package imports after the
last migration. Fix by removing unused imports and keeping language-specific
imports in language packages, not by moving extra behavior to `ffi/host`.

Verification:

- `NEW_MOON_MOD=0 moon check`
- `NEW_MOON_MOD=0 moon test`
- `NEW_MOON_MOD=0 moon info` and inspect all `git diff '*.mbti'`
- `cd examples/web && npm run build`; include the required PR body table with
  rows JSON, Markdown, Lambda and columns clean main, with change, delta, gzip

## Step 6 — Add declared export manifests and discrepancy check

In a separate PR, introduce a declared manifest per app as the single source of
truth for expected FFI exports. Start with the lambda app seam because it has
both live layers today: `ffi/lambda/moon.pkg` and
`examples/ideal/main/crdt_reexport.mbt` plus `examples/ideal/main/moon.pkg`.
The manifest format should be simple, reviewable, and not code-generated in
this stage. Keep it close to the app or docs path chosen for export-surface
ownership, and document that the existing hand-maintained files remain
authoritative during parallel-run.

Add a script/CI check that compares the declared manifest to both live layers.
The check must parse MoonBit `moon.pkg` brace export lists and the wrapper file
well enough to report symbol-level discrepancies in three directions:
manifest-only, `moon.pkg`-only, and wrapper-only. A failure should tell the
author exactly which symbol is missing from which layer. A raw pass/fail diff
is not sufficient.

The check does not generate or rewrite `crdt_reexport.mbt`, and it does not
delete any wrapper. Codegen is reserved for the deletion-time decision after
one release of manifest parallel-run.

Expected compile breakpoints: none if the manifest and check are additive.
Script failures are expected on first run until the manifest exactly describes
the current lambda app seam. Resolve by correcting the manifest or fixing an
actual hand-maintained discrepancy, not by weakening the check.

Expected `.mbti` diff: none from manifest/check changes unless tests add a
MoonBit package. Any FFI `.mbti` diff in this PR is suspect.

Verification:

- Run the new manifest discrepancy check locally and confirm symbol-level
  reporting
- `NEW_MOON_MOD=0 moon check`
- `NEW_MOON_MOD=0 moon test`
- `NEW_MOON_MOD=0 moon info` and inspect `git diff '*.mbti'`
- `cd examples/web && npm run build`; include the required PR body table with
  rows JSON, Markdown, Lambda and columns clean main, with change, delta, gzip

## PR slicing and merge gates

PR1 is host extraction only. It may contain `ffi/host`, imports from
`ffi/{lambda,json,markdown}` to `ffi/host`, migrated white-box tests, README or
plan-note updates tied to the extraction, and the bundle-size table. It must
not contain export manifest work, `crdt_reexport.mbt` deletion, protected-cell
genericization, assemble-handle genericization, S2 surface changes,
`lang/runtime` changes, or lambda LLM/relay/ws rewiring.

PR2 is export manifest parallel-run only. It may contain manifest files, the
discrepancy check, CI wiring, tests for the check, and documentation explaining
parallel-run. It must not delete wrappers or convert current authoritative
files to generated outputs.

PR3 is deferred deletion and is not part of this plan's implementation scope.
Its gate is at least one release after PR2, plus TS typecheck CI, bundle
measurement, and runtime smoke across all three FFI surfaces.

Every PR body must include a bundle-size table with columns `clean main`,
`with change`, `delta`, and `gzip`; rows `json`, `markdown`, and `lambda`; and
measurements from `cd examples/web && npm run build`.

## Gates and acceptance criteria

- `ffi/host` exists as an internal shared dependency with no language imports
  and no JS exports.
- `ffi/json`, `ffi/markdown`, and `ffi/lambda` remain separate MoonBit link
  roots with unchanged JS export surfaces.
- Ordinary handle maps, ordinary view-state maps, and coordinator destroy
  gateway behavior are shared through `ffi/host`.
- Protected-cell bundles remain language-local.
- Lambda-specific companion, `last_created_handle`, `pretty_view_states`,
  LLM, relay, WebSocket, semantic, and analysis disposal behavior remains
  language-local.
- `ffi/{lambda,json,markdown}/pkg.generated.mbti` diffs are empty or explicitly
  justified as non-breaking; expected public API addition is limited to
  `ffi/host/pkg.generated.mbti`.
- Bundle deltas stay in the spike-proven sub-kB range unless a PR explicitly
  explains and justifies the variance.
- The export manifest check reports symbol-level discrepancies across the
  declared manifest, `ffi/lambda/moon.pkg`, `crdt_reexport.mbt`, and
  `examples/ideal/main/moon.pkg`.
- `crdt_reexport.mbt` remains present after S4.

## Baseline correction note

The architecture proposal recorded historical S4 bundle baselines of JSON
277 kB, Markdown 246 kB, and Lambda 546 kB. Those numbers are not
reproducible: a fresh build at S0 commit `979c2fe` (the proposal's own date)
yields 370.29 / 333.17 / 683.92 kB — within ~1 kB of current main, proving
S1–S3 added almost nothing and the recorded numbers came from a different
method or toolchain. The operative gate is the 2026-06-12 clean-main
measurement (`examples/web` Vite chunks, minified, pinned submodules):

- JSON: 370.6 kB, gzip 89.0 kB
- Markdown: 333.6 kB, gzip 80.8 kB
- Lambda: 685.2 kB, gzip 155.4 kB

Keep the proposal's numbers as historical context only. S4 PRs compare against
the 2026-06-12 operative gate and against clean `main` in the PR body table.
The spike delta evidence was JSON +0.26 kB, Markdown +0.26 kB, and Lambda
+0.63 kB, so sub-kB deltas are the expectation for host extraction.

## Risks

- Bundle regression: shared host code could still pull too much into each
  entry if imports widen. Mitigation: host imports only `editor` and
  `workspace/coordinator`, bundle table required on every PR.
- Visibility creep: making registry fields `pub(all)` would turn an internal
  bookkeeping package into a data bag. Mitigation: prefer owning-package
  methods and review `.mbti` diffs.
- Lambda over-generalization: companion, pretty view, LLM, relay, WebSocket,
  and analysis disposal state could be accidentally pulled into the generic
  host. Mitigation: PR1 scope is registry/view-state/destroy only.
- Test migration drift: existing wbtests rely on private maps. Mitigation:
  rewrite cleanup/introspection through host methods while keeping
  protected-cell behavior tests in language packages.
- Rename damage: broad textual replacements can alter exported or embedded
  identifiers. Mitigation: scoped semantic/manual rename and targeted `rg`
  review for exported strings.
- Manifest false confidence: a manifest that only checks one layer could miss
  the current two-layer export bug class. Mitigation: compare against both
  `ffi/lambda` and `examples/ideal/main` live layers with symbol-level output.
