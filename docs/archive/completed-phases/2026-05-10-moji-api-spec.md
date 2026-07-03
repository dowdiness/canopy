# moji API specification — what canopy needs from a MoonBit UAX #29 library

**Status:** implemented in [#251](https://github.com/dowdiness/canopy/pull/251) — the moji library lives at `lib/moji/` and is wired into the editor's diff layer, cursor invariant, arrow-key API, and FFI variants per the per-call-site analysis below. Conformance: 1187/1187 GraphemeBreakTest + 1826/1826 WordBreakTest cases pass against Unicode 15.1.

The spec body is preserved as the pre-implementation design record; see TODO.md §16 for the per-item shipped notes and remaining follow-ups.

**Original audience:** moji author. Current audience: canopy maintainers
checking what shipped in #251 and what remains in TODO.md §16.

## Background

[Canopy](https://github.com/dowdiness/canopy) is an incremental
projectional editor with CRDT collaboration, written in MoonBit. At the
time this spec was written, the editor treated text positions as UTF-16
code-unit offsets without a grapheme-boundary invariant, which produced
a bimodal failure surface for non-ASCII inputs:

- **Surrogate pairs** (emoji, ZWJ sequences, regional-indicator flags)
  could reach mid-surrogate positions in lower parser/undo text-layer calls.
  Current status: the follow-up after #251 converted the `panic #216` probes
  into inspect-style behavior tests and restored the non-BMP §4.3
  cluster-fusing-cursor fixtures.
- **BMP combining marks** (NFD `"e\u{0301}"`) silently corrupt:
  `backspace` deletes only the trailing combining mark; the diff
  reports a 1-code-unit delete.

Closing both edges required UAX #29 grapheme-cluster awareness in the
editor layer. `lib/moji/` is the MoonBit library that now provides it.
This spec derives the minimum API surface canopy needed from a per-
call-site audit of every position-bearing surface in the editor.

The spec is API-only. moji's implementation strategy (table-driven vs
property-derived, which Unicode version to track, allocation choices)
is out of scope.

## TL;DR

Canopy's preferred required shape from moji is **four functions**:

| # | Function | Purpose |
|---|---|---|
| 1 | `prev_grapheme_boundary(text, pos) -> Int` *(at-or-before)* | Snap a UTF-16 offset back to the nearest grapheme-cluster boundary. |
| 2 | `next_grapheme_boundary(text, pos) -> Int` *(at-or-after)* | Snap forward. |
| 3 | `prev_word_boundary(text, pos) -> Int` *(at-or-before)* | UAX #29 word-boundary counterpart. |
| 4 | `next_word_boundary(text, pos) -> Int` *(at-or-after)* | UAX #29 word-boundary counterpart. |

Two ergonomics helpers (5, 6) and one optional reverse iterator (7):

| # | Function | Required? |
|---|---|---|
| 5 | `is_grapheme_boundary(text, pos) -> Bool` | nice-to-have |
| 6 | `grapheme_clusters(text) -> Iter[(Int, Int)]` | nice-to-have |
| 7 | `grapheme_clusters_reverse(text) -> Iter[(Int, Int)]` | optional |

5 and 6 are mathematically derivable from 1 and 2. List them only if
moji can provide them cheaply.

**Acceptable fallback shape** if accepting arbitrary UTF-16 offsets
(see §2.1) is too invasive: replace 1–4 with
`grapheme_boundaries(text) -> Array[Int]` and
`word_boundaries(text) -> Array[Int]`. Canopy then binary-searches
for point queries.

All `pos` arguments are UTF-16 code-unit offsets, matching MoonBit's
`String[Int]` indexing and CodeMirror 6's wire convention.

## 0. Layer responsibilities

Three position units coexist in canopy's text path. Boundary-snapping
alone does not make positions safe to pass to canopy's CRDT; canopy
needs an explicit conversion layer between moji and its CRDT.

| Layer | Unit | Source of truth |
|---|---|---|
| Editor public boundary | UTF-16 code-unit offset | CodeMirror 6 `iterChanges`, JS `String.length`, MoonBit `String[Int]` |
| Grapheme layer (new, via moji) | UTF-16 offset that is a grapheme-cluster boundary | moji's UAX #29 segmenter |
| Canopy CRDT (`@text.Pos`) | Item-space offset (one item per codepoint) | internal |

For ASCII the three coincide. For non-ASCII they diverge:

- `"a😀b"` → UTF-16 length 4, item-space length 3, grapheme-cluster
  count 3. UTF-16 offset 3 = item-space offset 2.
- `"a\u{1D165}"` (base `a` + Musical Symbol Combining Stem) → UTF-16
  length 3, item-space length 2, cluster count 1. The "non-BMP combining
  mark" case proves UTF-16 and item-space don't always coincide for
  combining-mark inputs.

The editor's bulk-splice seam needs two conversions per call, in order:

1. **UTF-16 → grapheme-aligned UTF-16** via moji.
2. **UTF-16 → item-space** via codepoint counting.

Step 2 is canopy's responsibility. moji has no opinion about CRDT
positions. moji's contribution is step 1.

## 0.5 Cursor-on-boundary invariant

Canopy's editor maintains an invariant: every time a user-initiated
text mutation runs (`insert`, `delete`, `backspace`, or any
`_and_record` variant), the editor cursor MUST be on a grapheme-
cluster boundary. This invariant is what makes the per-character
mutation paths grapheme-safe.

**How canopy preserves the invariant:**

| Operation | How |
|---|---|
| `move_cursor(pos)` | Pre-snap with `prev_grapheme_boundary`. |
| `insert(text)` | Pre-snap cursor before splice; **unconditional** post-snap with `next_grapheme_boundary` after splice. |
| `delete` / `backspace` | Pre-condition. Defense-in-depth pre-snap if violated. |
| `apply_text_edit_internal` (cursor-to-edit-end branch) | **Unconditional** post-snap of the new cursor against the new doc text. |
| `apply_text_edit_internal` (cursor-stays branch, used by `insert_at`/`delete_at`/`set_text_and_record`/span edits) | Clamp existing cursor to `[0, new_text.length()]`, then post-snap against the new doc text. |
| `undo` / `redo` | Does NOT preserve the invariant. Bounds-clamp only; defense-in-depth at the next mutation repairs it. |

**Why post-snap is unconditional**, even when the splice itself was
boundary-aligned: UAX #29 cluster formation can extend across the
splice point. Inserted content can fuse with surrounding clusters
and shift downstream boundaries:

- Doc `"🇯🇵🇺🇸"` (boundaries `0,4,8`). Splice `(4, 0, "🇮")` is
  on-boundary. After splice, doc `"🇯🇵🇮🇺🇸"` re-pairs RIs into
  `🇯🇵 / 🇮🇺 / 🇸` with boundaries `0,4,8,10`. Naive cursor
  `4 + 2 = 6` lands inside the new `🇮🇺` cluster.
- Doc `"👩💻"` (woman + laptop, two clusters, boundaries `0,2,4`),
  cursor `2`. `insert_at(2, "\u{200D}")` (ZWJ) is boundary-aligned.
  After splice, doc `"👩‍💻"` is one cluster (profession emoji),
  boundaries `0,5`. Cursor stays at `2`, now interior.
- Same risk class with virama insertions joining Indic consonants
  into a conjunct, or VS-16 promoting a text-style heart to emoji.

The unconditional post-snap on `new_text` covers all cases. Cost is
one moji call per splice. Performance is typically local (UAX #29
grapheme rules look back a small fixed window) but worst-case
proportional to the containing sequence for pathological RI/ZWJ/Extend
runs.

**Defense-in-depth repair when the invariant is violated** (e.g. by
undo, by an unmigrated caller, by an out-of-band cursor mutation).
Recommended direction is **toward the containing cluster** (Option B,
matching the splice policy in §1.1):

- Forward delete with interior cursor: snap cursor backward
  (`cursor = prev_grapheme_boundary(text, cursor)`); strict-step
  forward; deletes the containing cluster.
- Backspace with interior cursor: snap cursor forward
  (`cursor = next_grapheme_boundary(text, cursor)`); strict-step
  backward; also deletes the containing cluster.

The repair is hardening, not a hot path. With the invariant
maintained at every entry, interior cursors should be unreachable in
practice.

## 1. Per-call-site analysis

Each entry below identifies a canopy call site that depends on moji,
states the operation it needs, and shows which moji function
implements it.

### 1.1 Bulk-splice seam (`apply_text_edit_internal`)

The funnel for splices originating from external editors (CodeMirror
6, the markdown block-input textarea, the older ProseMirror bridge).
Receives `(start, deleted_len, inserted)` in UTF-16 code units.

**Operation: snap the splice to grapheme boundaries.** Policy splits
by operation type:

- **Pure insertion (`deleted_len == 0`):** snap `start` to a single
  boundary in one direction (recommended `prev` — insertion happens
  at the boundary before the requested position).
- **Replacement / deletion (`deleted_len > 0`):** snap `start` with
  `prev_grapheme_boundary`, snap `start + deleted_len` with
  `next_grapheme_boundary`. Round expansively — any partially-touched
  cluster is fully consumed.

The naive expansive-rule-for-everything approach is wrong for pure
insertion: in `"a😀b"`, inserting `"X"` at offset 2 with `deleted_len
= 0` would snap to `(1, 3)`, turning the insert into a replacement
that destroys the emoji.

After grapheme snap, canopy converts to item-space (§0 step 2) and
applies. Then the §0.5 unconditional post-snap of the cursor.

### 1.2 Per-character `insert(text)`

Bypasses the seam.

**Operation:** maintain the cursor on a grapheme boundary across
the insert.

Pre-snap cursor with `prev_grapheme_boundary`; splice; post-snap with
`next_grapheme_boundary`. The post-snap is unconditional for the same
reason as §1.1.

### 1.3 Per-character `delete()` (forward delete)

Bypasses the seam. Pre-condition: cursor on boundary (§0.5).

**Operation:** delete the entire grapheme cluster starting at the
cursor.

Strict-step formula from a boundary:
`right = next_grapheme_boundary(text, cursor + 1)` (clamped to
`<= text.length()`); deletion range is `cursor..<right`. The `+1` is
required because at-or-after of `cursor` itself returns `cursor` when
the invariant holds.

### 1.4 Per-character `backspace()`

Bypasses the seam. Pre-condition: cursor on boundary (§0.5).

**Operation:** delete the cluster ending at the cursor.

Strict-step formula:
`left = prev_grapheme_boundary(text, cursor - 1)` (clamped to `>= 0`);
deletion range is `left..<cursor`; new cursor is `left`.

### 1.5 `move_cursor(pos)`

**Operation:** snap the requested position to a grapheme boundary.

Direction is canopy's choice (see §6). Both
`prev_grapheme_boundary(text, pos)` (stable) and "compute both prev
and next, pick whichever has smaller code-unit distance" (mouse-click
intuition) are expressible from the two primitives.

