# JSX Patch Property Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic QuickCheck coverage proving that generated JSX reconcile patches, including releases, insertions, text, expression spans, and nested updates, produce the same final fake-DOM model as a fresh render.

**Architecture:** Reuse the existing pure `DryRunModel` in `lang/jsx/proj/dry_run.mbt` as the fake DOM model. Generate bounded old/new declarative trees in a whitebox test, lower them to `ProjNode[JsxNode]`, reconcile the new tree against the old mounted IDs, apply the incremental patches to the old model, and compare the result with applying a fresh patch set for the reconciled new tree. The property exposed a real exact-key LCS identity defect, so the implementation also updates generic exact-key reconstruction to preserve earliest feasible sibling identities; no DOM, FFI, session API, or `DomPatch` contract changes.

**Tech Stack:** MoonBit, `@qc` QuickCheck, `@splitmix.RandomState`, `@canopy_core.ProjNode`, `@jsx.JsxNode`, `DryRunModel`, `reconcile`, `reconcile_jsx_projection`.

## Global Constraints

- Reuse the existing `DryRunModel`; do not create a second fake-DOM implementation.
- Keep generated trees bounded to depth four and at most three children per element.
- Include Element, Text, and ExprSpan nodes in the generator; use nested elements so parent/child insertion is exercised.
- Keep all new helpers package-private and test-only.
- Do not change `DomPatch`, `DryRunModel::apply`, or the JSX session API. Change generic exact-key reconciliation only because the independent duplicate-sibling regression exposed a real identity defect.
- Keep the existing explicit release-before-insert regression test.
- Add QuickCheck imports only to `lang/jsx/proj/moon.pkg` under `for "wbtest"`.
- Run `NEW_MOON_MOD=0 moon check lang/jsx/proj` after every MoonBit edit.
- Record any QuickCheck seed or shrunk counterexample if a property fails.

## Existing API Reuse Check

- `DryRunModel::empty` and `DryRunModel::apply` in `lang/jsx/proj/dry_run.mbt`: reused as the only fake-DOM state transition and failure boundary.
- `reconcile` in `lang/jsx/proj/reconcile.mbt`: reused to generate incremental `DomPatch` sequences and mounted IDs.
- `reconcile_jsx_projection` in `lang/jsx/proj/proj_node.mbt`: reused to assign stable IDs from exact JSX subtree matching before patch generation.
- `@canopy_core.ProjNode::ProjNode` and `@jsx.JsxNode` constructors: reused to build test projections without a parser or DOM.
- `@quickcheck.Arbitrary`, `@qc.Shrink`, and `@qc.quick_check_fn`: reused for bounded generated cases and deterministic shrinking.
- `Array` is the correct core collection for ordered children and patch lists; `@set.Set` is reused for uniqueness membership, while `Iter` is reused for lazy structural shrinking. `Map` was considered but is unnecessary for the test-only uniqueness predicate.

---

### Task 1: Wire QuickCheck dependencies for the projection whitebox package

**Files:**
- Modify: `lang/jsx/proj/moon.pkg`

**Interfaces:**
- Consumes: the existing projection package imports.
- Produces: `moonbitlang/core/quickcheck`, `moonbitlang/core/quickcheck/splitmix`, and `moonbitlang/quickcheck` available only to whitebox tests.

- [x] **Step 1: Add the existing `for "wbtest"` QuickCheck import block**

Match the established `core/moon.pkg` and `ffi/jsx/moon.pkg` pattern:

```moonbit
import {
  "moonbitlang/core/quickcheck",
  "moonbitlang/core/quickcheck/splitmix",
  "moonbitlang/quickcheck" @qc,
} for "wbtest"
```

- [x] **Step 2: Run the package check**

Run:

```bash
NEW_MOON_MOD=0 moon check lang/jsx/proj
```

Expected: the package still checks successfully; no production behavior changes.

- [ ] **Step 3: Commit only if this isolated wiring is independently useful**

Do not create a separate commit unless the repository workflow requires it; keep the import with the property-test commit otherwise.

---

### Task 2: Add the generated old/new patch-model property

**Files:**
- Create: `lang/jsx/proj/patch_properties_wbtest.mbt`

**Interfaces:**
- Consumes: `DryRunModel`, `DomPatch`, `reconcile`, `reconcile_jsx_projection`, `@core.ProjNode`, and `@jsx.JsxNode`.
- Produces: one package-private QuickCheck property and one named whitebox test.

- [x] **Step 1: Define a bounded generated tree and pair**

Use a test-only enum with the three mounted node kinds:

