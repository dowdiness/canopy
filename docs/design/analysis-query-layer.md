# Analysis Query Layer

**Status:** design proposal — not implemented  
**Goal:** bring syntax-pattern search, semantic queries, and previewable refactors
into Canopy without weakening the core text-CRDT pipeline.

This document refines the ast-grep / `moon ide` integration idea after design
review. It is intentionally conservative: the first milestone is read-only range
highlighting, not rewrite or rename.

## Why this exists

Canopy's vision is not merely to display syntax. It is to let structure and
meaning surface while the user writes. External tools point at two useful
families of interaction:

- ast-grep-style tools: search and transform by syntax shape.
- `moon ide`-style tools: ask compiler-backed semantic questions such as
  definition, references, docs, outline, and rename.

Canopy should not embed those tools directly into the editor model. Instead, it
should normalize their results into derived analysis data that can be rendered as
ordinary projectional UI and, later, previewed as edits.

## Core invariant

The existing pipeline remains the authority:

```text
Text CRDT
  -> source snapshot
  -> parse / projection / source map
  -> analysis
  -> rendering
```

Only the text CRDT is durable ground truth. Analysis results are derived,
snapshot-bound, and discardable. Any edit suggested by analysis must eventually
be applied as validated text edits through the same CRDT path as ordinary user
input.

## Snapshot-bound analysis

Every provider request runs against a source snapshot, not against an implicit
"current file". The snapshot is the provenance that lets Canopy reject late or
stale results.

A source snapshot should identify:

- the document and URI being analyzed;
- the source version observed by the editor;
- a hash and length of the exact source text sent to the provider;
- the unit-converted length used by Canopy internals;
- the source-map generation used when correlating ranges with projections;
- the source text supplied to the provider.

A result is accepted only if its snapshot still matches the editor state it is
being attached to. Otherwise it is stale and must be dropped without mutating
analysis state.

This mirrors the provider-boundary discipline used for cognition work: effectful
providers may finish late, so completion must validate against the inputs that
planned the request.

## Range units

Provider boundaries must normalize offsets before analysis data enters Canopy.

- Canopy-internal analysis ranges use UTF-16 document offsets.
- External byte offsets, line/column pairs, or provider-specific locations are
  adapter-local details.
- Protocol-facing decorations and text edits use the same normalized range
  convention as the editor pipeline.

This conversion is not optional. Byte offsets from ast-grep and compiler
locations from `moon ide` are not safe to attach directly to projection or view
state, especially in the presence of non-ASCII text, combining characters, and
mixed newline conventions.

## Analysis facts

Provider output should become typed internal facts, not string messages with a
kind tag. A fact has common provenance and range data plus a typed payload.

Common fact data:

- fact id;
- document id;
- source snapshot identity;
- normalized UTF-16 range;
- optional projected node hint;
- provider id;
- typed payload.

Payload families include:

- pattern match, with pattern id and captures;
- definition, with symbol identity and declaration location;
- reference, with symbol identity and optional definition link;
- type information, with provider-specific type expression data;
- diagnostic, with severity, code, message, and related locations;
- rewrite suggestion, linking to a previewable edit plan;
- evaluation result, carrying a displayable value.

Messages are display text. They are not the semantic source of truth.

### Projected node hints are optional

The normalized source range is authoritative. A projected node id, when present,
is only a hint.

Reasons:

- provider ASTs and Canopy projection trees may have different granularity;
- a range can overlap several nodes;
- a pattern match can span multiple projected nodes;
- node identity is document-local and can change when reconciliation cannot
  preserve it.

A provider or aggregator may attach a node hint only when the range maps
unambiguously, or when an explicit heuristic has chosen a stable display target.
The first implementation should not depend on node hints.

## Provider boundary

The analysis layer is a facade over provider adapters. It should aggregate
existing in-process analyses and host-side external tools without making the
editor model depend on any one backend.

Provider categories:

- syntax-pattern provider: ast-grep-like structural search;
- semantic provider: `moon ide`-like definition/reference/doc/outline queries;
- evaluation provider: existing language evaluation output;
- diagnostic provider: parse, type, or lint diagnostics;
- future type/lint providers.

Provider requests need workspace context when the provider requires it. For
MoonBit, that means module and package context, target information, and the
workspace root. A `moon ide` adapter is not a single-file string analyzer; it is
a compiler-backed workspace query.