### 1.6 `move_cursor_left/right_grapheme` and word variants

New API canopy needs to expose for arrow-key navigation.

**Operation:** strict step left/right by one cluster, or one word.

- Left grapheme: `prev_grapheme_boundary(text, cursor - 1)`, clamped
  to `>= 0`. If `cursor == 0`, no-op.
- Right grapheme: `next_grapheme_boundary(text, cursor + 1)`, clamped
  to `<= text.length()`. If `cursor == text.length()`, no-op.
- Word variants: same shape with `prev_word_boundary` /
  `next_word_boundary`.

The `pos ± 1` form requires moji to accept positions inside clusters
(see §2.1 offset-tolerance contract).

UAX #29 word boundaries appear at every transition between word
characters, whitespace, and punctuation. Editor word navigation
typically skips whitespace and may treat punctuation specially —
canopy will layer that policy on top of moji's raw boundaries.

### 1.7 `text_diff::find_common_prefix` / `find_common_suffix_after_prefix`

Used by canopy's text-diff for trimming the diff window before LCS.

**Operation:** longest common prefix and suffix at grapheme-cluster
granularity. Returns code-unit length (unchanged unit).

Walk both `grapheme_clusters` iterators in lockstep, comparing slices,
until divergence. The current byte-walk implementation can stop
between high and low surrogate (`"a😀"` vs `"a😁"` share `"a\uD83D"`,
returning prefix=2), producing a splice with a lone surrogate in
`inserted`. The grapheme-aware walk fixes this.