```moonbit
enum PatchTree {
  Element(tag~ : String, children~ : Array[PatchTree])
  Text(value~ : String)
  ExprSpan(raw~ : String)
} derive(Debug, Eq)

struct PatchTreePair {
  old : PatchTree
  new : PatchTree
} derive(Debug)

Implement `@quickcheck.Arbitrary` for `PatchTreePair` and structural `@qc.Shrink` implementations for both `PatchTree` and `PatchTreePair`. Shrinking must enumerate strictly simpler cases: remove the whole element child list, shrink child arrays through the built-in `Array` shrinker, shrink text and expression strings through the built-in `String` shrinker, and shrink each pair side independently. Generate depth at most four, zero through three children, fixed element tags (`div`, `span`, `p`), and varied text/raw values including empty, short, and punctuation-containing strings. The generator must produce nested elements as well as text/expression leaves. A failing property must therefore report a small tree with a reproducible seed rather than the original random tree.

- [x] **Step 2: Lower generated trees to typed projections**

Implement a test-only recursive helper returning paired `JsxNode` and `ProjNode[JsxNode]` values. Assign mounted-node IDs from `Ref(1)` for the old tree and a disjoint range such as `Ref(100_000)` for the provisional new tree; wrap each generated tree in a root projection with root ID `0`. Use empty attributes so the property focuses on patch ordering and mounted content rather than attribute normalization. Assert that every mounted ID is unique and that mounted IDs never include root ID `0`.

- [x] **Step 3: Define the model-equivalence property**

For each generated pair:

1. Build the old projection.
2. Reconcile it against an empty mounted-ID set and apply those patches to `DryRunModel::empty()`.
3. Build a fresh new projection with provisional IDs from the disjoint range and call `reconcile_jsx_projection(old, new, Ref(1_000_000), None)` to obtain the identity-preserving new projection.
4. Reconcile the new projection against the old mounted IDs and apply the incremental patches to the old model.
5. Separately reconcile the identity-preserving new projection against an empty mounted-ID set and apply the fresh patches to an empty model.
6. Return true only when incremental application succeeds, fresh application succeeds, every reported reachable-ID array is unique and excludes root ID `0`, the final model shapes are equal, and both paths report the same reachable mounted IDs.

This explicitly exercises release-before-insert because the generated old/new sibling lists may remove and insert nodes at different indexes. It also covers nested parent IDs and text/expression nodes. The property proves final fake-DOM shape/order, not duplicate-key identity tie-breaking; that identity contract is asserted separately below.

- [x] **Step 4: Add deterministic fixed regressions alongside the property**

- `[Text("a"), ExprSpan("x"), Text("b")] → [Text("b"), Text("new"), ExprSpan("y")]`;
- nested removal followed by insertion under the same surviving parent;
- a mixed element/text/expression sibling update;
- duplicate-key JSX siblings where old `[span("a"), span("a")]` becomes `[span("a"), span("a"), span("a")]`; add the independent identity/LCS regression in `lang/jsx/proj/reconcile_wbtest.mbt` and generic append/deletion/mixed-key tie regressions in `core/reconcile_properties_wbtest.mbt`, asserting earliest feasible old IDs and fresh IDs for genuinely inserted nodes. The model-equivalence oracle cannot provide this independent identity check.

Each case must assert the final `DryRunModel::shape()` exactly, not merely that `apply` returns `Ok`.

- [x] **Step 5: Calibrate the model-equivalence detector**

Use one deterministic old/new transition with an insertion, corrupt exactly one emitted `Make*` patch's sibling index to a different in-bounds index in a test-only patch array, require the corrupted `apply` to succeed, and assert that its shape differs from the fresh-render oracle. This known-positive control proves the comparison rejects the historical sibling-order failure without introducing a second fake-DOM implementation.

- [x] **Step 6: Run the new tests**

Run:

```bash
NEW_MOON_MOD=0 moon check lang/jsx/proj
NEW_MOON_MOD=0 moon test lang/jsx/proj
```

Expected: the new fixed cases and QuickCheck property pass. If the property exposes a real defect, retain the failure seed/counterexample, then change the smallest production boundary required by that counterexample.

---

### Task 3: Verify the complete issue contract

**Files:**
- Modify: `core/reconcile.mbt` (exact-key LCS reconstruction defect exposed by the independent identity regression)
- Modify: `core/reconcile_properties_wbtest.mbt` (generic exact-key identity regressions)
- Modify: `lang/jsx/proj/pkg.generated.mbti` only if generated interfaces change
- Modify: `lang/jsx/proj/reconcile_wbtest.mbt` (JSX duplicate-key identity regression)
- No browser files are expected to change.

- [x] **Step 1: Run focused package validation**

```bash
NEW_MOON_MOD=0 moon check lang/jsx/proj
NEW_MOON_MOD=0 moon test lang/jsx/proj
NEW_MOON_MOD=0 moon test ffi/jsx
```

- [x] **Step 2: Run formatting and interface generation**

```bash
NEW_MOON_MOD=0 moon fmt lang/jsx/proj
NEW_MOON_MOD=0 moon info lang/jsx/proj
```

Inspect `lang/jsx/proj/pkg.generated.mbti`; the new helpers are test-only, so no public API change is expected.

- [x] **Step 3: Inspect the diff**

Confirm the change provides evidence for:

- generated final sibling order;
- release-before-insert;
- text and expression-span nodes;
- nested updates;
- deterministic property generation and shrinking;
- session/DOM production code unchanged unless a property found a genuine defect.

- [x] **Step 4: Run whitespace validation**

```bash
git diff --check
```

- [x] **Step 5: Commit the focused test change**

```bash
git add lang/jsx/proj/moon.pkg lang/jsx/proj/patch_properties_wbtest.mbt
# Include pkg.generated.mbti only if moon info changed it intentionally.
git commit -m "test(jsx): property-test patch application ordering"
```
