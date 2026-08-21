# Gate R0 canonical positional-event and Unicode contract

**Date:** 2026-08-20  
**Wayfinder:** [#1314](https://github.com/dowdiness/canopy/issues/1314)  
**Depends on:** [restore architecture](2026-08-19-egwalker-r0-restore-architecture-reassessment.md), [capture receipt](2026-08-20-r0-capture-receipt-reassessment.md), and [cold capability boundary](2026-08-20-r0-cold-event-graph-capability-boundary.md)

## Result

The canonical EGW event coordinate is a **zero-based Unicode-scalar index in the visible text materialized by the event's declared parent frontier**.

The browser, Loom, SourceMap, Markdown façade, and accepted Markdown transform receipt remain **UTF-16 code-unit** surfaces. Conversion happens once at the capture/application adapter. A UTF-16 splice or multi-span patch is not a canonical event.

The canonical event algebra remains paper-aligned:

```text
CanonicalTextEventV1 {
  identity
  declared_parents
  body
}

CanonicalTextEventBodyV1 =
  InsertScalar(parent_relative_scalar_position, scalar_utf8)
  | DeleteScalar(parent_relative_scalar_position)
  | Undelete(target_identity)  // Canopy extension, outside the paper
```

These V1-suffixed names are the unchanged body/algebra layer, not the V2 authenticated sidecar generation. `CanonicalTextEventV1` is a conceptual algebra rather than one serialized envelope: its identity/parents are represented by `EventMetaV2`, while its encoded body is exactly `EventPayloadV1.canonical_event_body_bytes`. One insert scalar and one delete effect own one `RawVersion`. Replace and multi-scalar input lower to a deterministic sequence of scalar events. UI intent and accepted UTF-16 transform batches may be retained in a separate capture/application wrapper, but do not enter event identity.

This selects the paper/Gate A scalar model rather than the initial UTF-16 event hypothesis. UTF-16 remains the correct editor boundary, but making it the event coordinate would leak one backend encoding into the event algebra and add a conversion on every EGW item-space operation.

## U0 — Existing positional responsibility map

### Current layers

| Layer | Current coordinate/text contract | Evidence |
|---|---|---|
| Browser/CodeMirror/text controls | UTF-16 code-unit positions; text controls normalize CRLF/lone CR to LF and require an explicit map back to canonical source | `adapters/editor`, `apps/loomark/internal/rabbita/raw_selection_transaction.mbt` |
| Loom syntax, SourceMap, `SpanEdit` | UTF-16 code-unit half-open ranges | [range/span decision](../decisions/2026-06-13-range-span-unit-boundaries.md), `modules/canopy/core/types.mbt` |
| Cursor/selection policy | UAX #29 grapheme boundaries may be validated or snapped at the editor shell | `modules/canopy/editor/sync_editor_text.mbt`, `deps/loom/moji` |
| Markdown receipt | Ordered UTF-16 transforms; transform 0 is relative to pre-commit text and each later transform is relative to the preceding result | `MarkdownTextTransform`, `MarkdownCommitReceipt::transforms()` |
| EGW Text façade | `Pos`/half-open `Range` in visible item space | `deps/event-graph-walker/text/types.mbt`, `text_doc.mbt` |
| EGW document | One visible item and one insert `Op` per Unicode scalar; non-BMP scalar is one item though it occupies two UTF-16 units | `internal/document/document.mbt`, `unicode_safety_wbtest.mbt` |
| Canonical Gate A model | One Unicode scalar and one `RawVersion` per insert; delete position is relative to parent-visible text | [Gate A plan](../plans/2026-08-12-egw-paper-aligned-text-event-admission.md) |
| Text commitment | Exact UTF-8 bytes, no Unicode or line-ending normalization | [capture receipt reassessment](2026-08-20-r0-capture-receipt-reassessment.md) |

The unit split is intentional. The editor uses UTF-16 because MoonBit `String`, browser selection APIs, and existing projections expose UTF-16 offsets. EGW uses scalar/item space because its replicated list element is one scalar.

### Existing malformed-text behavior

Current authoritative text ingress already chooses **well-formed Unicode text**:

- local `TextState` insert/replace rejects malformed UTF-16 before mutation;
- remote insert validation requires exactly one well-formed scalar per operation;
- sync JSON decode rejects a JSON string containing lone surrogates before structural parsing;
- internal document tests construct lone surrogates through unchecked UTF-16LE bytes and verify atomic rejection;
- `MarkdownEditor` maps the Text error to initialization/commit failure.

JavaScript can retain a lone surrogate in a `String`/JSON escape, while `TextEncoder` replaces it with U+FFFD. Therefore hashing after lossy UTF-8 conversion would silently change identity. R0 follows the existing rejection contract and never hashes a repaired string.

### Existing multi-span behavior

The general `SyncEditor::apply_span_edits` accepts an array of same-source `SpanEdit`s, sorts them in descending source order, and mutates once per edit. Diagnostic/structural layers may therefore produce more than one span.

The public Markdown portable commit currently treats zero/one projected transform as its successful shape and reports `UnexpectedTransformCount` otherwise. Its receipt is nevertheless vector-shaped and explicitly defines transforms as an ordered **sequential** fold. R0 must not freeze `event = one UTF-16 span` merely because today's façade usually emits one transform.

## U1 — Canonical text and coordinate contract

### Text domain

Canonical text is a sequence of Unicode scalar values:

- well-formed UTF-16 at MoonBit/editor ingress;
- strict UTF-8 in canonical event bytes and text hashes;
- no lone high or low surrogates;
- no NFC, NFD, NFKC, NFKD, line-ending, case, or grapheme normalization.

`"é"` and `"e\u0301"` are distinct text, distinct event payloads, and distinct hashes. CRLF remains two scalars. A ZWJ sequence remains its exact scalar sequence.

This follows the paper's event storage statement that one insert event contains one Unicode scalar encoded in UTF-8, [UAX #15](https://unicode.org/reports/tr15/) separation of normalization from encoding, and [RFC 8259 §8.2](https://www.rfc-editor.org/rfc/rfc8259#section-8.2)'s warning about unpaired-surrogate interoperability.

### Position domain

`ParentRelativeScalarPositionV1` is a canonical nonnegative integer in `0..<0x7fff_ffff`:

- insert is valid when `parent_scalar_length < 0x7fff_ffff` and `position <= parent_scalar_length`, so the resulting length remains representable;
- delete is valid when `position < parent_scalar_length`;
- undelete has no visible position and uses a dedicated target identity;
- canonical decode never clamps, rounds, wraps, or saturates;
- the test-only canonical fixture codec uses an unsigned varint and rejects values above MoonBit's signed 32-bit `Int` maximum before conversion;
- arithmetic validates `length <= total - start` after proving `start <= total`, never `start + length <= total`, to avoid overflow;
- before emitting any event, lowering proves `post_delete_scalar_length <= 0x7fff_ffff - inserted_scalar_count`; it never emits a valid prefix whose next position/text length would overflow.

MoonBit `Int` is signed 32-bit. JavaScript's larger safe-integer range is irrelevant: canonical acceptance is identical across targets.

### Coordinate base

A numeric event position is **explicitly defined** against the visible scalar sequence at the event's declared parent frontier. It is not an identity-relative anchor, destination-local LV, receiver-current position, or arbitrary snapshot position.

For a first local event after R0 restore, the pure validator returns an in-memory verified capability over the `R0SnapshotCommitV2` and its text bytes. This is not a second serialized snapshot/base DTO. The capture receipt owns `document_text_scalar_length` alongside text byte length/hash; this positional validator consumes and recomputes that committed field.

Validation proves:

1. `snapshot_commit_id` binds the resident text/hash and exact heads;
2. the first event's declared parents equal those exact heads as a set;
3. the UTF-16 request is converted against those exact resident text bytes;
4. the resulting scalar index is valid in that text.

`document_text_scalar_length` is the capture-receipt-owned derived snapshot field, recomputed from verified text during receipt validation and included in `snapshot_commit_id`. It makes the branch's canonical item-space length explicit and supports O(1) append-at-end checks; arbitrary offset conversion may still scan resident text.

A production/canonical event does **not** carry `snapshot_commit_id`. Snapshot commits are R0 capture artifacts, are not guaranteed to exist at every peer, and cannot replace a causal frontier—especially when the frontier has multiple heads. The capture wrapper binds the first event to the selected snapshot; the event itself remains portable by using its declared parents. Each following local scalar event is relative to the frontier/text produced by its predecessor.

This makes coordinate role explicit without duplicating the parent frontier in the body or coupling event identity to one storage publication.

## U2 — Canonical event and capture algebra

### Canonical event

```text
InsertScalar(position, scalar_utf8)
```

- payload decodes with strict `@encoding/utf8.decode`;
- decoded text contains exactly one scalar;
- every scalar uses 1–4 UTF-8 bytes, and a non-BMP scalar uses exactly 4;
- combining marks and ZWJ components are independent scalar events.

```text
DeleteScalar(position)
```

- deletes exactly one visible scalar in parent text;
- repeated deletes of a range use the same current scalar position as preceding deletes remove items.

```text
Undelete(target_identity)
```

- is a Canopy extension rather than an Eg-walker operation;
- uses a canonical causal target because deleted content has no visible position;
- its exact lookup/replay behavior is resolved by the [undelete after paper-branch restore](2026-08-21-r0-undelete-after-paper-branch-restore.md) (#1316): the target Insert is an explicit planner seed; indexed bounded replay with a disposable tracker; no persistent tombstone map or reverse index.

Canonical events contain no Fugue origins. Legacy left/right origins and delete targets are derived only inside the compatibility adapter and do not enter canonical event digest/metadata.

### Accepted transform wrapper

The adapter consumes accepted behavior, not an untrusted raw UI request. In R0's coordinated seams, EGW committed-operation evidence owns identities/membership while the Markdown receipt owns the accepted source effect; neither is reconstructed from the other by guessing:

```text
CanonicalCaptureBatchV1 {
  base_snapshot_commit_id
  transforms : NonEmptyArray[AcceptedSequentialUtf16SpliceV1]
}

AcceptedSequentialUtf16SpliceV1 {
  start_utf16
  end_utf16                 // half-open
  inserted_text
}
```

Each splice is relative to text after all prior transforms. This batch is formed only when accepted transforms explain a source-changing commit. If causal authority advances without an explanatory transform, the harness lifts authority-owned history through the canonical compatibility adapter or records a bounded negative; it never fabricates events from unchanged text.

For each splice, the pure lowering core:

1. verifies `0 <= start <= end <= current_text.length()` without overflowing;
2. rejects a start/end inside a surrogate pair;
3. verifies inserted text is well formed and does not normalize it;
4. converts start/end to scalar indices against current resident text;
5. counts inserted scalars and proves the complete post-splice scalar length and every emitted position remain within `0..0x7fff_ffff` before emitting anything;
6. emits deletes left-to-right as repeated `DeleteScalar(start_scalar)` events;
7. emits inserted scalars in order at `start_scalar`, `start_scalar + 1`, ...;
8. advances and returns the working text/frontier/event bytes plus comparison evidence.

The imperative test harness compares that returned evidence with authority-owned Markdown history and the independently replayed full-history oracle. The pure lowering core performs no provider/oracle I/O.

A splice with `start == end` and empty inserted text emits no event and is omitted. Replacing text with byte-identical text is not automatically a no-op if causal authority history advanced; the history receipt is the authority evidence and the full-history oracle independently checks it.

The wrapper is non-identity-bearing: its fields are excluded from canonical event digest. When two wrappers correspond to the same authority-owned canonical scalar-event sequence, grouping/provenance cannot change those event bytes. UI intent, IME, paste, backspace, and multi-cursor provenance may be retained by an application-owned outer envelope, whose representation is out of this EGW decision. If the test stores a capture batch, its `base_snapshot_commit_id` and selected immutable snapshot must be in the same bytes-only handoff so a batch from another snapshot cannot be substituted.

### Same-base span arrays

A same-source `Array[SpanEdit]` remains valid in the language/editor planning layer. It is not accepted directly by the canonical event codec. `SyncEditor::apply_span_edits` has an established descending-order mutation rule, but that generic path does not itself guarantee a Markdown sequential-transform receipt. Today's successful portable Markdown receipt has zero or one projected transform. R0 lowers only authority-reported accepted sequential transforms; future multi-transform support must add and test that shell receipt instead of inferring a sequence from planned spans.

This avoids inventing a second canonicalization for overlap, adjacency, same-position insertion ordering, or later edits that touch earlier inserted content. It also preserves the existing distinction:

```text
use-case/UI intent -> planned same-base spans -> accepted sequential transforms
                    -> canonical scalar events -> EGW admission
```

A replace lowers to multiple events and is not graph-atomic. This matches the paper and current EGW behavior. Run compression may store consecutive scalar events compactly without changing their identities.

### Canonical digest fields

This decision owns the canonical body bytes and their unchanged body digest:

```text
body_digest = SHA-256(
  domain("loomark-r0-event-body:v1")
  || exact canonical body bytes
)
```

The [capture receipt](2026-08-20-r0-capture-receipt-reassessment.md#event-digest-overlay) owns the complete `event_digest_v2` composition that binds this `body_digest`, rank, identity, parents, predecessor, and semantic references. This document does not duplicate that framing.

Canonical body bytes contain the kind plus parent-relative scalar position and exact length-prefixed UTF-8 scalar bytes for insert, the position for delete, or the undelete target identity. The undelete target's required kind (`RequiredReferencedKind`) and target event digest are additionally bound in its semantic-reference record. The target's actual kind is not asserted by the referring event; it is verified from the target's own authenticated metadata (`EventMetaV2`). Parent/reference identity order is unsigned bytewise lexical order of validated UTF-8 agent bytes, then numeric sequence.

Sequence zero has no predecessor. A semantic undelete target remains role-tagged even if it also appears in another dependency position.

## U3 — Cold-path proof contract

### Replay-set selection

Before any canonical encoding, the test-only preflight rejects malformed UTF-16 in **every** string field, including agent/document IDs, not only text payload. This is required because native UTF-8 encode aborts while the JS `TextEncoder` path replaces malformed input. Existing production `TextState` validates content but only requires a nonempty local agent ID; R0 records malformed identities as an unsupported/invalid candidate rather than widening production APIs.

Critical-base and conflict/replay-set selection is causal-graph planning. It uses authenticated metadata:

- identity/kind;
- declared parents;
- implicit predecessor;
- event digests;
- undelete target when relevant.

It does not inspect scalar position, inserted scalar, UTF-16 length, or neighboring text to choose which historical payload identities to fetch. Position-driven replay-set growth would violate the R0 provider contract.

Therefore `EventMetaV2` does **not** add inserted/deleted UTF-16 lengths for canonical text events. `payload_byte_length` remains encoded-body accounting, not text-effect length. Legacy origin references stay adapter-only; canonical `semantic_references` contains only the undelete target.

After the pure planner fixes the replay set, the shell fetches exactly those payloads. Temporary replay applies scalar events and converts resulting scalar effects to UTF-16 at the Markdown boundary.

### Boundary conversion APIs

Existing MoonBit core candidates fit the data shape:

- `String::length()` / `StringView::length()` — UTF-16 code-unit length;
- `String::char_length(start_offset?, end_offset?)` and `StringView::char_length()` — scalar count for verified well-formed ranges (signatures confirmed with `moon ide doc`);
- `String::offset_of_nth_char()` / `StringView::offset_of_nth_char()` — scalar index to UTF-16 offset; because they return `None` at the end boundary, adapters explicitly map `scalar_index == char_length` to `text.length()`;
- `String::get_view()` / `StringView::get_view()` — bounds- and surrogate-boundary-checked non-owning slices;
- `String::get_char()`, `String::code_unit_at()`, `Int::is_leading_surrogate()`, and `Int::is_trailing_surrogate()` — whole-string and endpoint validation;
- `String::view()` / `StringView` — non-owning slices only after validation;
- `@encoding/utf8.encode/decode`, `Bytes::length()`, and `BytesView` — strict canonical UTF-8 bytes;
- `Option`/`Result` — explicit invalid/out-of-range conversion rather than clamping;
- `Array::sort_by`, `Map`, and existing frontier helpers — stable parent/head handling.

No reusable public helper validates every arbitrary String field needed by the fixture codec: EGW's `is_well_formed_utf16` is package-private and content-specific. An executable-local preflight helper is therefore unavoidable; its sole responsibility is validating complete fixture strings before strict UTF-8 encoding, and cross-target tests pin identical rejection. Do not use `String::to_array()` merely to count/locate scalars; it allocates an O(text) character array. Do not add a manual UTF-16/scalar loop before checking the core methods above. The existing `utf16_offset_to_item_pos` is implementation precedent but clamps and returns the preceding item for a mid-surrogate offset; canonical capture must validate/reject before conversion rather than reuse its clamping semantics directly.

A plain-text implementation may use a rope/piece/run representation with scalar and UTF-16 aggregate lengths. That remains document state, not per-event identity/tombstone sidecar. Deleting the acceleration must change latency only, never accepted event bytes or text.

### Path assertions

| Path | Coordinate/payload behavior | Cold reads |
|---|---|---|
| First local event | Validate UTF-16 request against resident text, convert to scalar, parents = resident exact heads | metadata 0, payload 0 |
| Closed strict-forward | Every declared parent/reference and nonzero implicit predecessor resolves inside incoming events or resident exact head records; each predecessor is proven reachable through declared-parent closure; coverage reaches every resident head. A semantic reference whose target kind, identity-to-text mapping, or visible effect requires cold evidence is **not** closed strict-forward even when causal parents cover the heads | existing metadata 0, existing payload 0 |
| Indexed forward | Causal proof may read metadata; positions remain incoming payload | existing payload 0 |
| Genuine concurrency | Select bounded replay set from metadata, then fetch exactly its payloads | bounded metadata + selected payload |
| Sidecar removed | Recompute conversion from resident/temporary text | same event/text result; latency may differ |
| Fallback/oracle | Rebuild/replay complete canonical history | explicit full-history operation only |

Resident UTF-16 code units/scalars visited during conversion are counted separately from provider metadata/payload reads so an O(text) local conversion cannot masquerade as free.

## Required Gate matrix

### Gate U0 — Existing positional responsibility map

Record and test:

- browser/capture request unit;
- Markdown receipt unit and sequential-base rule;
- Loom/SourceMap range convention;
- EGW item-space unit;
- exact text hash/serialization encoding;
- current malformed-surrogate rejection;
- current zero/one/multi-span behavior.

### Gate U1 — Canonical text and coordinate contract

Pin:

- scalar canonical position;
- scalar-boundary validation;
- exact UTF-8/no-normalization text;
- malformed text rejection;
- half-open UTF-16 capture ranges;
- 32-bit canonical integer bound and overflow-safe validation;
- initial snapshot-to-parent-frontier binding;
- `document_text_scalar_length` receipt commitment.

### Gate U2 — Canonical event/capture algebra

Property-test:

- accepted UTF-16 splice -> scalar-event sequence -> expected text;
- deterministic scalar-event bytes across JS/native;
- replace/delete/insert lowering order;
- ordered sequential multi-transform fold;
- current zero/one Markdown receipts lower directly, while any future multi-transform receipt is tested as an authority-reported sequential fold; planned same-base spans never enter canonical lowering directly;
- no empty scalar event;
- one scalar per insert identity;
- canonical↔legacy adapter laws for the canonicalizable domain.

### Gate U3 — Cold-path proof

Prove:

- first local capture reads no provider metadata/payload;
- strict-forward reads no pre-existing metadata/payload;
- replay-set selection is metadata/causal-only;
- concurrency opens payloads only after the set is fixed;
- sidecar presence/absence preserves event bytes, text, frontier, and hash;
- full-history oracle matches text/effects on every case.

## Minimum probes

| Fixture | Required observation |
|---|---|
| `"AB"` | UTF-16 and scalar indexes coincide |
| `"A😀B"` | UTF-16 offsets `0,1,3,4` map to scalar indexes `0,1,2,3`; offset `2` rejects |
| `"e\u0301"` | offset between base/combining mark is scalar-valid in core; current grapheme UI may reject/snap it |
| ZWJ family sequence | every scalar boundary is core-valid; internal grapheme boundaries remain UI policy |
| regional-indicator pair | scalar operations may alter grapheme pairing; UI policy remains outside event algebra |
| CRLF and lone CR | no core normalization; DOM normalization map returns accepted canonical offsets |
| NFC/NFD pair | distinct bytes/events/hashes |
| empty range | insert if payload nonempty; no event if both range and payload empty |
| lone high/low surrogate in text or agent/document ID | reject before hashing/admission on JS and native |
| negative/`0x8000_0000`/overflowing length | reject before `Int` conversion/addition |
| ordered multi-transform case | each transform applies to the preceding result |

Existing characterization executed during this decision:

- EGW internal document Unicode `#31` suite: 9/9 on JS and 9/9 on native;
- Markdown UTF-16-filtered wbtests: 8/8 on JS;
- Loomark/Rabbita grapheme-filtered wbtests: 2/2 on JS.

These are evidence, not a substitute for the new canonical-event differential properties.

## Alternatives

| Alternative | Decision |
|---|---|
| Canonical UTF-16 code-unit position | Rejected: editor-specific encoding leaks into EGW, every operation needs item-space conversion, and mid-surrogate values require an extra invalid subdomain. UTF-16 remains the adapter unit. |
| Canonical UTF-8 byte offset | Rejected: text list elements are scalars, not bytes; variable-width byte indexing adds the wrong conversion boundary. |
| Canonical grapheme index | Rejected: grapheme segmentation is Unicode-version/UI policy and combines multiple replicated scalars. See [UAX #29](https://unicode.org/reports/tr29/). |
| Snapshot-commit ID as event coordinate base | Rejected: a storage receipt is not the causal parent frontier and may not exist at remote peers. Retained only in the initial capture wrapper. |
| Singular raw version as coordinate base | Rejected: a frontier can have multiple heads. |
| Multi-scalar splice as one canonical event | Rejected: violates one identity per scalar and hides non-atomic replace semantics. |
| Same-base multi-span canonical event | Rejected: duplicates editor planning semantics and introduces overlap/order/adjacency representations. A future multi-transform capture requires an authority-reported sequential receipt. |
| Normalize to NFC | Rejected: changes user bytes, event identity, and receipt hash. |
| Preserve lone surrogates as raw UTF-16 | Rejected: contradicts current authoritative ingress and strict UTF-8 canonical encoding. |
| Persist scalar↔UTF-16 per-character sidecar | Rejected: unnecessary for correctness and contrary to the paper branch. Run/rope aggregate lengths remain an allowed plain-text representation. |
| Put text-effect lengths in `EventMetaV2` now | Rejected: replay-set selection must be causal-only; effect fields are used after payload selection. #1315 confirmed the planner satisfies the causal-only proof. |

## Consequences

- The earlier Gate A one-scalar contract is affirmed, not replaced.
- The capture receipt binds `document_text_scalar_length` through `snapshot_commit_id`; this decision fixes its Unicode-scalar meaning.
- `EventMetaV2.semantic_references` is narrowed for canonical events to the undelete target; Fugue origins exist only in legacy adapter evidence.
- The test-only canonical fixture/body codec freezes scalar positions, not UTF-16 spans; no production wire codec is authorized.
- Markdown's ordered transform vector is the capture seam; raw browser intent and same-base planned spans remain imperative-shell inputs.
- Ticket #1315 is resolved by the [concurrency replay-base proof](2026-08-21-r0-concurrency-replay-base-proof.md): replay-set selection uses authenticated `EventMetaV2` causal metadata with V2 sidecar `causal_rank_timestamp` and one-colour waterline scan. The metadata consequence is confirmed, not reopened.
- Ticket #1316 is resolved by the [undelete after paper-branch restore](2026-08-21-r0-undelete-after-paper-branch-restore.md): undelete target is the original Insert identity as an explicit planner seed; indexed bounded replay with a disposable tracker; no persistent tombstone map or reverse index.
- No production archive, storage provider, Text/Markdown public API, or wire format changes are authorized by this decision.