For the suffix walk, canopy materialises a forward boundary array
once and iterates in reverse. moji does not need to expose a reverse
iterator unless it's natural in the implementation.

### 1.8 `compute_split_block` — markdown Enter-mid-line

Splits a markdown block at a textarea cursor offset.

**Operation:** snap the offset to a grapheme boundary inside the
block's text span before computing the split.

`next_grapheme_boundary(source, split_pos)` (recommended direction:
split *after* the cluster the user pointed at; canopy will choose
direction at integration).

### 1.9 `text_diff::compute_edit` and `compute_text_change`

A text-diff utility module shared by canopy and several submodules.

**Operation:** compute a `(start, delete_len, inserted)` splice from
`(old_text, new_text)` that does not bisect any grapheme cluster.

Current byte/codeunit walk can return splices with lone surrogates
in `inserted` when the diverging codepoint is non-BMP. The fix walks
`grapheme_clusters` for both prefix and suffix scans, then reuses the
internal LCS for the diverging middle section.

The fix lives in canopy's leaf text-diff module; the submodules that
import it inherit the fix automatically (verified by inspection of
submodule import paths).

### 1.10 JS bridge (`bridge.ts::applySpliceChanges`)

Canopy's older ProseMirror bridge calls the editor's bulk-splice seam
with batched UTF-16 splices, maintaining a cumulative `posOffset`
across changes in a batch.