Effectful adapters run outside the pure editor pipeline. In a browser demo, that
means a host, native shell, local dev-server, worker, or other explicit driver.
The editor should receive normalized facts, not spawn CLI tools from rendering
or reactive recomputation.

## Analysis projection

Internal facts should be projected to existing UI surfaces before any protocol
extension is considered.

Initial targets:

- decorations for highlights and underlines;
- diagnostics for errors and warnings;
- annotations or hover-like display text where already supported;
- side panels or match lists derived from the same fact set.

Do not expose the internal fact representation as public protocol in the first
milestone. The protocol is a stable frontend contract; changing it should wait
until several fact families have proven they cannot be represented by existing
decorations, diagnostics, or annotations.

## Edit plans

Rewrite and rename should be preview-first. A provider may suggest edits, but
applying them is a separate user-confirmed operation.

An edit plan records:

- the source snapshot it was computed against;
- a title and provider provenance;
- one or more document edits;
- expected old text for each edited range when available;
- validation steps to run after application;
- whether the plan is single-document or multi-document.

Edit-plan invariants:

- all ranges are normalized UTF-16 ranges;
- edits in one document are non-overlapping;
- application order is deterministic and safe for shifted offsets;
- expected old text must match before an edit applies;
- edits must not split invalid text boundaries;
- multi-document edits are not disguised as one document transaction;
- parse/check validation runs after application;
- public interface drift is reviewed when MoonBit APIs may change.

The first edit-plan implementation should prefer compiler-backed semantic
rename over syntax rewrite, because semantic rename has clearer provider-owned
meaning. Syntax rewrite can follow once preview, validation, and rollback
expectations are stable.

## Implementation sequence

### Phase 1 — range-only structural search overlay

Build the smallest useful slice:

```text
current source snapshot
  -> host-side ast-grep run
  -> byte offsets normalized to UTF-16
  -> pattern-match facts
  -> decorations and match list
```

Do not include rewrite. Do not require node-id mapping. Do not add protocol
variants. This phase proves snapshot validation, offset conversion, and derived
analysis rendering.

### Phase 2 — analysis projection aggregator

Route existing language facts through a small internal aggregator:

- structural matches;
- evaluation results;
- semantic annotations already produced by language packages;
- diagnostics.

The goal is to learn the shape of the common fact model from real in-process
analyses before committing to a broad provider abstraction.

### Phase 3 — read-only `moon ide` provider

Add compiler-backed semantic queries without edits:

- outline;
- definition lookup;
- references;
- docs;
- diagnostics where appropriate.

This phase must include package/module context, stale-result rejection, and
multi-file result representation. Rename remains out of scope.

### Phase 4 — previewable edit plans

Introduce edit plans and start with semantic rename:

```text
semantic rename result
  -> multi-document edit plan
  -> preview
  -> apply selected document edits through CRDT text transactions
  -> reparse / refresh projection
  -> validate
```

Validation for MoonBit work includes at least checking the package/module and
reviewing generated interface drift when public APIs may have changed.

### Phase 5 — semantic fact graph

Once facts are typed and stable, they can become graph relations:

```text
range defines symbol
range references symbol
symbol has type
pattern matches range
diagnostic affects range
```

At that point, search results become navigable semantic structure rather than a
flat list. This is the path toward resurfacing, context-aware views, and
intent-level operations.

## Non-goals for the first milestone

- No rewrite or rename.
- No persistent semantic database.
- No protocol extension.
- No reliance on node-id mapping.
- No browser-direct CLI execution.
- No global workspace indexing beyond the single requested analysis.

## Open decisions

- Where host-side adapters live for native, JS, and web-demo builds.
- How much of the fact model belongs in shared core versus language-specific
  packages.
- Whether semantic provider results should eventually integrate with the
  cognition runtime or remain editor-local.
- How multi-document edit preview should look in collaboration sessions.
- Which validation commands are mandatory for each provider family.

## Success criteria for Phase 1

- ast-grep results are displayed as range highlights for a source snapshot.
- Stale provider results are rejected deterministically.
- Byte offsets are converted to UTF-16 ranges before entering analysis state.
- Non-ASCII test cases prove range conversion correctness.
- The UI can list matches and jump to a normalized range.
- No changes are required to the public protocol.
