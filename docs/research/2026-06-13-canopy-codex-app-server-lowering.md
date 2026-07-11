# Lowering Codex app-server edits into canopy — research note (2026-06-13)

**Status:** research/empirical note — records *what was verified and why*, not *what
to build*. Per [design-principles §8] this is a "what was verified" record, kept
separate from an implementation plan. It deliberately cites concrete types,
fields, and line numbers; that is precisely why it lives in `docs/research/` and
not under architecture docs (which are principles-only). Everything below is
either code-verified against the tree at this date or explicitly flagged as
aspirational / unverified.

Companion references: agent-memory `project_canopy_data_flow_text_truth`
(canopy's data flow), `reference_codex_app_server_driving` (the Codex side),
[`scripts/codex-app-server-turn.py`](../../scripts/codex-app-server-turn.py).

## 1. Two systems, one shape

- **canopy** — the source of truth is a **text** CRDT (`event-graph-walker/text`,
  FugueMax sequence CRDT) held by `editor/SyncEditor[T]` alongside an
  `UndoManager` (`editor/sync_editor.mbt:6-7`). The `ProjNode` AST is **not
  stored** — it is a reactive derivation of the parsed text, wired by
  `core/build_projection_memos` as three `incr` Memo cells
  (`SyntaxNode → ProjNode → SourceMap`, `core/projection_memo.mbt:5`;
  `core/README.md`: "owns nothing computational"). The boundary-crossing
  operation is `protocol/UserIntent` (`user_intent.mbt:11`); `core/GenericTreeOp`
  is a UI-level intent type, not a CRDT op.
- **Codex app-server** — exposes the agent's work as a structured JSON-RPC op
  stream (`thread/*`/`turn/*`, `item/*` lifecycle, `FileChange`), not an opaque
  text blob.

Restated in one vocabulary: *an external operation source feeds operations into a
shared document through a log.* That is the CRDT model and the agent protocol
both. The integration is not a chat sidebar — it is treating the agent as a
**first-class participant** whose operations flow through canopy's existing
inbound path. Note the operations-as-data thesis holds at the **text-op /
event-graph** level (sequence insert/delete), **not** at the AST level.

## 2. What the integration buys, mapped to existing APIs

Real and reachable with today's surface:

- **Agent-as-CRDT-peer (#1).** Feed agent edits as `UserIntent::TextEdit` through
  the same `SyncEditor` apply path the human frontend uses, under the agent's own
  `replica_id` (`TextState::new(agent_id)`). **Only the `TextEdit` path is verified
  in this note** (§4–§6); the `StructuralEdit` / `CommitEdit` paths (via
  `LanguageCapabilities` tree-edit handlers) exist but are **unverified here** — see §8.
- **Provenance / undo (#4).** The agent's `replica_id` enters the causal DAG
  automatically; undo is the same operation-inverse machinery.
- **In-place approval (#3).** Render Codex `requestApproval` as proposed-edit
  decorations via the existing `ViewPatch.SetDecorations`, not a separate diff view.
- **Live streaming (#5).** Add an agent ephemeral cursor to `EphemeralHub` and
  stream `item/agentMessage/delta` + edits.

Aspirational / different architecture:

- **Structural validity of agent edits (#2).** Does **not** hold for the running
  architecture. Because the truth is text and the tree is a reparse, an agent can
  emit malformed intermediate text exactly as today; loom reparses it, tolerating
  malformed input as error nodes. Achieving it would require adopting the
  `egw/tree` movable-tree CRDT as source of truth (so `create_node`/`move_node`/
  `delete_node` become first-class CRDT ops — names are README-level in egw, not
  yet `.mbti`-confirmed). Treat as a research track; the `container` facade hints
  at a text+tree hybrid.

## 3. The lowering seam

Codex file changes surface as the `FileChange` type — e.g. in
`ApplyPatchApprovalParams.fileChanges` (path → `FileChange`), the
approval-request message whose shape was read and verified here. (Whether the
streaming `item/fileChange` event carries the identical `FileChange` shape is
**not yet verified** — only the approval-params shape was confirmed from the
JSON schema.) `FileChange` is a `oneOf`:

- `add` `{content}` / `delete` `{content}` — full content → whole-document replace.
- `update` `{unified_diff, move_path?}` — a **unified diff string** → must be
  parsed into hunks and lowered into `UserIntent::TextEdit`.

The MoonBit dispatch already exists in the FFI layer (`ffi/lambda/intent.mbt`):

- `handle_text_intent` → `apply_text_edit` — **SnapToGrapheme** (expands endpoints
  outward to grapheme boundaries).
- `handle_text_intent_checked` → `apply_text_edit_exact` — **ExactBoundaries**
  (returns `false` if an endpoint is off a grapheme boundary or out of range; doc
  unchanged on rejection).

So the `from/to→deleted_len` collapse and the snap/exact choice are MoonBit
concerns, not TypeScript. The TS adapter
(`adapters/editor-adapter/cm6-adapter.ts:255`) only produces the
`{type:"TextEdit", from, to, insert}` JSON — i.e. the **CM6 bridge** computes
`from/to` on the **TS** side (strategy (a)-like, §4). The `codex/` prototype is
different: it computes the splice **entirely in MoonBit** from the diff string,
with **no TS offset step** (strategy (b), §4).

## 4. The crux: endpoint grapheme alignment (stated precisely)

`TextEdit.from`/`.to` are **UTF-16 document code-unit offsets**, half-open
(`protocol/README.md:45`; field types `Int`). The crux is that **edit endpoints
must land on grapheme-cluster boundaries**; the coordinate system the adapter
works in changes only *how* a misalignment is produced, never *whether* it can
be. Two adapter strategies make this concrete:

- **(a) Trust the diff's byte-columns.** Codex diff content is **UTF-8
  lines/bytes**; mapping a byte-column directly to a `TextEdit` offset requires a
  **UTF-8 byte → UTF-16 code-unit** conversion. The *conversion error* is the
  misalignment source.
- **(b) Discard byte-columns, re-diff line contents.** Take only the line
  *number* from the hunk header and recompute the splice from the `-`/`+` line
  *contents* (already decoded to UTF-16 `String`). No byte→UTF-16 arithmetic
  occurs — but the minimal diff **must be computed at grapheme granularity**, or
  a common prefix/suffix boundary splits a surrogate pair / combining sequence.
  The *granularity error* is the misalignment source.

Same crux, two coordinate systems. Three precise claims — all code-verified and
empirically demonstrated (§6), so stated as settled:

1. **The skew is nonzero even for BMP multibyte.** Under (a): a single `é`
   (precomposed U+00E9) is 2 UTF-8 bytes but 1 UTF-16 code unit, so a byte→UTF-16
   converter is **always** required; ASCII-only intuition is wrong even without
   emoji. Under (b) the failure has the same *shape* — a code-unit-granular
   minimal diff splits a grapheme on innocuous-looking input — but a different
   verified witness: the probe case is **non-BMP**, two emoji sharing a UTF-16
   high surrogate (🧑🧒 = U+1F9D1 / U+1F9D2, both `D83E …`), where a code-unit
   common prefix stops mid-surrogate so the splice endpoint lands inside the
   cluster (§6). This is **not** a tight parallel of (a): (a) holds *even for
   BMP* multibyte, whereas (b)'s verified break is non-BMP. The BMP analogue for
   (b) — a combining sequence (`e` + U+0301) split between base and mark — is
   plausible but **not yet probed**, so it is not asserted here.
2. **The skew becomes a *rejectable* error only when it lands mid-cluster** —
   inside a surrogate pair or a combining sequence. When the skew instead lands on
   a *different but valid* grapheme boundary, the result is an edit **correctly
   aligned at the wrong position** — silent content corruption.
3. **Therefore `apply_text_edit_exact` is necessary but not sufficient.** It is a
   guardian of **grapheme alignment only** — it cannot verify **offset
   correctness**. An adapter test suite needs **both**:
   - the **Exact reject** path (catches mid-cluster landings, fail-fast), and
   - a **full-text-match on accept** (catches wrong-but-aligned offsets).

   Do **not** write "Exact catches converter bugs." It catches misalignment, not
   miscomputation.

`apply_text_edit_exact`'s rejection rule (the basis for claim 3) is
`sync_editor_text.mbt:221-227`: reject iff out of range OR an endpoint is not a
grapheme boundary. The snap site (`SnapToGrapheme`, `:231-251`) uses
`@moji.prev/next_grapheme_boundary`, then `apply_local_text_change` constructs the
`@loom_core.Edit` for the CRDT — i.e. snap precedes the eg-walker item-space Edit,
matching `protocol/README.md:52-53`.

**Which strategy the prototype took.** The `codex/` adapter prototype chose
**(b)**: `parse_single_line_update` reads only the line *number* from the hunk
header, and `minimal_splice` recomputes the splice from the `-`/`+` line contents
at grapheme granularity (`codex/lowering.mbt` design note). So the byte→UTF-16
conversion of (a) never appears in that code — but the crux did not vanish, it
**moved** to minimal-diff granularity, which `minimal_splice` addresses head-on.
Read §4's earlier "offset-unit conversion" name as the **(a)-manifestation** of a
coordinate-independent requirement, not as the crux itself. This generalization
is exactly §5's deduction chain (sub-line minimal → mid-grapheme possible →
grapheme alignment required → Exact seatbelt); §5 was the correct statement of
the crux all along.

## 5. Policy: deduced, then precedented

Granularity, not policy, is the free variable, and it forces the policy:

> interleaving caveat (FugueMax bulk/whole-line replace harms concurrent
> same-line merges) → choose **sub-line minimal splices** → endpoints can land
> mid-grapheme → grapheme alignment required → **Exact (reject + recompute
> upstream)** is safer than silently snapping.

This is not only deducible — canopy already chose it for the analogous case. The
comment on `handle_text_intent_checked` (`ffi/lambda/intent.mbt:80-84`):

> *"Used by the JS bridge (`bridge.ts::applySpliceChanges`) to maintain its own
> posOffset bookkeeping; silently snapping inside the seam would cause the
> bookkeeping to drift."*

A Codex diff is the same shape — an external op source with its own offset model.
The structure predicts the Codex adapter should use the Exact entry, and an
existing same-shape consumer (the CM6 bridge) already does.

## 6. Empirical evidence (ephemeral probe, 2026-06-13)

An ephemeral whitebox probe drove the **real** Exact FFI dispatch
(`handle_text_intent_checked`) — not a hand-written offset — confirming §4. Vector:
document `"café🧑🧑Z"` (UTF-16 length 9), sub-line delete of the first emoji at
(line 0, UTF-8 byte-col 5, byte-len 4). The `é` is **precomposed U+00E9**
(2 UTF-8 bytes / 1 UTF-16 unit); every value in the table depends on this — a
decomposed `e` + U+0301 (3 bytes / 2 units) would shift them:

| converter | output `(from, del)` | Exact result | document after |
|---|---|---|---|
| correct (UTF-8 byte → UTF-16) | `(4, 2)` | **accept** | `café🧑Z` (intended) |
| naive (byte-as-UTF-16) | `(5, 4)` | **reject** | `café🧑🧑Z` (unchanged) |

- The naive `from=5` lands on the low surrogate of emoji #1 (mid-grapheme).
- **Control:** `naive_from` and `naive_from+del` are both in-bounds (`5, 9 ≤ 9`),
  so the rejection can only be the grapheme-boundary failure — the negative vector
  is genuinely negative, not rejected for being out of range.
- This vector demonstrates claims 1–3; it does **not** by itself exhibit the
  silent wrong-but-aligned case of claim 2 (that requires a vector whose skew
  lands on a different valid boundary), which is why the full-text-match assertion
  is load-bearing and Exact alone is insufficient.

The probe was removed after observation (not committed), consistent with
prototype-first discipline.

A **second, committed** probe exhibits the same crux under strategy (b)
(`codex/lowering_test.mbt`): document `🧑🧒` → `🧒`, where the two emoji share
UTF-16 high surrogate `D83E`. A code-unit-granular minimal diff stops the common
prefix mid-surrogate (Exact rejects / full-text-match fails); a grapheme-granular
one yields `(from=0, del=2)` and accepts. The §6 table above is the **(a)**
manifestation (byte-as-UTF-16 naive converter); this is the **(b)** manifestation
— the same claim 1–3 in different coordinates.

## 7. Placement

The Codex WebSocket/JSON-RPC client and the diff→`UserIntent` converter are
Codex-specific and the app-server protocol is experimental, so they belong in a
**`codex` adapter outside the framework core** — the same tier as `transport_ws`,
with `core` / `editor` / `protocol` staying Codex-free. The framework-level
abstraction is "an external intent source feeds `UserIntent`s into a `SyncEditor`
under its own `replica_id`"; Codex is one concrete adapter of that.

## 8. Non-goals / open (implementation-phase)

- **Hunk fuzzy-apply under concurrent edits.** Unified-diff hunk line numbers are
  the agent's view; concurrent human edits shift them, so hunks may need
  context-based fuzzy apply. This is a real-adapter / CRDT-merge concern, **out of
  scope** for text-level lowering verification.
- **`StructuralEdit` / `CommitEdit` lowering** — the FFI path exists, but its
  conversion (via `LanguageCapabilities` tree-edit handlers) was scoped out in
  B-narrow as unread and is **not verified** in this note. Distinct from #2: this
  is about lowering structural *intents*, not about tree-as-source-of-truth.
- **Structural validity (#2)** — research track (egw/tree as truth), see §2.
- **egw `tree` op names** — README-level; final signatures need `.mbti`
  confirmation.

[design-principles §8]: separating design docs ("what to build, why") from records
of verification.