**Operation:** none on the JS side. The MoonBit seam handles
grapheme-snapping. The bridge calls the **exact-splice** variant of
the FFI (see §1.11) which rejects non-boundary splices via Bool
return. The bridge already aborts the batch on `false` and schedules
reconcile.

Silently snapping inside the seam would be unsafe: if the seam
expanded a splice (e.g. `deleteLen = 0` inside `"😀"` snapped to
`deleteLen = 2`), the JS-side `posOffset += insert.length - deleteLen`
bookkeeping would diverge for subsequent changes in the batch.

### 1.11 FFI variant naming

Two FFI entry points wrap `apply_text_edit_internal`. Their
documented semantics should distinguish the policies:

| FFI | Semantic name | Behaviour on non-boundary splice |
|---|---|---|
| `handle_text_intent_checked` | **"exact splice"** | Reject (`false`); doc unchanged. Caller maintains its own offset bookkeeping. |
| `handle_text_intent` | **"snap splice"** | Snap endpoints per §1.1 policy; apply. |
| `set_text` / `set_text_and_record` | "full replace" | No splice positions to validate; the doc-level diff is recomputed via §1.9. |

Future callers reading "checked" might assume "checked = bounds-
checked" and pick it from a non-batched context, then be surprised by
rejection. Or pick the unchecked variant from a batched context,
re-introducing the `posOffset` drift. Naming the semantics in the
doc-comments closes both gaps.

### Direction-ambiguity summary

Every snap involves a direction choice. Canopy decides per call site
at integration time; both directions are expressible from `prev_/
next_grapheme_boundary`.

| Site | Recommended direction |
|---|---|
| §1.1 splice — pure insertion | `prev` (snap point) |
| §1.1 splice — replacement, start | `prev` (round down) |
| §1.1 splice — replacement, end | `next` (round up) |
| §1.5 `move_cursor` | `prev` (stable) — alternative: nearest |
| §1.8 `compute_split_block` | `next` (split after) |

## 2. API surface

### 2.1 Required functions

```moonbit
/// Largest grapheme-cluster boundary `<= pos`. Returns `pos` if it
/// already is a boundary. Returns `0` if `pos <= 0`.
///
/// MUST accept any UTF-16 code-unit offset, including positions
/// inside surrogate pairs and inside multi-codepoint clusters.
/// MUST NOT abort on out-of-range positions; clamp to
/// `[0, text.length()]` and answer for the clamped value.
pub fn prev_grapheme_boundary(text : String, pos : Int) -> Int

/// Smallest grapheme-cluster boundary `>= pos`. Returns `pos` if it
/// already is a boundary. Returns `text.length()` if `pos >= text.length()`.
/// Same offset-tolerance contract.
pub fn next_grapheme_boundary(text : String, pos : Int) -> Int

/// Word-boundary counterparts per UAX #29 word segmentation.
/// Same offset-tolerance contract.
///
/// These return raw UAX #29 boundaries. Editor word-navigation
/// policy (skip whitespace, treat punctuation specially) layers on
/// top in canopy.
pub fn prev_word_boundary(text : String, pos : Int) -> Int
pub fn next_word_boundary(text : String, pos : Int) -> Int
```

