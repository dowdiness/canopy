# Safe Generative UI text lowering

## Status

Approved design for the Generative UI text-candidate repair.

## Problem

`GenerativeUiCandidate::validate` accepts bounded `Text` values, but the current
candidate-to-source lowering rejects `<`, `>`, `{`, and `}`. A candidate can
therefore validate successfully and later fail with `CandidateLoweringError`.
The candidate contract must allow ordinary bounded display text without letting
that text become JSX syntax, an expression, HTML, an attribute, or a DOM
operation.

The replay adapter already checks the session handle and base revision before
candidate or capabilities decoding. This design does not change that gate.

## Decision

Candidate commits bypass parser-source lowering. The adapter lowers a validated
`GenerativeUiCandidate` directly to a typed
`@canopy_core.ProjNode[@jsx_ast.JsxNode]`, then reuses the existing
`reconcile`, `DryRunModel::apply`, and `apply_patches_with_registry` pipeline.

The candidate path is a forced remount boundary. It never reconciles a
candidate projection against a previous candidate or parser projection.

## Typed projection construction

- Construct `@jsx_ast.JsxNode::Root`, `Element`, and `Text` values directly in
  `ffi/jsx`; `lib/cognition` remains renderer-neutral and exposes only the
  validated candidate tree.
- Construct matching `@canopy_core.ProjNode` values with synthetic source spans
  of `0..0`; source maps are not exposed for generated candidates.
- Give the unmounted synthetic Root node ID `0`. Allocate every mounted
  candidate node in preorder from `-2` downward. `-1` remains reserved for
  `DomPatch`'s root-container parent sentinel.
- Candidate validation limits the tree to 1,024 nodes, so mounted IDs occupy
  only the bounded interval `-2..-1025`; no persistent decrementing allocator
  is required.
- Candidate lowering uses the existing `escape_attribute` transformation before
  constructing `JsxAttr::StringLit` metadata values. This preserves the current
  one-pass `data-genui-*` entity normalization performed by both dry-run and
  DOM adapters.
- `GenerativeUiCandidateNode::Text(value)` becomes
  `JsxNode::Text(value)` directly. Its exact bounded string reaches
  `MakeText`/`SetText`; it is never parsed as source syntax.

## Session state and commit ordering

The parser and `committed_source` remain a pair representing the most recently
committed ordinary JSX source. A successful candidate commit must not replace
that pair or claim the parser consumed synthetic candidate source.

The session records one `mounted_origin : Source | Candidate` value alongside
its independent dirty state. A successful candidate commit sets
`mounted_origin` to `Candidate`. The next ordinary JSX source render derives a
forced remount from that value even when both roots have the same tag or shape;
only a successful source commit changes it back to `Source`. A failed source
render leaves `mounted_origin` unchanged, so a retry cannot reconcile parser IDs
against a candidate-owned DOM baseline. Candidate commits also always remount,
including candidate-to-candidate updates. A dry-run failure occurs before the
prior registry is cleared and preserves the committed DOM, source, revision,
and mounted IDs. A DOM-apply failure preserves logical source, revision, and
mounted-ID state, marks the session dirty, and requires a later successful
remount repair; without rollback, its physical DOM may be partial or empty.

The shared commit order remains:

1. Reject unknown, disposed, or stale sessions before candidate/capabilities
   decoding.
2. Validate the typed candidate and lower it to a typed projection.
3. Build patches against an empty mounted-ID baseline.
4. Apply the patches to an empty dry-run model.
5. Only after dry-run success, clear the prior session registry and apply DOM
   patches.
6. Only after DOM success, advance revision, `mounted_ids`, `last_proj`, and
   the dry-run model.
7. Keep parser and `committed_source` unchanged after candidate success.

## Non-goals

- No candidate-specific grammar or token is added to the generic JSX parser.
- No `data-genui-*` attribute gains a hidden DOM side effect.
- No rollback semantics are added for a partially failed DOM application.
- No source-map location is invented for generated candidate content.
- No change is made to replay handle or base-revision precedence.

## Verification

Add deterministic MoonBit boundary coverage for:

1. Candidate text containing `<`, `>`, `{`, `}`, `&`, quotes, and Unicode:
   validation and commit succeed, and the rendered DOM text equals the original
   string exactly. Cover generated metadata attributes containing `&amp;lt;`,
   `&amp;amp;`, quotes, and Unicode so `escape_attribute` plus the one-pass
   `data-genui-*` normalizer preserves their original values exactly.
2. Normal JSX → candidate → normal JSX: each successful stage advances the
   revision once; the final DOM contains only the final source tree; mounted IDs
   are the complete reachable set for that tree.
3. Candidate → candidate with shifted children: forced remount removes the old
   tree rather than reconciling stale synthetic IDs; sibling order and DOM text
   match the second candidate.
4. Candidate validation, lowering, and dry-run failures preserve DOM, revision,
   parser/`committed_source`, and mounted IDs. The next normal source commit
   repairs a dirty root when needed.
5. A DOM-apply failure preserves logical source, revision, and mounted IDs,
   reports no commit, and leaves a dirty root for the next successful remount
   repair. The test must not assert physical DOM rollback.
6. Existing stale, invalid, and disposed replay inputs still reject before
   candidate/capability decoding.

### Property coverage

Extract two pure helpers from the session shell so the invariants do not depend
on a JavaScript DOM fixture:

1. `candidate_to_projection` lowers an already validated candidate to a typed
   projection. Generate bounded candidate trees and text values. For every
   generated value, assert that every projection node ID, including the
   unmounted Root, is unique and never `-1`; assert mounted IDs lie in
   `[-1025, -2]`; and assert the projection preserves every text value with exact
   `String` equality. The property corpus must include a fixed seed corpus of
   `<>{}&`, `&lt;tag&gt;`, quotes, and Unicode, in addition to randomly
   generated bounded strings.
2. `plan_render` is a pure function of `(mounted_origin, dirty, revision)`,
   render kind (`Source` or `Candidate`), and source structural-transition
   information. It returns `must_remount` before any DOM effect.
   `finish_render` is a separate pure reducer from the prior state, that plan,
   and one outcome (`Success`, `DryRunFail`, `DomFail`, or `ProjectionFail`) to
   the next logical baseline and an explicit shell command such as
   `RestoreCommittedSource`. Generate event sequences from the constructor state
   rather than arbitrary raw state tuples. For each generated
   `(kind, structural transition, outcome)` sequence, assert:
   - every candidate attempt plans a remount;
   - any planned render after a dirty state remounts;
   - the first source attempt after a candidate success plans a remount;
   - dry-run, DOM, and projection failures neither advance revision nor replace
     the logical baseline;
   - every success advances revision exactly once;
   - a failed source render retains `mounted_origin == Candidate`; and
   - a source `ProjectionFail` emits `RestoreCommittedSource`.

Use the repository's `@qc.quick_check_fn` pattern and add the existing
quickcheck imports to `ffi/jsx/moon.pkg` under `for "wbtest"`. Keep DOM fixtures
for effect wiring and exact rendered-text assertions; properties cover the pure
projection and transition invariants. Record each QuickCheck failure seed or
shrunk counterexample so it can be reproduced deterministically.

Run `moon check` after each MoonBit file edit, then run affected `ffi/jsx` and
`lang/jsx/proj` tests, `moon info`, `moon fmt`, interface-drift inspection, and
the GenUI browser regression suite.