**Offset-tolerance contract — preferred shape.** Canopy uses the
`pos ± 1` pattern for strict-step cursor movement (§1.3, §1.4, §1.6),
which intentionally passes positions inside clusters. The contract
above (accept any UTF-16 offset, including mid-surrogate / mid-
cluster) is the simplest API for canopy.

**Fallback contract — if moji can only segment well-formed codepoint
streams.** A pure UAX #29 implementation may not natively accept
arbitrary UTF-16 offsets (the algorithm is defined over codepoints,
not code units). If the offset-tolerance contract is too invasive,
an alternative shape that still covers every canopy call site:

```moonbit
/// Boundary array indexed by code-unit offset (sorted, deduplicated).
/// Always starts with `0` and ends with `text.length()`.
pub fn grapheme_boundaries(text : String) -> Array[Int]

/// Word-boundary counterpart.
pub fn word_boundaries(text : String) -> Array[Int]
```

Canopy then derives `prev_/next_*_boundary` and `is_*_boundary` by
binary-searching the array. Cost is O(n) memory per call (canopy can
cache per text-version) and O(log n) per query. The §0.5 cursor
invariant and the §1.3/§1.4 strict-step formulas continue to work;
the strict formulas become "binary-search for the first boundary
> `cursor`," which is well-defined for any integer cursor including
mid-cluster.

The trade is **simpler moji contract** (boundaries from a codepoint-
stream walk) vs. **more glue in canopy** (binary-search plus optional
per-version caching). The fallback is preferred over moji refusing
the offset-tolerance contract and forcing canopy to call `is_boundary`
before every `prev_/next_` query.

### 2.2 Ergonomics helpers (required-if-cheap)

```moonbit
/// True iff `pos` is a UAX #29 grapheme cluster boundary.
/// Endpoints `0` and `text.length()` are always boundaries.
/// Same offset-tolerance contract.
///
/// Derivable as `prev_grapheme_boundary(text, pos) == pos`. Listed
/// because it makes assertion sites read clearly.
pub fn is_grapheme_boundary(text : String, pos : Int) -> Bool

/// Iterate (start, end) UTF-16 code-unit ranges, one per cluster, in
/// forward order. Empty string yields zero items.
///
/// Derivable as a loop over `next_grapheme_boundary` from 0.
pub fn grapheme_clusters(text : String) -> Iter[(Int, Int)]
```

If the implementation cost is non-trivial, omit. Canopy can build
both from the two required primitives.

### 2.3 Reverse iteration — optional

```moonbit
// OPTIONAL — only if natural in moji's implementation:
pub fn grapheme_clusters_reverse(text : String) -> Iter[(Int, Int)]
```

Canopy's only consumer is the suffix-scan in §1.7 / §1.9. Canopy can
materialise a forward `Array[(Int, Int)]` of boundaries and iterate
it in reverse. If moji has a natural reverse-walk, it's a free
ergonomics win.

### 2.4 Driver mapping

| Function | Drivers |
|---|---|
| `prev_grapheme_boundary` | §0.5 backspace defense, §1.1 (replace start), §1.4 backspace strict step (`pos-1`), §1.5 cursor, §1.6 left arrow (`pos-1`), §1.7 (via iterator), §1.8 split, §1.9 diff prefix |
| `next_grapheme_boundary` | §0.5 forward-delete defense + cursor post-snap, §1.1 (insert point + replace end), §1.2 post-insert clamp, §1.3 forward delete strict step (`pos+1`), §1.5 cursor, §1.6 right arrow (`pos+1`), §1.7 (via iterator), §1.8 split, §1.9 diff prefix/suffix |
| `prev_word_boundary` | §1.6 left-by-word |
| `next_word_boundary` | §1.6 right-by-word |
| `is_grapheme_boundary` | §0.5 debug-build invariant assertion; test scaffolding |
| `grapheme_clusters` | §1.7, §1.9 prefix/suffix scan; future render-layer chunking |

## 3. Out of scope — explicitly NOT in this API

Listed so moji does not grow accidentally.

- **Normalization** (NFC, NFD, NFKC, NFKD). Application-level
  decision; canopy stores what the user typed.
- **Bidi (UAX #9).** Renderer's job.
- **Casing.** No call site uses it. Locale handling (Turkish dotted-I)
  is well beyond canopy's grapheme scope.
- **Display width / East Asian width.** Renderer's job.
- **Line / sentence boundaries.** Defer until a concrete driver
  appears.
- **Script / language detection / collation.**
- **Well-formedness validation.** Canopy's CRDT layer rejects
  malformed wire content; the editor trusts MoonBit `String` to be
  valid UTF-16.
- **Splice-boundary integrity** — checking that an inserted string
  doesn't fuse with surrounding text into an unintended cluster
  (e.g. regional indicator merging with neighbour). Canopy may layer
  this later by re-checking boundaries on the post-splice text using
  the primitives moji already exposes — no new moji function needed.
- **JS bindings.** moji is a MoonBit library. The JS side does not
  call moji directly.
- **CRDT position conversion.** UTF-16 ↔ item-space is canopy's
  responsibility (§0 step 2).

## 4. Test-vector requirements

These are the unicode fixture cases canopy will use to verify the
*integration* with moji, not what moji needs to prove internally
(moji's own tests presumably exercise UAX #29 reference data).

### 4.1 Grapheme boundary fixtures

| Category | Sample input | Expected boundaries (UTF-16 code units) | Why |
|---|---|---|---|
| ASCII | `"hello"` | `0,1,2,3,4,5` | Baseline. |
| BMP single | `"あ"`, `"中"` | `0,1` | Single-codeunit non-Latin. |
| BMP combining | `"e\u{0301}"` | `0,2` | Combining mark binds to base. |
| Precomposed equivalent | `"é"` (`U+00E9`) | `0,1` | Single codeunit; should not equal the previous case in code units even though they render the same. |
| Non-BMP single | `"😀"`, `"𠮷"` | `0,2` | Surrogate pair = one cluster of 2 codeunits. |
| Mixed | `"a😀b"` | `0,1,3,4` | Cluster boundaries skip surrogate interior. |
| ZWJ family | `"👨‍👩‍👦"` | `0,8` | Three emoji + two ZWJs collapse into one cluster. |
| Skin-tone modifier | `"👋🏽"` | `0,4` | Emoji + Fitzpatrick modifier. |
| Variation selector | `"❤️"` | `0,2` | Heart + VS-16 (text→emoji presentation). |
| RGI ZWJ profession | `"👩🏽‍💻"` | `0,7` | Emoji + skin tone + ZWJ + emoji. |
| Regional indicator | `"🇯🇵"` | `0,4` | Two RIs bond into one flag. |
| Two adjacent flags | `"🇯🇵🇺🇸"` | `0,4,8` | Pair-bonding stops every two RIs. |
| Hangul jamo (decomposed) | `"\u{1100}\u{1161}\u{11A8}"` | `0,3` | L+V+T jamo sequence forms one syllable cluster. |
| Hangul precomposed | `"각"` (`U+AC01`) | `0,1` | Single precomposed syllable; distinct from the decomposed jamo case even though they render the same. |
| Indic virama conjunct | `"क्ष"` (`U+0915 U+094D U+0937`) | `0,3` (per Unicode 15+) | Devanagari virama joins consonants. Version-sensitive — pin moji's Unicode version in the test. |
| CRLF | `"a\r\nb"` | `0,1,3,4` | CRLF is one cluster (UAX #29 GB3). |
| Empty | `""` | `0` (only boundary) | Edge case for both `prev_` and `next_`. |
| Leading combining | `"\u{0301}a"` | `0,1,2` | Combining mark with no base — degenerate but valid. |

### 4.2 Word-boundary fixtures

| Category | Sample input | Notes |
|---|---|---|
| Latin words | `"hello world"` | Boundaries at `0,5,6,11`. |
| CJK | `"日本語"` | Each character its own word per UAX #29. |
| Mixed script | `"hello 日本"` | Latin word + CJK word boundary. |
| Punctuation | `"don't"` | Apostrophe is part of the word per WB6. |
| Numeric | `"$3.14"` | Number cluster. |
| Hangul | `"안녕하세요"` | Each syllable is its own word at the UAX level. |

### 4.3 Splice-policy fixtures (drives §1.1 + §1.11)

**Snap-splice fixtures — drives `handle_text_intent` and the §1.1
policy split:**

| Operation | Input doc | Splice (UTF-16) | Expected post-policy splice |
|---|---|---|---|
| Pure insert mid-cluster | `"a😀b"` | `(2, 0, "X")` | `(1, 0, "X")` *(snap start to prev boundary, deleted_len stays 0)* |
| Pure insert on boundary | `"a😀b"` | `(1, 0, "X")` | `(1, 0, "X")` *(no change)* |
| Replace mid-cluster | `"a😀b"` | `(2, 1, "X")` | `(1, 2, "X")` *(start prev, end next)* |
| Replace on boundaries | `"a😀b"` | `(1, 2, "X")` | `(1, 2, "X")` *(no change)* |
| Delete mid-cluster | `"a😀b"` | `(2, 1, "")` | `(1, 2, "")` |

**Exact-splice fixtures — drives `handle_text_intent_checked`:**

| Operation | Input doc | Splice (UTF-16) | Expected result |
|---|---|---|---|
| Pure insert mid-cluster | `"a😀b"` | `(2, 0, "X")` | reject (`false`); doc unchanged |
| Pure insert on boundary | `"a😀b"` | `(1, 0, "X")` | accept; doc becomes `"aX😀b"` |
| Replace mid-cluster | `"a😀b"` | `(2, 1, "X")` | reject; doc unchanged |
| Replace on boundaries | `"a😀b"` | `(1, 2, "X")` | accept; doc becomes `"aXb"` |
| Delete mid-cluster | `"a😀b"` | `(2, 1, "")` | reject; doc unchanged |

**Cluster-fusing-cursor fixtures — drives §0.5 post-snap on both
`apply_text_edit_internal` branches:**

| Branch | Input doc | Cursor before | Splice (UTF-16) | Expected cursor after |
|---|---|---|---|---|
| cursor-to-edit-end | `"🇯🇵🇺🇸"` | any | `(4, 0, "🇮")` | `8` *(post-snap from naive `6`, snapped past `🇮🇺`)* |
| cursor-stays | `"👩💻"` | `2` | `(2, 0, "\u{200D}")` | `0` or `5` *(post-snap; new doc `"👩‍💻"` has only `0,5`)* |
| cursor-stays | `"a"` | `0` | `(1, 0, "\u{0301}")` | `0` *(stays at `0`, which is a boundary in `"a\u{0301}"`)* |

## 5. What this spec does not answer

- **moji's implementation strategy** — table-driven vs. property-
  derived vs. external Unicode data.
- **Performance characteristics.** Canopy call sites scan short
  strings or do single forward walks; O(n) point queries are fine.
- **Versioning policy** — which Unicode version moji tracks. Document
  on moji's side; canopy will pin in tests (especially Indic
  conjuncts, which moved between Unicode versions).
- **Allocation strategy** — tuple iterator vs. out-buffer.

## 6. Open questions canopy will resolve at integration

These are canopy-side decisions surfaced for moji's awareness — they
do not require input from the moji author, but they affect how canopy
will use moji's API.

### 6.1 Cursor unit-storage

Whether canopy stores `self.cursor` in UTF-16 (current), item-space,
or grapheme-ordinal after moji integrates. The recommended choice is
UTF-16 (smallest blast radius; moji's API is UTF-16-shaped regardless).
If canopy chooses item-space or grapheme-ordinal, the §1.2–§1.4
analyses are redone — moji's API is unaffected.

### 6.2 Direction defaults

Per the §1 direction-ambiguity summary, every snap site has a
recommended direction and an alternative. Canopy commits to the
recommendations during integration; moji's API is unaffected.

### 6.3 Word-navigation policy

UAX #29 word boundaries vs. editor "move by word" semantics
(skip-whitespace, treat punctuation specially, camelCase / snake_case
splitting). Canopy will spec the policy layer separately; moji
provides raw boundaries.

### 6.4 Smaller surface choices

- Whether to ship `is_grapheme_boundary` as part of moji's public
  API or have canopy derive it.
- Whether to ship `grapheme_clusters` or have canopy derive it.
- Whether to ship `is_word_boundary` for symmetry with grapheme.

These are nice-to-have ergonomics, derivable from the four required
functions if absent.

## Contact

This spec was derived from canopy issue
[#216](https://github.com/dowdiness/canopy/issues/216) "Unicode Text
Correctness." Canopy maintainer: see repo. Questions, pushback, or
counter-proposals welcome — particularly on §2.1 (offset-tolerance vs
fallback contract) and the §6 open questions, which inform how
canopy will integrate.
